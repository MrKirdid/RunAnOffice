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

--> Somebody else's desks, drawn while standing in their base and only then. The server decides
--> when that is and sends the desks itself; this only stands them up where the plot's markers say,
--> sits whoever works there down at them, and hangs a steal prompt off every employee. The parts
--> are furniture: they can be looked at and never taken. Nothing here is read off anyone's save.

--> Kept apart from the player's own desks, which FloorsController hides and shows by the floor
--> being stood on. Somebody else's base shows every floor they own, so these are never hidden.
local ContainerName = "VisitingDesks"
local PlotContainerName = "PlotContainer"
local ComponentsName = "Components"

--> Same reach and hold as picking up off a pad: stealing is picking up, off somebody else's chair.
local PromptText = "Steal!"
local PromptHold = 1
local PromptDistance = 10

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
	Model: Model,
	Record: Record,
}

local VisitController = {
	--> Whose base is being drawn, nil out in the street or at home.
	Owner = nil :: Player?,

	Desks = {} :: { [string]: Desk },

	--> Every steal prompt standing, so full hands can switch them all off at once.
	Prompts = {} :: { ProximityPrompt },

	--> One theft in flight at a time, or two holds send two and the second always fails.
	Stealing = false,
}

local function DeskKey(Floor: number, Slot: number): string
	return `{Floor}-{Slot}`
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
	local Enabled = not HandsFull() and not self.Stealing

	for Index = #self.Prompts, 1, -1 do
		local Prompt = self.Prompts[Index]

		if Prompt.Parent then
			Prompt.Enabled = Enabled
		else
			table.remove(self.Prompts, Index)
		end
	end
end

function VisitController:_Remove(Floor: number, Slot: number)
	local Key = DeskKey(Floor, Slot)
	local Desk = self.Desks[Key]

	if not Desk then
		return
	end

	self.Desks[Key] = nil
	Desk.Model:Destroy()
end

function VisitController:Clear()
	for Key, Desk in self.Desks do
		self.Desks[Key] = nil
		Desk.Model:Destroy()
	end

	table.clear(self.Prompts)
	self.Owner = nil
end

--> The theft. The rig comes off the chair the moment the prompt is held, because the server tells
--> the visitor the desk changed before it answers the steal, and the rebuild off that would
--> destroy it anyway. The arms are drawn off the attribute the server writes, so there is nothing
--> to hand over here. Refused, the desk is rebuilt from the last record and the worker is back.
function VisitController:_Steal(Record: Record, Model: Model)
	local Owner = self.Owner

	if not Owner or self.Stealing or HandsFull() then
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

			local Desk = self.Desks[DeskKey(Record.Floor, Record.Slot)]

			if Desk and self.Owner == Owner then
				self:_Build(Desk.Record)
			end
		end)
		:finally(function()
			self.Stealing = false
			self:RefreshPrompts()
		end)
end

function VisitController:_AddPrompt(Record: Record, Model: Model, Root: BasePart)
	local Point = Instance.new("Attachment")
	Point.Name = "StealPoint"
	Point.Parent = Root

	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Name = "Steal"
	Prompt.ObjectText = Record.EmployeeName or ""
	Prompt.ActionText = PromptText
	Prompt.HoldDuration = PromptHold
	Prompt.MaxActivationDistance = PromptDistance
	Prompt.RequiresLineOfSight = false
	Prompt.Enabled = not HandsFull() and not self.Stealing
	Prompt.Parent = Point

	Prompt.Triggered:Connect(function()
		self:_Steal(Record, Model)
	end)

	table.insert(self.Prompts, Prompt)
end

--> Stands one desk up, or rebuilds what is on one already standing: the parts and whoever is sat
--> there. The desk model is kept across rebuilds so an employee being taken off it does not make
--> the whole desk blink.
function VisitController:_Build(Record: Record)
	local Owner = self.Owner
	local Plot = Owner and self:GetPlot(Owner)
	local DeskCFrame = Plot and DeskPlacements.GetCFrame(Plot, Record.Floor, Record.Slot)

	if not DeskCFrame then
		return
	end

	local Key = DeskKey(Record.Floor, Record.Slot)
	local Desk = self.Desks[Key]

	if not Desk then
		local Model = Assets.Desk:Clone()

		Model:PivotTo(DeskCFrame)
		Model.Parent = GetContainer()

		Desk = { Model = Model, Record = Record }
		self.Desks[Key] = Desk
	end

	Desk.Record = Record

	local Existing = Desk.Model:FindFirstChild(ComponentsName)

	if Existing then
		Existing:Destroy()
	end

	local Container = Instance.new("Folder")
	Container.Name = ComponentsName
	Container.Parent = Desk.Model

	local Pivot = Desk.Model:GetPivot()

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
	local Model, Root = EmployeeController:BuildSeated(
		Type,
		Record.EmployeeName or Type,
		`{Type}_{Key}`,
		Pivot * Offsets.EmployeeDeskOffset,
		Container
	)

	self:_AddPrompt(Record, Model, Root)
end

function VisitController:Init()
	NetworkingClient.Visiting.Entered.On(function(Base)
		self:Clear()
		self.Owner = Base.Owner

		for _, Record in Base.Desks do
			self:_Build(Record)
		end
	end)

	NetworkingClient.Visiting.DeskChanged.On(function(Change)
		if Change.Owner ~= self.Owner then
			return
		end

		if Change.Removed then
			self:_Remove(Change.Desk.Floor, Change.Desk.Slot)
			return
		end

		self:_Build(Change.Desk)
	end)

	NetworkingClient.Visiting.Left.On(function(Owner)
		if Owner == self.Owner then
			self:Clear()
		end
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		if Player == self.Owner then
			self:Clear()
		end
	end)

	PlayerData.Holding.Changed(function()
		self:RefreshPrompts()
	end)
end

return VisitController
