local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskController = require(Shared.Controllers.DeskController)
local DeskData = require(Shared.Utilities.DeskData)
local FloorsController = require(Shared.Controllers.FloorsController)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local SoundController = require(Shared.Controllers.SoundController)
local VfxController = require(Shared.Controllers.VfxController)

--> The wrapped gift that stands in for a part not rolled yet. Opening it is the roll.
local GiftImage = "rbxassetid://94439392463893"

--> Studs, because a BillboardGui's scale components are stud sizes rather than fractions. A gift is
--> what a desk is for, and one small enough to be tidy was one nobody noticed was there.
local ButtonSize = 4

--> What the parts a desk is built with stand in, so the gifts can be measured against the desk and
--> not against them.
local ComponentsName = "Components"

--> How high over the top of the desk the middle of a gift floats. To the middle rather than to the
--> bottom edge of the card, because the card is a square with the gift drawn to fit inside it and
--> the bottom of that square is mostly empty: holding the whole square clear of the desk stood the
--> gift half a card up in the air over it. This is the one number to move if they sit too high or
--> too low, and it does not move when the card is resized.
--> Every gift on a desk is at this one height whatever slot it is for. The three spots the parts
--> land on are a stud apart in height and are the middles of the parts rather than of the desk, so
--> a gift hung off its own spot ended up half inside the desk while the next one floated over it.
local Hover = 1.4

--> The drift: how far the gift rises off where it is planted, and how long it takes to get up there
--> and back. It rides above that spot rather than either side of it, so the height above is the
--> height it was given and never less. Small on purpose -- it is the difference between a decal on
--> the desk and something floating over it, not an animation.
local FloatDepth = 0.12
local FloatSpeed = 1.7

--> Rendering stops here. Three of these per desk over a full floor is a lot of furniture wearing
--> buttons, and none of it is worth looking at from across the office.
local ShowDistance = 34

local IdleScale = 1
local HoverScale = 1.12
local PressScale = 0.85

--> Where it springs to once opened. Scaled to nothing rather than switched off, so it leaves
--> rather than blinking out.
local BusyScale = 0

--> The kick given to the spring the moment the gift is opened, before it collapses: it swells
--> for a frame and then goes, which is the pop. The same kick brings a refused one back.
local Punch = 7

--> Loose enough to overshoot, which is what makes the pop read.
local Stiffness = 340
local Damping = 15

--> A frame this long is a tab that was in the background, and integrating it in one step throws
--> the spring somewhere it cannot recover from.
local MaxStep = 1 / 30

--> The idle breathe, so a gift that is doing nothing still reads as something to open.
local BreathSpeed = 2.2
local BreathDepth = 0.03

type Entry = {
	Floor: number,
	Slot: number,
	Component: string,

	Display: BillboardGui,
	Scale: UIScale,
	Anchor: Attachment,

	--> Where the gift is planted, before the hover is added to it, and how far along that hover it
	--> starts: three gifts rising and falling together read as one thing moving rather than three.
	Ground: Vector3,
	Phase: number,

	Value: number,
	Velocity: number,

	Hovered: boolean,
	Pressed: boolean,
	Busy: boolean,
}

type Set = {
	--> Which desk these were built against. A desk sold and bought back lands on the same id with a
	--> new model, and the old attachments went with the old one.
	Desk: Model,

	--> By component, so a slot rolling only takes its own gift down.
	Entries: { [string]: Entry },
}

--> A gift over every slot of a desk that has nothing on it yet. Pressing one opens it: the gift
--> pops out, the spin runs where it stood, and the part it rolled is what is left there. A slot
--> that holds a part has no gift, so a desk that has been fully opened wears none at all.
local DeskSlotController = {
	--> Keyed by desk, so a desk changing only touches its own three.
	Buttons = {} :: { [string]: Set },
}

local function GetGui(): PlayerGui
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

--> A gift stands out in the world off a BillboardGui in the PlayerGui rather than off anything on
--> the desk, so the sweep that hides the floors overhead never reached one: taking floor two away
--> took its desks with it and left three cards hanging in the sky over nothing.
--> The test is the desk's rather than the floor you are standing on: a gift belongs to a desk, and
--> it should be there exactly when that desk is. That is the same line FloorsController draws in
--> RefreshLoose -- your own floor and everything under it, and the whole plot while you are off it
--> entirely, which is what keeps them from all blinking out as you walk into the street.
--> Disabled rather than scaled away, so a gift on a floor you cannot see cannot be pressed either.
local function ShouldShow(Floor: number): boolean
	local Inside = FloorsController.Inside

	return Inside == nil or Floor <= Inside
end

--> How high the desk stands, in its own space. Measured off the model rather than off the offsets,
--> because those are the middles of the parts that go on it -- a monitor's is halfway up the
--> monitor -- and a gift planted at one would float at the height of a part instead of standing on
--> the desk. The parts already on it are left out, or a desk with two slots opened would plant its
--> last gift on top of a monitor. The reach is the part's three half extents projected onto the
--> desk's own up, which is its highest corner however it is turned.
local function DeskTop(Desk: Model): number
	local Pivot = Desk:GetPivot()
	local Top = 0

	for _, Object in Desk:GetDescendants() do
		if not Object:IsA("BasePart") or Object:FindFirstAncestor(ComponentsName) then
			continue
		end

		local Placed = Pivot:ToObjectSpace(Object.CFrame)
		local Half = Object.Size / 2

		local Reach = math.abs(Placed.RightVector.Y) * Half.X
			+ math.abs(Placed.UpVector.Y) * Half.Y
			+ math.abs(Placed.LookVector.Y) * Half.Z

		Top = math.max(Top, Placed.Position.Y + Reach)
	end

	return Top
end

--> Over the spot the part on this slot will stand, and up off the desk's own top: the across and
--> the along are the part's, the height is the desk's, so a plot pivoted into place carries its
--> gifts with it instead of leaving them standing at world height.
local function AnchorPosition(Desk: Model, Offset: CFrame, Top: number): Vector3
	local Spot = Offset.Position

	return (Desk:GetPivot() * CFrame.new(Spot.X, Top + Hover, Spot.Z)).Position
end

--> A BillboardGui only hands input to the buttons inside it when it is parented to the PlayerGui,
--> so the card lives there and Adornee is what puts it out in the world. Active has to be on for
--> both the billboard and the button; off on either one and the press lands on nothing.
local function BuildButton(Anchor: Attachment): (BillboardGui, ImageButton, UIScale)
	local Display = Instance.new("BillboardGui")
	Display.Name = "DeskSlot"
	Display.Size = UDim2.fromScale(ButtonSize, ButtonSize)
	Display.Adornee = Anchor
	Display.Active = true
	Display.AlwaysOnTop = false
	Display.ClipsDescendants = false
	Display.LightInfluence = 0
	Display.MaxDistance = ShowDistance

	--> Nothing rebuilds these on respawn, so they must not be thrown away on one.
	Display.ResetOnSpawn = false

	local Button = Instance.new("ImageButton")
	Button.Name = "Gift"
	Button.AnchorPoint = Vector2.new(0.5, 0.5)
	Button.Position = UDim2.fromScale(0.5, 0.5)
	Button.Size = UDim2.fromScale(1, 1)
	Button.BackgroundTransparency = 1
	Button.Image = GiftImage
	Button.ScaleType = Enum.ScaleType.Fit
	Button.Active = true

	--> Off on purpose: the darkening it does on press fights the spring, and the spring is the
	--> part of the press worth seeing.
	Button.AutoButtonColor = false
	Button.Parent = Display

	local Scale = Instance.new("UIScale")
	Scale.Scale = 0
	Scale.Parent = Button

	return Display, Button, Scale
end

local function Drop(Entry: Entry)
	Entry.Display:Destroy()
	Entry.Anchor:Destroy()
end

function DeskSlotController:_Clear(DeskID: string)
	local Set = self.Buttons[DeskID]

	if not Set then
		return
	end

	for _, Entry in Set.Entries do
		Drop(Entry)
	end

	self.Buttons[DeskID] = nil
end

function DeskSlotController:_Press(Entry: Entry)
	if Entry.Busy then
		return
	end

	Entry.Busy = true
	Entry.Pressed = false

	--> The pop: thrown outwards first, and the spring aiming at nothing pulls it back through to
	--> gone. This has to be visible before the spin blocks below, hence before the roll.
	Entry.Velocity = Punch

	--> Where the gift is standing rather than where the part will land, because this is the gift
	--> coming apart: it goes off with the pop, and both are gone before the spin starts.
	VfxController:Burst("Click", Entry.Anchor.WorldPosition)

	local Rolled = DeskController:RollSlot(Entry.Floor, Entry.Slot, Entry.Component)

	--> A spin runs for a couple of seconds, and a desk taken away underneath one takes its gifts
	--> with it. Nothing left to hand back to in that case.
	if not Entry.Display.Parent then
		return
	end

	--> Opened: the part it rolled is on the desk now, and the rebuild off that write takes this
	--> gift down for good. Left busy so nothing can press it in the frame before that lands.
	if Rolled then
		return
	end

	Entry.Busy = false

	SoundController:Play("Error")

	--> Refused, so the gift is still owed: it comes back the way it left, dropped to nothing and
	--> thrown at the mark hard enough to overshoot it.
	Entry.Value = BusyScale
	Entry.Velocity = Punch
end

function DeskSlotController:_Make(
	Floor: number,
	Slot: number,
	Component: string,
	Desk: Model,
	Host: BasePart,
	Offset: CFrame,
	Top: number
): Entry
	local Ground = AnchorPosition(Desk, Offset, Top)

	local Anchor = Instance.new("Attachment")
	Anchor.Name = `Slot_{Component}`
	Anchor.Parent = Host
	Anchor.WorldPosition = Ground

	local Display, Button, Scale = BuildButton(Anchor)

	local Entry: Entry = {
		Floor = Floor,
		Slot = Slot,
		Component = Component,

		Display = Display,
		Scale = Scale,
		Anchor = Anchor,

		--> Off the spot itself rather than a number kept per slot, so the three on one desk are
		--> spread apart by where they stand and two desks side by side are not in step either.
		Ground = Ground,
		Phase = Ground.X + Ground.Z,

		Value = 0,
		Velocity = 0,

		Hovered = false,
		Pressed = false,
		Busy = false,
	}

	Button.MouseEnter:Connect(function()
		Entry.Hovered = true

		if not Entry.Busy then
			SoundController:Play("Hover")
		end
	end)

	Button.MouseLeave:Connect(function()
		Entry.Hovered = false
		Entry.Pressed = false
	end)

	Button.MouseButton1Down:Connect(function()
		if Entry.Busy then
			return
		end

		Entry.Pressed = true
		SoundController:Play("Press")
	end)

	Button.MouseButton1Up:Connect(function()
		Entry.Pressed = false
	end)

	--> Spawned rather than run on the input thread: the roll waits on the server and then on a
	--> two second spin, and holding the input thread for that long swallows every other press.
	Button.Activated:Connect(function()
		task.spawn(function()
			self:_Press(Entry)
		end)
	end)

	--> Set before it is parented, or a gift built on a floor overhead is drawn for the frame between
	--> landing and the next refresh.
	Display.Enabled = ShouldShow(Floor)
	Display.Parent = GetGui()

	return Entry
end

--> Every gift on every desk against the floor now being stood in. Cheap enough to walk in full:
--> it runs when the floor changes and nowhere else, and a plot holds tens of these rather than
--> thousands.
function DeskSlotController:_Refresh()
	for _, Set in self.Buttons do
		for _, Entry in Set.Entries do
			Entry.Display.Enabled = ShouldShow(Entry.Floor)
		end
	end
end

--> Brings the gifts on one desk in line with its record: a gift over every slot with nothing on
--> it, and none over a slot that holds a part. Runs off every change to the desk, which is most
--> often a gift being opened, so the gifts already standing are kept rather than rebuilt -- the
--> one that was just opened is still there to be taken down, and the others do not pop in again.
function DeskSlotController:_Build(Floor: number, Slot: number)
	local DeskID = DeskController:GetDeskID(Floor, Slot)
	local Desk = DeskController.Desks[DeskID]
	local Record = DeskData.Get(PlayerData, Floor, Slot)
	local Components = Record and Record()

	if not Desk or type(Components) ~= "table" then
		self:_Clear(DeskID)
		return
	end

	local Standing = self.Buttons[DeskID]

	if Standing and Standing.Desk ~= Desk then
		self:_Clear(DeskID)
		Standing = nil
	end

	--> Any of them: the attachment only carries a world position, so which part of the desk holds
	--> it decides nothing except that it is thrown away when the desk is.
	local Host = Desk:FindFirstChildWhichIsA("BasePart", true)

	if not Host then
		return
	end

	local Set: Set = Standing or { Desk = Desk, Entries = {} }
	self.Buttons[DeskID] = Set

	--> Once for the desk rather than once per gift: all three stand on the same plane, and this
	--> walks every part of it to find that plane.
	local Top = DeskTop(Desk)

	for Component, Offset in Offsets.Desk do
		local Entry = Set.Entries[Component]

		if Components[Component] ~= nil then
			if Entry then
				Drop(Entry)
				Set.Entries[Component] = nil
			end

			continue
		end

		--> The hover is put back on this in Step, so the spot is written down rather than written
		--> straight onto the attachment.
		if Entry then
			Entry.Ground = AnchorPosition(Desk, Offset, Top)
			continue
		end

		Set.Entries[Component] = self:_Make(Floor, Slot, Component, Desk, Host, Offset, Top)
	end
end

--> Semi implicit Euler on a plain spring. Fusion drives the panels, but these are dozens of one
--> number springs built and thrown away with the desks they sit on, and a scope per gift is more
--> bookkeeping than the arithmetic it would be wrapping.
function DeskSlotController:Step(Delta: number, Clock: number)
	local Step = math.min(Delta, MaxStep)

	for _, Set in self.Buttons do
		for _, Entry in Set.Entries do
			local Goal

			if Entry.Busy then
				Goal = BusyScale
			elseif Entry.Pressed then
				Goal = PressScale
			elseif Entry.Hovered then
				Goal = HoverScale
			else
				Goal = IdleScale + math.sin(Clock * BreathSpeed) * BreathDepth
			end

			Entry.Velocity += (-Stiffness * (Entry.Value - Goal) - Damping * Entry.Velocity) * Step
			Entry.Value += Entry.Velocity * Step

			--> Clamped rather than allowed to go under: a negative scale turns the art inside out.
			Entry.Scale.Scale = math.max(Entry.Value, 0)

			--> The hover, added to where the gift is planted rather than tweened onto the
			--> attachment: the desk never moves, so this is the whole of it. Half a wave, so it
			--> only ever rises off the height it was planted at and never dips below it.
			local Rise = (math.sin(Clock * FloatSpeed + Entry.Phase) * 0.5 + 0.5) * FloatDepth

			Entry.Anchor.WorldPosition = Entry.Ground + Vector3.new(0, Rise, 0)
		end
	end
end

function DeskSlotController:Start()
	DeskController.ComponentsChanged:Connect(function(Floor: number, Slot: number)
		self:_Build(tonumber(Floor) :: number, tonumber(Slot) :: number)
	end)

	--> The same signal the desk picker rides. Walking upstairs and teleporting both come through it,
	--> so nothing here has to watch the character.
	FloorsController.FloorChanged:Connect(function()
		self:_Refresh()
	end)

	--> Whichever of the two controllers starts first: the sweep catches the desks that were already
	--> standing, the signal catches the rest.
	for DeskID in DeskController.Desks do
		local Floor, Slot = string.match(DeskID, "^(%d+)%-(%d+)$")

		if Floor and Slot then
			self:_Build(tonumber(Floor) :: number, tonumber(Slot) :: number)
		end
	end

	local Clock = 0

	RunService.RenderStepped:Connect(function(Delta: number)
		Clock += Delta

		self:Step(Delta, Clock)
	end)
end

return DeskSlotController
