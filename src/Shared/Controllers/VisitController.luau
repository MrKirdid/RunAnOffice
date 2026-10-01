local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local EmployeeController = require(Shared.Controllers.EmployeeController)
local Items = require(Shared.Utilities.Items)
local NetworkingClient = require(Shared.Networking.networkingClient)
local Offsets = require(Shared.Configs.Offsets)
local Parts = require(Assets.Parts)
local PlayerData = require(Shared.PlayerData).client
local PlotController = require(Shared.Controllers.PlotController)
local ScreenShakeController = require(Shared.Controllers.ScreenShakeController)
local SoundController = require(Shared.Controllers.SoundController)
local Tiers = require(Shared.Utilities.Tiers)
local TutorialController = require(Shared.Controllers.TutorialController)
local VfxController = require(Shared.Controllers.VfxController)

--> Everybody else's desks, drawn all the time so a base can be looked at from the street. The
--> server sends each base whole and every change to it after; this only stands the desks up where
--> the plot's markers say, sits whoever works there down at them, and hangs a steal prompt off
--> every employee. A prompt only works in the base the server says the player is stood in, and
--> the rigs of every other base type at a few frames a second and in silence, which is plenty
--> from the street and a fraction of the cost. Nothing here is read off anyone's save.

--> Kept apart from the player's own desks, which FloorsController hides and shows by the floor
--> being stood on. Somebody else's base shows every floor they own, so these are never hidden.
local ContainerName = "VisitingDesks"
local PlotContainerName = "PlotContainer"
local ComponentsName = "Components"

--> Same reach and hold as picking up off a pad: stealing is picking up, off somebody else's chair.
local PromptText = "Steal!"
local PromptHold = 1
local PromptDistance = 10

--> how often a base nobody here is stood in moves its rigs on: about two and a half frames a second
local FarStep = 0.4

type Record = {
	Floor: number,
	Slot: number,
	Computer: string?,
	Keyboard: string?,
	Monitor: string?,
	Employee: string?,
	EmployeeName: string?,
}

type Desk = {
	Owner: Player,
	Model: Model,
	Record: Record,
	Prompt: ProximityPrompt?,
	Track: AnimationTrack?,
	Speed: number,
	Sound: Sound?,
}

local VisitController = {
	--> Whose base the player is stood in, nil out in the street or at home: the only one whose
	--> employees can be stolen.
	Owner = nil :: Player?,

	Desks = {} :: { [string]: Desk },

	--> One theft in flight at a time, or two holds send two and the second always fails.
	Stealing = false,
}

local function DeskKey(Owner: Player, Floor: number, Slot: number): string
	return `{Owner.UserId}/{Floor}-{Slot}`
end

local function Same(A: Record, B: Record): boolean
	for _, Field in { "Computer", "Keyboard", "Monitor", "Employee", "EmployeeName" } do
		if (A :: any)[Field] ~= (B :: any)[Field] then
			return false
		end
	end

	return true
end

local function GetContainer(): Folder
	local Existing = workspace:FindFirstChild(ContainerName)

	if Existing then
		return Existing :: Folder
	end

	local Container = Instance.new("Folder")
	Container.Name = ContainerName
	Container.Parent = workspace

	return Container
end

local function HandsFull(): boolean
	return Items.IsHeld(PlayerData.Holding())
end

function VisitController:GetPlot(Owner: Player): Model?
	local Index = PlotController.Plots[Owner]
	local Container = workspace:FindFirstChild(PlotContainerName)
	local Plot = Index and Container and Container:FindFirstChild(tostring(Index))

	return if Plot and Plot:IsA("Model") then Plot else nil
end

function VisitController:RefreshPrompts()
	local Free = not HandsFull() and not self.Stealing

	for _, Desk in self.Desks do
		if Desk.Prompt and Desk.Prompt.Parent then
			Desk.Prompt.Enabled = Free and Desk.Owner == self.Owner
		end
	end
end

--> Full speed and sound in the base being stood in, and a held pose everywhere else that the
--> stepping in Start moves on.
function VisitController:_Wake(Desk: Desk)
	local Near = Desk.Owner == self.Owner

	if Desk.Track then
		Desk.Track:AdjustSpeed(if Near then Desk.Speed else 0)
	end

	if Desk.Sound then
		Desk.Sound.Playing = Near
	end
end

function VisitController:_Moved()
	self:RefreshPrompts()

	for _, Desk in self.Desks do
		self:_Wake(Desk)
	end
end

function VisitController:_Remove(Owner: Player, Floor: number, Slot: number)
	local Key = DeskKey(Owner, Floor, Slot)
	local Desk = self.Desks[Key]

	if not Desk then
		return
	end

	self.Desks[Key] = nil
	Desk.Model:Destroy()
end

--> Every desk of one base, or of every base.
function VisitController:Clear(Owner: Player?)
	for Key, Desk in self.Desks do
		if Owner and Desk.Owner ~= Owner then
			continue
		end

		self.Desks[Key] = nil
		Desk.Model:Destroy()
	end
end

--> A whole base as the server has it now: desks it no longer lists go, the rest are built or
--> left alone if nothing on them changed.
function VisitController:_Sync(Owner: Player, Records: { Record })
	local Listed = {}

	for _, Record in Records do
		Listed[DeskKey(Owner, Record.Floor, Record.Slot)] = true
		self:_Build(Owner, Record)
	end

	for Key, Desk in self.Desks do
		if Desk.Owner == Owner and not Listed[Key] then
			self.Desks[Key] = nil
			Desk.Model:Destroy()
		end
	end
end

--> The theft. The rig comes off the chair the moment the prompt is held, because the server tells
--> the visitor the desk changed before it answers the steal, and the rebuild off that would
--> destroy it anyway. The arms are drawn off the attribute the server writes, so there is nothing
--> to hand over here. Refused, the desk is rebuilt from the last record and the worker is back.
function VisitController:_Steal(Owner: Player, Record: Record, Model: Model)
	if Owner ~= self.Owner or self.Stealing or HandsFull() then
		SoundController:Play("Error")
		return
	end

	self.Stealing = true
	self:RefreshPrompts()

	Model:Destroy()

	NetworkingClient.Stealing.Steal
		.Invoke({
			Owner = Owner,
			Floor = Record.Floor,
			Slot = Record.Slot,
		})
		:andThen(function(Taken: { Name: string, Type: string })
			SoundController:Play("Confirm")
			ScreenShakeController:Shake(0.8)
			TutorialController:Notify(`Stole {Taken.Name} ({Taken.Type}). Yours once you are back in your base`)
		end)
		:catch(function(Problem)
			warn(`[Visit] {Problem}`)

			SoundController:Play("Error")

			local Desk = self.Desks[DeskKey(Owner, Record.Floor, Record.Slot)]

			if Desk then
				self:_Build(Owner, Desk.Record, true)
			end
		end)
		:finally(function()
			self.Stealing = false
			self:RefreshPrompts()
		end)
end

function VisitController:_AddPrompt(Desk: Desk, Root: BasePart, Model: Model)
	local Point = Instance.new("Attachment")
	Point.Name = "StealPoint"
	Point.Parent = Root

	local Record = Desk.Record
	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Name = "Steal"
	Prompt.ObjectText = Record.EmployeeName or ""
	Prompt.ActionText = PromptText
	Prompt.HoldDuration = PromptHold
	Prompt.MaxActivationDistance = PromptDistance
	Prompt.RequiresLineOfSight = false
	Prompt.Enabled = not HandsFull() and not self.Stealing and Desk.Owner == self.Owner
	Prompt.Parent = Point

	Prompt.Triggered:Connect(function()
		self:_Steal(Desk.Owner, Record, Model)
	end)

	Desk.Prompt = Prompt
end

--> Stands one desk up, or rebuilds what is on one already standing: the parts and whoever is sat
--> there. The desk model is kept across rebuilds so an employee being taken off it does not make
--> the whole desk blink, and a record that says what the desk already shows changes nothing.
function VisitController:_Build(Owner: Player, Record: Record, Force: boolean?)
	local Plot = self:GetPlot(Owner)
	local DeskCFrame = Plot and DeskPlacements.GetCFrame(Plot, Record.Floor, Record.Slot)

	if not DeskCFrame then
		return
	end

	local Key = DeskKey(Owner, Record.Floor, Record.Slot)
	local Desk = self.Desks[Key]

	if Desk and not Force and Same(Desk.Record, Record) and Desk.Model:FindFirstChild(ComponentsName) then
		return
	end

	if not Desk then
		local Model = Assets.Desk:Clone()

		Model:PivotTo(DeskCFrame)
		Model.Parent = GetContainer()

		Desk = { Owner = Owner, Model = Model, Record = Record, Speed = 1 }
		self.Desks[Key] = Desk
	end

	local Built = Desk :: Desk

	Built.Record = Record
	Built.Prompt = nil
	Built.Track = nil
	Built.Sound = nil

	local Existing = Built.Model:FindFirstChild(ComponentsName)

	if Existing then
		Existing:Destroy()
	end

	local Container = Instance.new("Folder")
	Container.Name = ComponentsName
	Container.Parent = Built.Model

	local Pivot = Built.Model:GetPivot()

	for Component, Offset in Offsets.Desk do
		local Variant = (Record :: any)[Component]

		if type(Variant) ~= "string" then
			continue
		end

		local Model: Model = Parts(Component, Variant)

		Model:PivotTo(Pivot * Offset)
		Model.Parent = Container

		VfxController:Aura(Model, (Tiers.FromVariant(Variant)))
	end

	local Type = Record.Employee

	if type(Type) ~= "string" then
		return
	end

	--> Sat in the same chair, with the same card, as the owner sees them. The rig lives with the
	--> parts, so the next rebuild takes it down with them.
	local Model, Root, _, Track, Sound = EmployeeController:BuildSeated(
		Type,
		Record.EmployeeName or Type,
		`{Type}_{Key}`,
		Pivot * Offsets.EmployeeDeskOffset,
		Container
	)

	Built.Track = Track
	Built.Speed = if Track then Track.Speed else 1
	Built.Sound = Sound

	self:_AddPrompt(Built, Root, Model)
	self:_Wake(Built)
end

function VisitController:Init()
	NetworkingClient.Visiting.Base.On(function(Base)
		self:_Sync(Base.Owner, Base.Desks)
	end)

	NetworkingClient.Visiting.Entered.On(function(Base)
		self.Owner = Base.Owner
		self:_Sync(Base.Owner, Base.Desks)
		self:_Moved()
	end)

	NetworkingClient.Visiting.DeskChanged.On(function(Change)
		if Change.Removed then
			self:_Remove(Change.Owner, Change.Desk.Floor, Change.Desk.Slot)
			return
		end

		self:_Build(Change.Owner, Change.Desk)
	end)

	NetworkingClient.Visiting.Left.On(function(Owner)
		if Owner == self.Owner then
			self.Owner = nil
			self:_Moved()
		end
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self:Clear(Player)

		if Player == self.Owner then
			self.Owner = nil
		end
	end)

	PlayerData.Holding.Changed(function()
		self:RefreshPrompts()
	end)
end

function VisitController:Start()
	--> the far rigs are held still and moved on a step at a time, so a street full of bases costs
	--> a handful of pose updates a second instead of one every frame
	task.spawn(function()
		while true do
			task.wait(FarStep)

			for _, Desk in self.Desks do
				local Track = Desk.Track

				if Desk.Owner == self.Owner or not Track or Track.Length <= 0 then
					continue
				end

				Track.TimePosition = (Track.TimePosition + FarStep * Desk.Speed) % Track.Length
			end
		end
	end)
end

return VisitController
