local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local Format = require(Shared.Utilities.Format)

--> The counter on the HUD, cloned rather than rebuilt: the popup is the same number in the same
--> hand, so it wants the same font, the same gradient and the same stroke. Copying those values
--> into this file would mean every retune in Studio silently stops applying to the popups.
local HudName = "HudGUI"
local LabelPath = "Root.CashBar.CashLabel"

--> TextScaled will not take text past 100 pixels however big the box under it is, and a
--> UITextSizeConstraint does not lift it either -- measured, not assumed. So the text is set at
--> that 100 outright and a UIScale over the top does the growing, which the cap does not reach.
--> Every popup's UIScale is driven off its own rendered height each frame, so the digits fill the
--> card at any distance the way TextScaled was supposed to.
local BaseTextSize = 100

--> The rarity line on the card that hangs over every employee. The popup is sized off that line
--> rather than off the rig, so it sits in the same scale as the card it comes up past instead of
--> dwarfing it, and a touch under so it reads as a note off the card rather than a line of it.
--> The height is what is being set, and the width follows from the authored shape of the counter.
local RarityPath = "Frame.RarityLabel"
local RarityShare = 0.85

--> Where it starts, above the crown. The card is centred on this rather than stood on it, so it
--> comes up out of the head rather than appearing over it.
local StartGap = 0.2

--> How far it travels, top to bottom, a random rise in this band so a row of desks paid on the same
--> tick does not come up as one solid line.
local MinRise, MaxRise = 1.2, 2

--> How the rise is spent. The first stretch of the life throws it most of the way up, and the rest
--> is the gentle slide that carries it the last of the distance: a boom and then a drift, rather
--> than one long even climb.
local BoomOver = 0.18
local BoomShare = 0.62

--> How far off straight up it may lean. The heading around the compass is free, so two popups
--> leaving the same head go their own ways instead of stacking.
local MaxTilt = math.rad(30)

local MinLife, MaxLife = 0.85, 1.35

--> The last stretch of the life, over which it fades out. Held solid before that: a card that
--> starts fading the moment it appears is never fully readable.
local FadeFrom = 0.55

--> How far the card grows on the way in, and over how much of its life. Read as it landing rather
--> than as a bounce, so it settles at 1 and stays there.
local PopFrom = 0.55
local PopOver = 0.18

--> Only what is near enough and on the same floor. Flat distance, so standing on a balcony looking
--> down does not put the desks below out of range on the horizontal.
local Range = 30

--> Floors are a flat 12 studs apart in the plot template, so this band cannot reach the one above
--> or below however tall the player and the chair are.
local FloorBand = 8

local PayPopupController = {
	Template = nil :: TextLabel?,

	--> The cost of laying a popup out is all in the aspect below, which needs the viewport, so it
	--> is measured once and again whenever the window changes rather than per popup.
	Aspect = nil :: number?,

	--> The rarity line's height in studs, read off the employee card once at start. It is authored
	--> in studs and never moves, so there is nothing to measure again.
	LineHeight = nil :: number?,

	Active = {} :: { Popup },
	Stepper = nil :: RBXScriptConnection?,
}

type Popup = {
	Gui: BillboardGui,
	Label: TextLabel,
	Scale: UIScale,
	Size: UDim2,
	Start: Vector3,
	Direction: Vector3,
	Rise: number,
	Life: number,
	Age: number,
}

--> Its own stream: where a card drifts is decoration and has no business pulling on the sequence
--> that rolls parts and employees.
local Drift = Random.new()

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

--> Read out of StarterGui rather than off the live HUD: CashController rewrites the copy in
--> PlayerGui to size itself around the amount on it, so the live one is whatever the player's
--> balance happens to look like. The authored one is the shape the label was drawn as.
local function GetSource(): TextLabel?
	local Hud = StarterGui:FindFirstChild(HudName)
	local Label = Hud and Resolve(Hud, LabelPath)

	return if Label and Label:IsA("TextLabel") then Label else nil
end

--> The authored width over the authored height, in pixels. Every size down the HUD is pure scale,
--> so the chain multiplies out to a fraction of the screen and the viewport turns the two
--> fractions into a shape.
local function Measure(Source: TextLabel): number?
	local Camera = workspace.CurrentCamera
	local Viewport = if Camera then Camera.ViewportSize else nil

	if not Viewport or Viewport.X <= 0 or Viewport.Y <= 0 then
		return nil
	end

	local Width, Height = 1, 1
	local Current: Instance? = Source

	while Current and Current:IsA("GuiObject") do
		Width *= Current.Size.X.Scale
		Height *= Current.Size.Y.Scale

		Current = Current.Parent
	end

	if Width <= 0 or Height <= 0 then
		return nil
	end

	return (Width * Viewport.X) / (Height * Viewport.Y)
end

--> The rarity line on the employee card, in studs. Walked up from the label to the billboard the
--> same way the aspect is, so a retune of the card in Studio moves the popups with it instead of
--> leaving them sized to a line that no longer exists.
local function MeasureLine(): number?
	local Display = Assets:WaitForChild("UI"):WaitForChild("EmployeeDisplay")
	local Label = Resolve(Display, RarityPath)

	if not Display:IsA("BillboardGui") or not Label or not Label:IsA("GuiObject") then
		return nil
	end

	local Height = Display.Size.Y.Scale
	local Current: Instance? = Label

	while Current and Current:IsA("GuiObject") do
		Height *= Current.Size.Y.Scale

		Current = Current.Parent
	end

	return if Height > 0 then Height else nil
end

--> A copy stripped of everything that only made sense inside the bar: where it sat, what it was
--> anchored to, and the automatic sizing CashController hangs on it. What is kept is the look --
--> the face, the colour, and the gradient and stroke that came along as children.
function PayPopupController:Build(): TextLabel?
	local Source = GetSource()

	if not Source then
		warn(`[Pay] no cash label at {HudName}.{LabelPath}, popups are off`)
		return nil
	end

	local Label = Source:Clone()
	Label.Name = "PayPopup"
	Label.AnchorPoint = Vector2.new(0.5, 0.5)
	Label.Position = UDim2.fromScale(0.5, 0.5)
	Label.Size = UDim2.fromScale(1, 1)
	Label.AutomaticSize = Enum.AutomaticSize.None
	Label.TextXAlignment = Enum.TextXAlignment.Center
	Label.TextYAlignment = Enum.TextYAlignment.Center
	Label.BackgroundTransparency = 1

	--> Off, and set to the cap by hand instead. The label is authored with it on, and left on it
	--> holds the digits at 100 pixels in a card ten times that tall.
	Label.TextScaled = false
	Label.TextWrapped = false
	Label.TextSize = BaseTextSize

	--> What actually does the growing. Sized per frame in Step, and held at nothing until then: a
	--> popup is drawn the frame it is parented, before Step has measured it, and a fresh UIScale sits
	--> at 1, which is the digits at the full 100 pixels for that one frame -- a flash several times
	--> the card. At zero there is nothing to draw until the first measurement lands.
	local Scale = Instance.new("UIScale")
	Scale.Name = "Scale"
	Scale.Scale = 0
	Scale.Parent = Label

	return Label
end

function PayPopupController:GetAspect(): number?
	if self.Aspect then
		return self.Aspect
	end

	local Source = GetSource()

	self.Aspect = if Source then Measure(Source) else nil

	return self.Aspect
end

--> Where the player is standing, which is what decides what they can see. The camera is no good
--> for this: it sits behind and above the character and can be looking in from another floor.
local function GetViewer(): Vector3?
	local Character = Players.LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	return if Root and Root:IsA("BasePart") then Root.Position else nil
end

--> Near enough, and on this floor. Flat across and banded up and down, so the desks directly
--> overhead stay quiet while the ones through the wall on this floor do not.
function PayPopupController:InView(Position: Vector3): boolean
	local Viewer = GetViewer()

	if not Viewer then
		return false
	end

	if math.abs(Position.Y - Viewer.Y) > FloorBand then
		return false
	end

	return ((Position - Viewer) * Vector3.new(1, 0, 1)).Magnitude <= Range
end

--> Straight up, leaned over by up to MaxTilt in a heading picked off the whole compass.
local function PickDirection(): Vector3
	local Tilt = Drift:NextNumber(0, MaxTilt)
	local Heading = Drift:NextNumber(0, 2 * math.pi)
	local Lean = math.sin(Tilt)

	return Vector3.new(Lean * math.cos(Heading), math.cos(Tilt), Lean * math.sin(Heading))
end

--> Slows as it goes rather than running at a constant rate: cash leaving a desk reads as thrown
--> up and settling, and the number is easiest to read where it is moving slowest.
local function EaseOut(Alpha: number): number
	local Left = 1 - Alpha

	return 1 - Left * Left * Left
end

--> How much of the trip is behind it. Two parts: a hard ease out over the opening, which is the
--> boom, and then a flat rate for the rest, which is the slide. Flat rather than eased again --
--> a second ease would come to a stop halfway up and hang there, and the card is meant to still
--> be moving when it goes.
local function Travelled(Alpha: number): number
	if Alpha < BoomOver then
		return BoomShare * EaseOut(Alpha / BoomOver)
	end

	return BoomShare + (1 - BoomShare) * ((Alpha - BoomOver) / (1 - BoomOver))
end

function PayPopupController:Show(Head: BasePart, Amount: number)
	local Template = self.Template
	local Aspect = self:GetAspect()
	local Line = self.LineHeight

	if not Template or not Aspect or not Line or Amount <= 0 then
		return
	end

	if not self:InView(Head.Position) then
		return
	end

	--> The same card over every desk whatever the rig, since the rarity line it is matched to is
	--> the same over every desk too. The width comes off the authored shape of the counter, which is
	--> mostly empty space either side of a short amount and invisible with nothing behind it.
	local Height = Line * RarityShare
	local Size = UDim2.fromScale(Height * Aspect, Height)

	--> Measured to the crown and no further, so Rise is the distance above the top of the head the
	--> card actually ends up at.
	local Lift = Head.Size.Y * 0.5 + StartGap

	--> Born at the size the pop starts from, not the full one. The digits are scaled off the card's
	--> rendered height, which is a frame behind, so a card made full size and shrunk on its first
	--> Step would put full-size digits on a pop-in card for that one frame.
	local Gui = Instance.new("BillboardGui")
	Gui.Name = "PayPopup"
	Gui.Adornee = Head
	Gui.Size = UDim2.fromScale(Size.X.Scale * PopFrom, Size.Y.Scale * PopFrom)
	Gui.LightInfluence = 0
	Gui.MaxDistance = Range
	Gui.ResetOnSpawn = false

	--> Drawn over the world rather than into it: a number sliced by a partition or a monitor on
	--> its way up reads as broken where one drawn over it reads as part of the interface.
	Gui.AlwaysOnTop = true

	local Label = Template:Clone()
	Label.Text = `+{Format.Cash(Amount)}`
	Label.Parent = Gui

	local Scale = Label:FindFirstChildOfClass("UIScale")

	if not Scale then
		return
	end

	local Popup: Popup = {
		Gui = Gui,
		Label = Label,
		Scale = Scale,
		Size = Size,
		Start = Vector3.new(0, Lift, 0),
		Direction = PickDirection(),
		Rise = Drift:NextNumber(MinRise, MaxRise),
		Life = Drift:NextNumber(MinLife, MaxLife),
		Age = 0,
	}

	Gui.StudsOffsetWorldSpace = Popup.Start
	Gui.Parent = Head

	table.insert(self.Active, Popup)

	self:_StartStepper()
end

function PayPopupController:_Retire(Index: number)
	local Popup = self.Active[Index]

	Popup.Gui:Destroy()

	--> Order among the live popups means nothing, so the last one fills the gap instead of every
	--> one after it shuffling down.
	local Last = #self.Active

	self.Active[Index] = self.Active[Last]
	self.Active[Last] = nil
end

function PayPopupController:Step(Delta: number)
	for Index = #self.Active, 1, -1 do
		local Popup = self.Active[Index]

		Popup.Age += Delta

		local Alpha = Popup.Age / Popup.Life

		--> The adornee goes with the employee when a desk is rebuilt, and a card with nothing to
		--> hang off is not going anywhere.
		if Alpha >= 1 or not Popup.Gui.Adornee then
			self:_Retire(Index)
			continue
		end

		Popup.Gui.StudsOffsetWorldSpace = Popup.Start + Popup.Direction * (Popup.Rise * Travelled(Alpha))

		local Pop = if Alpha < PopOver then PopFrom + (1 - PopFrom) * EaseOut(Alpha / PopOver) else 1

		Popup.Gui.Size = UDim2.fromScale(Popup.Size.X.Scale * Pop, Popup.Size.Y.Scale * Pop)

		--> The digits made to fill the card, off what the card is actually being drawn at this
		--> frame, which moves with the distance and with the pop above. Nothing to do on the first
		--> frame, before it has been laid out and while its height still reads zero.
		local Drawn = Popup.Gui.AbsoluteSize.Y

		if Drawn > 0 then
			Popup.Scale.Scale = Drawn / BaseTextSize
		end

		--> Squared rather than straight, so it holds its colour a moment longer and then goes
		--> quickly, instead of spending the whole tail as a grey smudge.
		local Faded = if Alpha > FadeFrom then ((Alpha - FadeFrom) / (1 - FadeFrom)) ^ 2 else 0

		Popup.Label.TextTransparency = Faded
		Popup.Label.TextStrokeTransparency = math.max(Popup.Label.TextStrokeTransparency, Faded)

		local Stroke = Popup.Label:FindFirstChildOfClass("UIStroke")

		if Stroke then
			Stroke.Transparency = Faded
		end
	end

	if #self.Active == 0 then
		self:_StopStepper()
	end
end

--> Connected only while something is in the air. One connection for every popup would be a
--> connection per desk per second, and there is nothing to do on a tick with an empty list.
function PayPopupController:_StartStepper()
	if self.Stepper then
		return
	end

	self.Stepper = RunService.RenderStepped:Connect(function(Delta: number)
		self:Step(Delta)
	end)
end

function PayPopupController:_StopStepper()
	if self.Stepper then
		self.Stepper:Disconnect()
		self.Stepper = nil
	end
end

function PayPopupController:Init()
	self.Template = self:Build()
	self.LineHeight = MeasureLine()

	if not self.LineHeight then
		warn(`[Pay] no rarity line at Assets.UI.EmployeeDisplay.{RarityPath}, popups are off`)
	end

	--> The aspect is a fraction of the screen turned into a shape, so a window resized mid session
	--> is a different shape. Dropped rather than recalculated: the next popup measures it again.
	local Camera = workspace.CurrentCamera

	if Camera then
		Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self.Aspect = nil
		end)
	end
end

return PayPopupController
