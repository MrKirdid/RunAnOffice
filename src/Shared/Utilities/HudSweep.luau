local Workspace = game:GetService("Workspace")

--> The hud leaves the screen through its own edges rather than switching Visible off. Visible off
--> is a cut, and a cut in the middle of a screen opening reads as the hud having been there by
--> mistake. Sliding it out says the screen took the display over and will hand it back.

--> The frame everything in the hud is parented under, and the root of every path below.
local RootName = "Root"

type Edge = "Left" | "Right" | "Up" | "Down" | "DownLeft"

type Entry = {
	Path: string,
	Exit: Edge,
	Order: number,
	Group: string?,
	Drift: number?,
}

--> Which way each edge carries an element. The axis it travels along is the one it leaves by; the
--> axis left at zero is the one its drift runs across, so a corner has no drift and does not need
--> one -- it is already leaving on both.
local Directions: { [Edge]: Vector2 } = {
	Left = Vector2.new(-1, 0),
	Right = Vector2.new(1, 0),
	Up = Vector2.new(0, -1),
	Down = Vector2.new(0, 1),
	DownLeft = Vector2.new(-1, 1),
}

--> A lean across the direction of travel, as a fraction of the viewport. Small on purpose: enough
--> to tell two neighbours apart on the way out, not enough to read as the element going sideways.
local Nudge = 0.03

--> Every element that leaves, the edge it leaves through, and its place in that edge's sweep. The
--> names are the ones RenameHud wrote, so a hud renamed again is renamed by that same pass.
--> Bars holding labels as well as buttons leave whole: RewardBar's claim amount and robux price
--> are siblings of its buttons rather than children, so sweeping the buttons on their own would
--> leave the numbers sitting on the bare world.
--> A Group is what makes several elements read as one thing rather than as several: they share the
--> tilt, so the side bar goes off as a panel and only the stagger tells the buttons apart.
--> Drift is left out wherever the element should leave dead straight, which is most of them.
local Layout: { Entry } = {
	--> the cash sits in the corner rather than against an edge, so it leaves through the corner.
	--> Sent straight down it spends most of the trip crossing the bottom left of the display, which
	--> is exactly where a screen opening puts its own art
	{ Path = "CashBar", Exit = "DownLeft", Order = 1 },

	--> the menu bar fans as it drops -- the outer two lean away from the middle and Upgrades, which
	--> is the middle, goes straight down. Three buttons dropping on exactly parallel lines read as
	--> one bar being lowered rather than as three buttons leaving
	{ Path = "MenuBar.InventoryButton", Exit = "Down", Order = 2, Drift = -Nudge },
	{ Path = "MenuBar.UpgradesButton", Exit = "Down", Order = 3 },
	{ Path = "MenuBar.IndexButton", Exit = "Down", Order = 4, Drift = Nudge },

	{ Path = "SideBar.ShopButton", Exit = "Left", Order = 1, Group = "SideBar" },
	{ Path = "SideBar.RebirthButton", Exit = "Left", Order = 2, Group = "SideBar" },
	{ Path = "SideBar.InviteButton", Exit = "Left", Order = 3, Group = "SideBar" },

	{ Path = "RewardBar", Exit = "Right", Order = 1 },
	{ Path = "TopBar", Exit = "Up", Order = 1 },
}

--> Leaving and returning are deliberately different motions. On the way out the overshoot would
--> happen off the edge where nobody can see it, so there is nothing to spend it on and the element
--> is better off simply gone; on the way in the overshoot is the whole payoff.
local ExitSpeed = 26
local ExitDamping = 1
local EnterSpeed = 19
local EnterDamping = 0.7

--> Position and rotation run on springs of their own rather than one shared. Driven together the
--> hud reads as a single rigid slab sliding away; letting the tilt lag a fraction behind the
--> travel is what sells it as something with weight.
local RotationSpeedScale = 0.85

--> how far past the edge the element is aimed, so it is clear of it rather than flush against it
local ExitMargin = 24

local StaggerStep = 0.045

--> Rolled once per element -- or once per group -- and kept, not re-rolled per toggle. Re-rolling
--> makes the same button leave differently every time, which reads as the hud being unstable
--> rather than as character. The direction an element travels is authored; only how far it leans
--> over on the way is left to chance.
local MinTilt = 5
local MaxTilt = 16

local Rng = Random.new()

type Element = {
	Object: GuiObject,
	Exit: Edge,
	Order: number,
	Base: UDim2,
	BaseRotation: number,
	Tilt: number,
	Drift: number,

	Hidden: any,
	Position: any,
	Rotation: any,
}

export type Handle = {
	Show: () -> (),
	Hide: () -> (),
}

local HudSweep = {}

--> the longest sweep in any group, so the return can play the sweep backwards
local MaxOrder = 0

for _, Entry in Layout do
	MaxOrder = math.max(MaxOrder, Entry.Order)
end

--> "SideBar.ShopButton" walked one name at a time, so a hud rebuilt without one of those links
--> gives back nothing to warn about instead of erroring on the way past.
local function Resolve(Root: Instance, Path: string): Instance?
	local Current: Instance? = Root

	for _, Step in string.split(Path, ".") do
		if not Current then
			return nil
		end

		Current = (Current :: Instance):FindFirstChild(Step)
	end

	return Current
end

local function GetViewportSize(): Vector2
	local Camera = Workspace.CurrentCamera

	return if Camera then Camera.ViewportSize else Vector2.new(1920, 1080)
end

--> Where the element sits when it is home, worked out from its parent rather than read off its own
--> AbsolutePosition. AbsolutePosition is wherever the spring has got to, so a hud hidden again
--> before it finished coming back would measure its exit from halfway and stop short of the edge.
--> The parent is never animated and AbsoluteSize never is either, so this is the resting spot
--> whatever the springs are doing.
local function GetRest(Element: Element): (Vector2, Vector2)
	local Object = Element.Object
	local Parent = Object.Parent :: GuiBase2d
	local Size = Object.AbsoluteSize
	local Base = Element.Base

	local Position = Parent.AbsolutePosition
		+ Parent.AbsoluteSize * Vector2.new(Base.X.Scale, Base.Y.Scale)
		+ Vector2.new(Base.X.Offset, Base.Y.Offset)
		- Size * Object.AnchorPoint

	return Position, Size
end

--> How far one axis has to move to be clear of the display: back past its own far side to leave by
--> the near edge, or on past the display to leave by the far one. An axis the element is not
--> leaving by takes the drift instead.
local function GetTravel(Direction: number, Position: number, Size: number, Viewport: number, Drift: number): number
	if Direction < 0 then
		return -(Position + Size + ExitMargin)
	end

	if Direction > 0 then
		return Viewport - Position + ExitMargin
	end

	return Drift * Viewport
end

--> Aimed just past the element's own edge, measured against the viewport as it is right now, so it
--> clears at any resolution and a window resized mid session does not leave a button half on.
local function GetExit(Element: Element): UDim2
	local Viewport = GetViewportSize()
	local Position, Size = GetRest(Element)
	local Direction = Directions[Element.Exit]

	return Element.Base
		+ UDim2.fromOffset(
			GetTravel(Direction.X, Position.X, Size.X, Viewport.X, Element.Drift),
			GetTravel(Direction.Y, Position.Y, Size.Y, Viewport.Y, Element.Drift)
		)
end

--> The scope is the caller's, and the hud is hydrated rather than rebuilt: it is built in the
--> place, and only Position and Rotation are taken over here. Cleaning the scope therefore
--> destroys the real hud, which is only ever safe because the hud it was attached to has already
--> been thrown away by the time UIController attaches a new one.
function HudSweep.Attach(Scope: any, Hud: ScreenGui): Handle
	local Root = Hud:FindFirstChild(RootName)
	local Elements: { Element } = {}
	local Tilts: { [string]: number } = {}

	if not Root then
		warn(`[UI] {Hud.Name} has no {RootName} to sweep`)
	end

	--> Grouped elements are handed the same roll, which is what makes them lean as one. Anything
	--> ungrouped keys off its own path, so it is a group of one and gets a roll to itself.
	local function GetTilt(Key: string): number
		local Existing = Tilts[Key]

		if Existing then
			return Existing
		end

		local New = (if Rng:NextNumber() < 0.5 then -1 else 1) * Rng:NextNumber(MinTilt, MaxTilt)

		Tilts[Key] = New

		return New
	end

	for _, Entry in Layout do
		local Object = if Root then Resolve(Root, Entry.Path) else nil

		if not Object or not Object:IsA("GuiObject") then
			warn(`[UI] no hud element at {RootName}.{Entry.Path} to sweep`)
			continue
		end

		local Element: Element = {
			Object = Object,
			Exit = Entry.Exit,
			Order = Entry.Order,
			Base = Object.Position,
			BaseRotation = Object.Rotation,
			Tilt = GetTilt(Entry.Group or Entry.Path),
			Drift = Entry.Drift or 0,

			Hidden = Scope:Value(false),
			Position = Scope:Value(Object.Position),
			Rotation = Scope:Value(Object.Rotation),
		}

		--> the character of the motion is part of its direction, so speed and damping are read off
		--> the same state the goal is: a spring retargeted mid flight picks up the new feel with it
		local Speed = Scope:Computed(function(Use)
			return if Use(Element.Hidden) then ExitSpeed else EnterSpeed
		end)

		local Damping = Scope:Computed(function(Use)
			return if Use(Element.Hidden) then ExitDamping else EnterDamping
		end)

		local RotationSpeed = Scope:Computed(function(Use)
			return Use(Speed) * RotationSpeedScale
		end)

		Scope:Hydrate(Object)({
			Position = Scope:Spring(Element.Position, Speed, Damping),
			Rotation = Scope:Spring(Element.Rotation, RotationSpeed, Damping),
		})

		table.insert(Elements, Element)
	end

	local function Apply(Element: Element, Hidden: boolean)
		--> a hud thrown away mid sweep takes its springs with it, so a delay left over from the
		--> sweep it was in the middle of has nothing left to set
		if Element.Object.Parent == nil then
			return
		end

		Element.Hidden:set(Hidden)

		if not Hidden then
			Element.Position:set(Element.Base)
			Element.Rotation:set(Element.BaseRotation)

			return
		end

		Element.Position:set(GetExit(Element))
		Element.Rotation:set(Element.BaseRotation + Element.Tilt)
	end

	local State = false

	--> Leaving sweeps forward through the group and returning sweeps backward, so the return reads
	--> as the sweep rewinding rather than as a second run of the same one.
	local function Set(Hidden: boolean)
		if State == Hidden then
			return
		end

		State = Hidden

		for _, Element in Elements do
			local Step = if Hidden then Element.Order - 1 else MaxOrder - Element.Order

			if Step <= 0 then
				Apply(Element, Hidden)
				continue
			end

			task.delay(Step * StaggerStep, function()
				--> a screen opened and shut again inside one sweep must not let the delay left over
				--> from the first fight the second
				if State ~= Hidden then
					return
				end

				Apply(Element, Hidden)
			end)
		end
	end

	return {
		Show = function()
			Set(false)
		end,

		Hide = function()
			Set(true)
		end,
	}
end

return HudSweep
