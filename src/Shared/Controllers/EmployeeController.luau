local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local NetworkingClient = require(Shared.Networking.networkingClient)
local EmployeeMenuController = require(Shared.Controllers.EmployeeMenuController)
local PayPopupController = require(Shared.Controllers.PayPopupController)
local SoundController = require(Shared.Controllers.SoundController)
local PlotController = require(Shared.Controllers.PlotController)
local DeskData = require(Shared.Utilities.DeskData)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local EmployeeConfigs = require(Shared.Configs.Employees)
local Format = require(Shared.Utilities.Format)
local Tiers = require(Shared.Utilities.Tiers)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local Revenue = require(Shared.Utilities.Revenue)
local Rolling = require(Shared.Utilities.Rolling)
local ScreenShakeController = require(Shared.Controllers.ScreenShakeController)
local Store = require(Shared.Utilities.Store)
local TutorialConfigs = require(Shared.Configs.Tutorial)
local TutorialController = require(Shared.Controllers.TutorialController)

local ContainerName = "Employees"
local FallbackModel = "Tie Guy"
local RootName = "HumanoidRootPart"
local HeadName = "Head"

local InterpolationDelay = 0.2
local MaxSnapshots = 16
local TurnSmoothing = 9

local AnimationFade = 0.2
local WalkPlaybackSpeed = 0.98
local MoveEpsilon = 0.001

--> Fractions of the base speed each employee is allowed to drift by, drawn once when its track
--> starts. Small on purpose: enough that two of them side by side are visibly not the same
--> employee, small enough that nobody reads it as one being buffed.
local WalkSpeedSpread = 0.06
local TypeSpeedSpread = 0.1

--> How long a track may wait for its asset before the phase offset is given up on. Only the very
--> first of a kind ever waits at all; every one after it loads from cache on the same frame.
local PhaseWaitTimeout = 2

local Variation = Random.new()

local DisplayGap = 0.4

--> Gold on every employee, deliberately off the tier colour: the rarity line already carries the
--> tier, so the multiplier reads as money instead of repeating it.
local MultiplierColor = Color3.fromRGB(255, 215, 0)

--> A price is the one line a player acts on, so it is the only green on the card: far enough round
--> the wheel from the gold above it that the two never read as the same number.
local CostColor = Color3.fromRGB(88, 255, 128)

local PromptDistance = 14
local PromptHold = 0

--> Seats filled closer together than this are one event, which is what a swap landing looks like.
local SeatCueGap = 0.2

--> How close the camera has to be for one at a desk to answer the mouse. Further than the buy
--> prompt, since a desk is looked at from across the room rather than walked up to.
local ClickDistance = 40

--> A seat with parts missing from its desk: the employee is sat at nothing, so they are shown
--> waiting rather than typing at it, and wear this so the desk reads as the problem.
local IdleName = "Idle"
local IdleColor = Color3.fromRGB(255, 70, 70)
local IdleFill = 0.6
local IdleOutline = 0

--> Where in the typing loop the idle one is held: mid stroke, hands over the keys, so they read
--> as stopped rather than as never having started.
local FreezePoint = 0.5

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
	Floor: number,
	Slot: number,
	Position: Vector3,
	Head: BasePart,

	--> the typing loop and its sound, held so an emptied desk can stop them and a filled one
	--> start them again
	Track: AnimationTrack?,
	Sound: Sound?,
	Idle: boolean,

	--> the speed the loop was started at, with its own drift, to hand back after a freeze
	Speed: number,
}

--> A seat and what it is paying this tick, which is the only reason anything walks the office.
type Earner = {
	Seat: Seated,
	Rate: number,
}

local EmployeeController = {
	Employees = {} :: { [number]: Rendered },
	Seated = {} :: { [string]: Seated },

	--> when the seated cue last played, so two seats filling together sound once
	SeatCueClock = 0,

	--> Which desk the next payday sound comes out of. The whole office is paid on one tick, so
	--> sounding every earner would be a chord once a second; they take it in turns instead.
	PayCursor = 0,

	--> The balance the last payday sound was played against, so cash going out -- an employee
	--> bought, a node in the tree unlocked -- is not mistaken for cash coming in.
	Balance = nil :: number?,

	--> False until the desks a player logs back in to have been walked once. Everyone already at a
	--> desk is built during that sweep, and a seat sound on each of them is the whole office
	--> sitting down in the player's ear the moment they arrive.
	Ready = false,
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

--> Every type is named after its model, so a missing one is a config row without an asset rather
--> than something to fall back from silently.
local function GetModelTemplate(Type: string): Model
	local Folder = Assets:WaitForChild("Employees")
	local Template = Folder:FindFirstChild(Type)

	if not Template then
		warn(`[Employee] No model named {Type}, using {FallbackModel}`)
		Template = Folder:WaitForChild(FallbackModel)
	end

	return Template :: Model
end

local function GetRarity(Type: string): (string, Color3)
	local Chance = BaseOdds[Type]

	return Tiers.FromOdds(if Chance and Chance > 0 then 1 / Chance else math.huge)
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
	Frame.MultiplierLabel.TextColor3 = MultiplierColor
	Frame.CostLabel.TextColor3 = CostColor
	Frame.CostLabel.Visible = Cost ~= nil

	if Cost then
		Frame.CostLabel.Text = Format.Cash(Cost)
	end

	return Display
end

--> The head, not the root: the root sits at hip height, so a display hung off it floats over the
--> chest. Recursive because a rig can bury its head under a hat or an accessory model.
local function GetHead(Model: Model, Root: BasePart): BasePart
	local Head = Model:FindFirstChild(HeadName, true)

	return if Head and Head:IsA("BasePart") then Head else Root
end

--> SizeOffset lifts the whole card clear of its anchor point, and the world space offset raises
--> that point to the crown, so the card sits above the head rather than across it.
local function AttachDisplay(Display: BillboardGui, Anchor: BasePart)
	Display.Adornee = Anchor
	Display.SizeOffset = Vector2.new(0, 0.5)
	Display.StudsOffsetWorldSpace = Vector3.new(0, Anchor.Size.Y * 0.5 + DisplayGap, 0)
	Display.Parent = Anchor
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

--> One detector on the model covers every part of the rig. It needs the parts queryable, which
--> BuildModel switches off for the walkers so nothing on the map has to see them: a seated one is
--> furniture, and furniture is meant to be clicked.
local function BuildClickDetector(Model: Model): ClickDetector
	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.CanQuery = true
		end
	end

	local Detector = Instance.new("ClickDetector")
	Detector.Name = "Inspect"
	Detector.MaxActivationDistance = ClickDistance
	Detector.Parent = Model

	return Detector
end

--> How far the root sits above the soles, swept in world space. Model:GetBoundingBox orients its
--> box to the model's pivot, and this rig's root carries a quarter turn in its PivotOffset, so the
--> box's Y is the robot's width and the lift comes out a whole leg short.
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

--> Moves the whole rig so the root lands on Target. PivotTo alone will not do it: this rig's
--> pivot carries a quarter turn against the root, so pivoting to an upright CFrame lies it down.
local function PlaceRoot(Model: Model, Root: BasePart, Target: CFrame)
	Model:PivotTo(Target * Root.CFrame:Inverse() * Model:GetPivot())
end

--> Drops the track somewhere random inside its own loop so a row of employees is not stepping and
--> typing on the same frame as each other. Length is 0 until the asset is in, and setting
--> TimePosition against a zero length does nothing, so the wait is worth the one frame it costs.
local function OffsetPhase(Track: AnimationTrack)
	if Track.Length > 0 then
		Track.TimePosition = Variation:NextNumber() * Track.Length
		return
	end

	task.spawn(function()
		local Deadline = os.clock() + PhaseWaitTimeout

		while Track.Length <= 0 and Track.IsPlaying and os.clock() < Deadline do
			task.wait()
		end

		if Track.Length > 0 and Track.IsPlaying then
			Track.TimePosition = Variation:NextNumber() * Track.Length
		end
	end)
end

--> One animation each and no switching between them: a walking employee is always walking, right
--> up to the frame it is taken off the map, and a seated one is always typing. Speed goes through
--> Play rather than AdjustSpeed, because Play resets it to 1 either way, and carries a per-track
--> nudge either side of Speed so no two of them run at exactly the same rate.
local function PlayLoop(
	Model: Model,
	Animation: Animation,
	Speed: number,
	Fade: number,
	Spread: number
): AnimationTrack?
	--> The rigs hang their Animator off an AnimationController rather than a Humanoid, which is
	--> what a rig with nothing to simulate wants. Both are checked so either kind animates.
	local Controller = Model:FindFirstChildOfClass("AnimationController") or Model:FindFirstChildOfClass("Humanoid")
	local Animator = Controller and Controller:FindFirstChildOfClass("Animator")

	if not Animator then
		return nil
	end

	local Track = Animator:LoadAnimation(Animation)
	Track.Looped = true
	Track.Priority = Enum.AnimationPriority.Movement
	Track:Play(Fade, 1, Speed * (1 + Variation:NextNumber(-Spread, Spread)))
	OffsetPhase(Track)

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

	AttachDisplay(BuildDisplay(Data.Name, Data.Type, Data.Cost), GetHead(Model, Root))
	Prompt.Parent = Root

	PlayLoop(Model, AnimationFolder.Walking, WalkPlaybackSpeed, AnimationFade, WalkSpeedSpread)

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

	--> Turned down here as well as on the server, with the reason said, so a press the server would
	--> refuse is answered on the spot instead of with a bare error after a round trip.
	if PlayerData.Cash() < Employee.Cost then
		SoundController:Play("Error")
		TutorialController:Notify(TutorialConfigs.Notices.NoCash)
		return
	end

	if not DeskData.GetFreeSeat(PlayerData) then
		SoundController:Play("Error")
		TutorialController:Notify(TutorialConfigs.Notices.NoSeat)
		return
	end

	Employee.Prompt.Enabled = false

	return NetworkingClient.Employees.Buy.Invoke(UID):andThen(function(Bought: boolean)
		SoundController:Play(if Bought then "Purchase" else "Error")

		if Bought then
			ScreenShakeController:Shake(0.6)
			TutorialController:Notify(`Hired {Employee.Name} ({Employee.Type})`)
		end

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

	EmployeeMenuController:Register(Floor, Slot, nil)
end

--> One employee sat in a chair, with the card over their head, the typing loop and the typing
--> sound all running. Nothing about whose chair it is: the player's own seats and the desks of a
--> base being visited both build theirs through here, and the caller says where the rig lives.
--> The sound is hung off the root and left running for as long as the rig exists: whoever
--> destroys the model takes the sound with it.
function EmployeeController:BuildSeated(
	Type: string,
	Name: string,
	Label: string,
	Seat: CFrame,
	Parent: Instance
): (Model, BasePart, BasePart)
	local Model, Root = BuildModel(Type, Label)

	PlaceRoot(Model, Root, Seat)
	Model.Parent = Parent

	local Head = GetHead(Model, Root)

	AttachDisplay(BuildDisplay(Name, Type), Head)

	--> No fade in: a seated one is already typing the moment it is there, it never arrived.
	local Track = PlayLoop(Model, AnimationFolder.Typing, 1, 0, TypeSpeedSpread)
	local Sound = SoundController:Attach("Typing", Root)

	return Model, Root, Head, Track, Sound
end

--> Whether every part a desk earns off is standing on it.
local function IsStocked(Desk: any): boolean
	if type(Desk) ~= "table" then
		return false
	end

	for Component in Offsets.Desk do
		if not DeskData.IsPart(Desk[Component]) then
			return false
		end
	end

	return true
end

--> A seated employee with parts missing from the desk stops typing and goes red until the desk
--> is filled again: typing at an empty desk earns nothing, and it should look like it.
function EmployeeController:RefreshIdle(Floor: number, Slot: number)
	local Seat = self.Seated[SeatKey(Floor, Slot)]

	if not Seat then
		return
	end

	local Idle = not IsStocked(PlayerData.Floors[Floor].Desks[Slot]())

	if Idle == Seat.Idle then
		return
	end

	Seat.Idle = Idle

	local Existing = Seat.Model:FindFirstChild(IdleName)

	if Idle then
		--> frozen mid stroke rather than stopped: a stopped track drops the rig back to its bind
		--> pose, which is a mannequin, not somebody waiting on parts
		if Seat.Track then
			Seat.Track.TimePosition = Seat.Track.Length * FreezePoint
			Seat.Track:AdjustSpeed(0)
		end

		if Seat.Sound then
			Seat.Sound:Pause()
		end

		if not Existing then
			local Mark = Instance.new("Highlight")
			Mark.Name = IdleName
			Mark.FillColor = IdleColor
			Mark.OutlineColor = IdleColor
			Mark.FillTransparency = IdleFill
			Mark.OutlineTransparency = IdleOutline
			--> hidden by walls like the rig is, rather than drawn over everything from anywhere
			Mark.DepthMode = Enum.HighlightDepthMode.Occluded
			Mark.Parent = Seat.Model
		end

		return
	end

	if Seat.Track then
		Seat.Track:AdjustSpeed(Seat.Speed)
	end

	if Seat.Sound then
		Seat.Sound:Resume()
	end

	if Existing then
		Existing:Destroy()
	end
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
		self:RefreshIdle(Floor, Slot)
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

	local Seat = DeskCFrame * Offsets.EmployeeDeskOffset
	local Model, _Root, Head, Track, Sound =
		self:BuildSeated(Seated.Type, Seated.Name, `{Seated.Type}_{Key}`, Seat, GetContainer())

	--> A swap changes two seats in the same beat, and one cue for the pair is enough.
	if self.Ready and os.clock() - self.SeatCueClock > SeatCueGap then
		self.SeatCueClock = os.clock()
		SoundController:PlayAt("EmployeeSeated", Seat.Position)
	end

	--> The detector lives in the model and goes when the seat is emptied.
	local Detector = BuildClickDetector(Model)

	Detector.MouseHoverEnter:Connect(function()
		EmployeeMenuController:Hover(Floor, Slot, Model)
	end)

	Detector.MouseHoverLeave:Connect(function()
		EmployeeMenuController:Unhover(Model)
	end)

	Detector.MouseClick:Connect(function()
		EmployeeMenuController:Show(Floor, Slot)
	end)

	self.Seated[Key] = {
		Model = Model,
		Stamp = Stamp,
		Floor = Floor,
		Slot = Slot,
		Position = Seat.Position,
		Head = Head,
		Track = Track,
		Sound = Sound,
		Idle = false,
		Speed = if Track then Track.Speed else 1,
	}

	EmployeeMenuController:Register(Floor, Slot, Model)

	self:RefreshIdle(Floor, Slot)
end

--> Every seat that is actually paying, in a fixed order so the cursor below walks the office the
--> same way each tick instead of jumping about with the hash order. A desk with an employee but no
--> parts on it earns nothing, and something that earns nothing has no reason to be heard.
function EmployeeController:GetEarners(): { Earner }
	local Earners: { Earner } = {}

	--> What the tree, the shop and the friends here have raised the plot's whole take by. The
	--> server floors the plot total once rather than desk by desk, so these will not always add up
	--> to the amount that landed in the balance: what is shown over a desk is that desk's own
	--> share, not a slice of the payment.
	local Multiplier = Store.IncomeMultiplier(PlayerData, Players.LocalPlayer)

	for _, Seated in self.Seated do
		local Desk = PlayerData.Floors[Seated.Floor].Desks[Seated.Slot]()
		local Rate = if Desk then math.floor(Revenue.DeskRate(Desk) * Multiplier) else 0

		if Rate > 0 then
			table.insert(Earners, { Seat = Seated, Rate = Rate })
		end
	end

	table.sort(Earners, function(Left: Earner, Right: Earner): boolean
		if Left.Seat.Floor ~= Right.Seat.Floor then
			return Left.Seat.Floor < Right.Seat.Floor
		end

		return Left.Seat.Slot < Right.Seat.Slot
	end)

	return Earners
end

--> A card over every desk that paid, and a sound out of one of them. The cards are what the player
--> is looking at, so they all come up; the sound is the one thing that cannot overlap twenty ways
--> and still be a sound, so it takes its turn round the office instead.
--> Both are positional and PayPopupController drops anything out of range on its own, so a plot
--> earning on four floors only ever shows the floor being stood on.
function EmployeeController:Payday()
	local Earners = self:GetEarners()

	if #Earners == 0 then
		return
	end

	for _, Earner in Earners do
		PayPopupController:Show(Earner.Seat.Head, Earner.Rate)
	end

	self.PayCursor = (self.PayCursor % #Earners) + 1

	SoundController:PlayAt("EmployeePay", Earners[self.PayCursor].Seat.Position)
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

	--> Sounded here rather than inside Add, which is also what the join time sweep below goes
	--> through: everyone already walking the map would announce themselves at once on the way in.
	--> Positional and quiet, since one of these arrives every few seconds for the life of the
	--> server and is only worth hearing near the door they come in through.
	NetworkingClient.Employees.Added.On(function(Batch)
		for _, Data in Batch do
			local Known = self.Employees[Data.UID] ~= nil

			self:Add(Data)

			if not Known then
				SoundController:PlayAt("EmployeeSpawn", Data.Position)
			end
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

	--> Everything from here on is somebody actually sitting down rather than a seat being restored.
	self.Ready = true

	PlayerData.Floors.OnKeyAdded(function(Floor: number)
		WatchFloor(Floor)
	end)

	--> Off the balance rather than off a payday message: the server pays on its own clock and the
	--> only thing that reaches the client is the new number, which is all this needs. Only a rise
	--> counts, so buying an employee or a node does not ring the tills.
	self.Balance = if type(PlayerData.Cash()) == "number" then PlayerData.Cash() else nil

	PlayerData.Cash.Changed(function()
		local New = PlayerData.Cash()

		if type(New) ~= "number" then
			return
		end

		local Previous = self.Balance
		self.Balance = New

		if Previous and New > Previous then
			self:Payday()
		end
	end)

	task.spawn(function()
		local Existing = NetworkingClient.Employees.GetAll.Invoke():expect()

		for _, Data in Existing do
			self:Add(Data)
		end
	end)
end

return EmployeeController
