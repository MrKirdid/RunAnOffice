local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local NetworkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local EmployeeConfigs = require(Shared.Configs.Employees)
local Rarities = require(Shared.Configs.Rarities)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local Rolling = require(Shared.Utilities.Rolling)

local ContainerName = "Employees"

--> Stood in for when a type has no model of its own yet, which is every type that gets added
--> to Configs/Employees before its rig is imported.
local FallbackModel = "Robot"
local RootName = "HumanoidRootPart"
local HeadName = "Head"

local InterpolationDelay = 0.2
local MaxSnapshots = 16
local TurnSmoothing = 9

local AnimationFade = 0.2
local WalkPlaybackSpeed = 1.375
local MoveEpsilon = 0.001

local PromptDistance = 14
local PromptHold = 0

local AnimationFolder = Assets:WaitForChild("Animations"):WaitForChild("Employee")

local BaseOdds = Rolling.Chances(EmployeeConfigs, 1)

export type Spawn = {
	UID: number,
	Name: string,
	Type: string,
	Cost: number,
	Position: Vector3,
	Owner: Player?,
}

type Snapshot = {
	Time: number,
	Position: Vector3,
}

type Rendered = {
	UID: number,
	Name: string,
	Type: string,
	Cost: number,
	Owner: Player?,
	Model: Model,
	Root: BasePart,
	Prompt: ProximityPrompt,
	Lift: number,
	Snapshots: { Snapshot },
	Facing: Vector3,
}

--> A seated one is not a Rendered: it never moves, never carries a prompt and is not something
--> the server is simulating. Stamp is who is in the chair, so a desk changing its parts does not
--> rebuild the employee sat at it.
type Seated = {
	Model: Model,
	Stamp: string,
}

local EmployeeController = {
	Employees = {} :: { [number]: Rendered },
	Seated = {} :: { [string]: Seated },
}

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

local function GetModelTemplate(Type: string): Model
	local Folder = Assets:WaitForChild("Employees")

	return (Folder:FindFirstChild(Type) or Folder:WaitForChild(FallbackModel)) :: Model
end

local function GetRarity(Type: string): (string, Color3)
	local Chance = BaseOdds[Type]
	local Odds = if Chance and Chance > 0 then 1 / Chance else math.huge

	for _, Tier in Rarities.Tiers do
		if Odds <= Tier.Ceiling then
			return Tier.Name, Tier.Color
		end
	end

	local Last = Rarities.Tiers[#Rarities.Tiers]

	return Last.Name, Last.Color
end

local function FormatValue(Value: number): string
	local Text = string.format("%.2f", Value)

	Text = string.gsub(Text, "0+$", "")
	Text = string.gsub(Text, "%.$", "")

	return Text
end

--> No Cost on one already sat at a desk: it is not for sale, so the label comes off rather than
--> printing a price nobody can act on.
local function BuildDisplay(Name: string, Type: string, Cost: number?): BillboardGui
	local Display = Assets:WaitForChild("UI"):WaitForChild("EmployeeDisplay"):Clone() :: BillboardGui
	local Frame = Display.Frame

	local Config = EmployeeConfigs[Type]
	local TierName, TierColor = GetRarity(Type)

	Frame.NameLabel.Text = Name
	Frame.RarityLabel.Text = TierName
	Frame.RarityLabel.TextColor3 = TierColor
	Frame.MultiplierLabel.Text = FormatValue(if Config then Config.Value else 1) .. "x"
	Frame.MultiplierLabel.TextColor3 = TierColor
	Frame.CostLabel.Visible = Cost ~= nil

	if Cost then
		Frame.CostLabel.Text = "$" .. Cost
	end

	return Display
end

local function BuildPrompt(Data: Spawn): ProximityPrompt
	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Name = "Buy"
	Prompt.ObjectText = Data.Name
	Prompt.ActionText = `Buy ${Data.Cost}`
	Prompt.HoldDuration = PromptHold
	Prompt.MaxActivationDistance = PromptDistance
	Prompt.RequiresLineOfSight = false

	return Prompt
end

--> How far the root sits above the soles, swept in world space. Model:GetBoundingBox orients its
--> box to the model's pivot, and a rig whose root carries a quarter turn in its PivotOffset would
--> otherwise measure the robot's width as its height and come out a whole leg short.
local function GetLift(Model: Model, Root: BasePart): number
	local Lowest = math.huge

	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") then
			local Size = Descendant.Size
			local Frame = Descendant.CFrame

			local Half = 0.5
				* (
					math.abs(Frame.RightVector.Y) * Size.X
					+ math.abs(Frame.UpVector.Y) * Size.Y
					+ math.abs(Frame.LookVector.Y) * Size.Z
				)

			Lowest = math.min(Lowest, Descendant.Position.Y - Half)
		end
	end

	return if Lowest < math.huge then Root.Position.Y - Lowest else 0
end

local function BuildModel(Type: string, Label: string): (Model, BasePart, number)
	local Model = GetModelTemplate(Type):Clone()
	Model.Name = Label

	local Root = Model:FindFirstChild(RootName) or Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true)

	if not Root or not Root:IsA("BasePart") then
		Model:Destroy()
		error(`[Employee] {Label} has no root part`)
	end

	Model.PrimaryPart = Root

	--> Editor leftovers on the rig, a couple of hundred keyframes cloned onto every spawn.
	local AnimSaves = Model:FindFirstChild("AnimSaves")

	if AnimSaves then
		AnimSaves:Destroy()
	end

	local Humanoid = Model:FindFirstChildOfClass("Humanoid")

	if Humanoid then
		Humanoid.EvaluateStateMachine = false
	end

	--> Only the root is anchored, and only the root is moved. The limbs hang off it through the
	--> rig's own joints, which is what leaves the Animator free to drive them: anchoring every
	--> part pins the whole rig and no animation can shift it.
	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.Anchored = Descendant == Root
			Descendant.CanCollide = false
			Descendant.CanQuery = false
			Descendant.CanTouch = false
			Descendant.Massless = true
		end
	end

	return Model, Root, GetLift(Model, Root)
end

--> Moves the whole rig so the root lands on Target. Written the long way rather than as a plain
--> PivotTo because a rig whose pivot carries a turn against its root would be laid on its side by
--> pivoting to an upright CFrame. Collapses to PivotTo(Target) once PivotOffset is cleared.
local function PlaceRoot(Model: Model, Root: BasePart, Target: CFrame)
	Model:PivotTo(Target * Root.CFrame:Inverse() * Model:GetPivot())
end

--> One animation each and no switching between them: a walking employee is always walking, right
--> up to the frame it is taken off the map, and a seated one is always typing. Speed goes through
--> Play rather than AdjustSpeed, because Play resets it to 1 either way.
--> The rigs carry an AnimationController rather than a Humanoid, so there is no state machine and
--> no physics to pay for. Humanoid is still accepted because a rig that has not been converted
--> yet would otherwise silently never animate.
local function PlayLoop(Model: Model, Animation: Animation, Speed: number, Fade: number): AnimationTrack?
	local Rig = Model:FindFirstChildOfClass("AnimationController") or Model:FindFirstChildOfClass("Humanoid")
	local Animator = Rig and Rig:FindFirstChildOfClass("Animator")

	if not Animator then
		return nil
	end

	local Track = Animator:LoadAnimation(Animation)
	Track.Looped = true
	Track.Priority = Enum.AnimationPriority.Movement
	Track:Play(Fade, 1, Speed)

	return Track
end

local function RefreshPrompt(Employee: Rendered)
	Employee.Prompt.Enabled = Employee.Owner ~= Players.LocalPlayer
end

local function Sample(Snapshots: { Snapshot }, RenderTime: number): (Vector3, Vector3)
	while #Snapshots > 2 and Snapshots[2].Time <= RenderTime do
		table.remove(Snapshots, 1)
	end

	local From = Snapshots[1]
	local To = Snapshots[2]

	if not To then
		return From.Position, Vector3.zero
	end

	local Span = To.Time - From.Time
	local Alpha = if Span > 0 then math.clamp((RenderTime - From.Time) / Span, 0, 1) else 1

	return From.Position:Lerp(To.Position, Alpha), To.Position - From.Position
end

function EmployeeController:Add(Data: Spawn): Rendered?
	if self.Employees[Data.UID] then
		return self.Employees[Data.UID]
	end

	local Model, Root, Lift = BuildModel(Data.Type, `{Data.Type}_{Data.UID}`)
	local Prompt = BuildPrompt(Data)

	PlaceRoot(Model, Root, CFrame.new(Data.Position + Vector3.new(0, Lift, 0)))
	Model.Parent = GetContainer()

	BuildDisplay(Data.Name, Data.Type, Data.Cost).Parent = Model:FindFirstChild(HeadName) or Root
	Prompt.Parent = Root

	PlayLoop(Model, AnimationFolder.Walking, WalkPlaybackSpeed, AnimationFade)

	local Employee: Rendered = {
		UID = Data.UID,
		Name = Data.Name,
		Type = Data.Type,
		Cost = Data.Cost,
		Owner = Data.Owner,
		Model = Model,
		Root = Root,
		Prompt = Prompt,
		Lift = Lift,
		Snapshots = { { Time = os.clock(), Position = Data.Position } },
		Facing = Root.CFrame.LookVector * Vector3.new(1, 0, 1),
	}

	self.Employees[Data.UID] = Employee
	RefreshPrompt(Employee)

	Prompt.Triggered:Connect(function()
		self:Buy(Data.UID)
	end)

	return Employee
end

function EmployeeController:Remove(UID: number)
	local Employee = self.Employees[UID]

	if not Employee then
		return
	end

	self.Employees[UID] = nil
	Employee.Model:Destroy()
end

function EmployeeController:SetTarget(UID: number, Position: Vector3)
	local Employee = self.Employees[UID]

	if not Employee then
		return
	end

	table.insert(Employee.Snapshots, { Time = os.clock(), Position = Position })

	while #Employee.Snapshots > MaxSnapshots do
		table.remove(Employee.Snapshots, 1)
	end
end

function EmployeeController:SetOwner(UID: number, Owner: Player?)
	local Employee = self.Employees[UID]

	if not Employee then
		return
	end

	Employee.Owner = Owner
	RefreshPrompt(Employee)
end

function EmployeeController:Buy(UID: number)
	local Employee = self.Employees[UID]

	if not Employee then
		return
	end

	Employee.Prompt.Enabled = false

	return NetworkingClient.Employees.Buy.Invoke(UID):andThen(function()
		if self.Employees[UID] then
			RefreshPrompt(Employee)
		end
	end)
end

local function SeatKey(Floor: number, Slot: number): string
	return `{Floor}-{Slot}`
end

function EmployeeController:RemoveSeated(Floor: number, Slot: number)
	local Key = SeatKey(Floor, Slot)
	local Existing = self.Seated[Key]

	if not Existing then
		return
	end

	self.Seated[Key] = nil
	Existing.Model:Destroy()
end

--> Rebuilt only when the person in the chair changes. Swapping a desk's monitor fires the same
--> Changed as sitting down does, and rebuilding on every one of those restarts the animation.
function EmployeeController:RefreshSeat(Floor: number, Slot: number)
	local Key = SeatKey(Floor, Slot)
	local Desk = PlayerData.Floors[Floor].Desks[Slot]()
	local Seated = Desk and Desk.Employee
	local Stamp = Seated and `{Seated.Type}|{Seated.Name}` or nil
	local Existing = self.Seated[Key]

	if (Existing and Existing.Stamp or nil) == Stamp then
		return
	end

	self:RemoveSeated(Floor, Slot)

	if not Seated or not Stamp then
		return
	end

	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local DeskCFrame = DeskPlacements.GetCFrame(Plot, tonumber(Floor) :: number, tonumber(Slot) :: number)

	if not DeskCFrame then
		return
	end

	local Model, Root = BuildModel(Seated.Type, `{Seated.Type}_{Key}`)

	PlaceRoot(Model, Root, DeskCFrame * Offsets.EmployeeDeskOffset)
	Model.Parent = GetContainer()

	BuildDisplay(Seated.Name, Seated.Type).Parent = Model:FindFirstChild(HeadName) or Root

	--> No fade in: a seated one is already typing the moment it is there, it never arrived.
	PlayLoop(Model, AnimationFolder.Typing, 1, 0)

	self.Seated[Key] = { Model = Model, Stamp = Stamp }
end

function EmployeeController:Step(Delta: number, Parts: { BasePart }, CFrames: { CFrame })
	local RenderTime = os.clock() - InterpolationDelay
	local TurnBlend = 1 - math.exp(-TurnSmoothing * Delta)

	table.clear(Parts)
	table.clear(CFrames)

	for _, Employee in self.Employees do
		local Position, Segment = Sample(Employee.Snapshots, RenderTime)

		Segment *= Vector3.new(1, 0, 1)

		if Segment.Magnitude > MoveEpsilon then
			Employee.Facing = Employee.Facing:Lerp(Segment.Unit, TurnBlend)
		end

		if Employee.Facing.Magnitude < MoveEpsilon then
			Employee.Facing = Vector3.new(0, 0, -1)
		end

		local Base = Position + Vector3.new(0, Employee.Lift, 0)

		table.insert(Parts, Employee.Root)
		table.insert(CFrames, CFrame.lookAt(Base, Base + Employee.Facing.Unit))
	end

	if #Parts > 0 then
		workspace:BulkMoveTo(Parts, CFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EmployeeController:Start()
	local Parts: { BasePart } = {}
	local CFrames: { CFrame } = {}

	NetworkingClient.Employees.Added.On(function(Batch)
		for _, Data in Batch do
			self:Add(Data)
		end
	end)

	NetworkingClient.Employees.Moved.On(function(Batch)
		for _, Update in Batch do
			self:SetTarget(Update.UID, Update.Position)
		end
	end)

	NetworkingClient.Employees.Removed.On(function(Batch)
		for _, UID in Batch do
			self:Remove(UID)
		end
	end)

	NetworkingClient.Employees.OwnerChanged.On(function(Batch)
		for _, Update in Batch do
			self:SetOwner(Update.UID, Update.Owner)
		end
	end)

	RunService.RenderStepped:Connect(function(Delta: number)
		self:Step(Delta, Parts, CFrames)
	end)

	--> Seats come off replicated data rather than off the wire, so a player who logs back in finds
	--> their employees already typing without anything having to be told to spawn them.
	local WatchDesk = function(Floor: number, Slot: number)
		PlayerData.Floors[Floor].Desks[Slot].Changed(function()
			self:RefreshSeat(Floor, Slot)
		end)
	end

	local WatchFloor = function(Floor: number)
		local Desks = PlayerData.Floors[Floor].Desks

		for Slot in Desks() do
			WatchDesk(Floor, Slot)
			self:RefreshSeat(Floor, Slot)
		end

		Desks.OnKeyAdded(function(Slot: number)
			WatchDesk(Floor, Slot)
			self:RefreshSeat(Floor, Slot)
		end)

		Desks.OnKeyRemoved(function(Slot: number)
			self:RemoveSeated(Floor, Slot)
		end)
	end

	for Floor in PlayerData.Floors() do
		WatchFloor(Floor)
	end

	PlayerData.Floors.OnKeyAdded(function(Floor: number)
		WatchFloor(Floor)
	end)

	task.spawn(function()
		local Existing = NetworkingClient.Employees.GetAll.Invoke():expect()

		for _, Data in Existing do
			self:Add(Data)
		end
	end)
end

return EmployeeController
