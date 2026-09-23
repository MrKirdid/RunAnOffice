local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local PlayerData = require(Shared.PlayerData).client

--> The counter on the hud, and the button sitting next to it. The label was authored TextScaled
--> inside a fixed box, which sizes the digits to the box rather than the box to the digits: "$200"
--> came out as tall as the bar and "$6.6M" came out small, and the button stayed where it was
--> drawn whatever the number did. Here the digits keep one size and the label fits itself around
--> them, so the counter is as wide as the amount is long and the button follows it.

--> From Root, the frame the counter lives in.
local BarPath = "Root.CashBar"
local LabelName = "CashLabel"
local ButtonName = "AddCashButton"

--> The gap between the number and the button, as a fraction of the text height rather than a pixel
--> count, so it is the same gap to the eye on a phone as on a monitor.
local Gap = 0.35

--> How fast the shown number chases the real one, per second of a proportion of what is left. The
--> counter is read while cash is ticking in, so it rolls up to the new amount rather than cutting
--> to it -- but only just: a roll long enough to notice is a number that is wrong for that long.
local RollSpeed = 14

--> Below this the roll has nothing left to show, so it lands.
local RollEpsilon = 0.5

local Draw = Random.new()

--> The "+$x" that floats off the counter when cash comes in. Every tick of income is one, so it
--> is small and quick: up a little, gone in under a second, and only the gain is written on it.
--> Distances are in label heights, so the throw scales with the counter.
local PopupName = "CashPopup"
local PopupTime = 1.1

--> Where one lands: this far above the counter, and anywhere this far to either side of it, so a
--> stream of them scatters instead of stacking on one spot.
local PopupLift = 1.1
local PopupSpread = 1.6

--> Where it floats off to: somewhere between the two rises, and this far to either side.
local PopupRise = NumberRange.new(1.2, 2.2)
local PopupDrift = 1.4
local PopupColor = Color3.fromRGB(120, 255, 140)

--> The pop: it lands small and tilted, swells past its size, settles, and only then floats off.
--> The digits are typed in over the swell, so the amount arrives rather than appears.
local PopupStartScale = 0.4
local PopupPunchScale = 1.25

--> How far over it lands, how far over it settles, and how much further it turns on the way out.
local PopupTilt = 30
local PopupRestTilt = 10
local PopupSpinOut = 25
local PopupTypeTime = 0.14
local PopupPunchTween = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PopupSettleTween = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PopupRiseTween = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PopupHold = 0.3

local CashController = {
	Bar = nil :: GuiObject?,
	Label = nil :: TextLabel?,
	Button = nil :: GuiObject?,

	--> Where the cluster is centred, taken off the label's authored position so the counter keeps
	--> sitting where it was drawn instead of a number repeated here going stale when it is moved.
	Center = 0.5,

	--> the amount on the label right now, which trails the real one while it rolls
	Shown = 0,
	Target = 0,
	Roll = nil :: RBXScriptConnection?,

	--> the last amount the counter was told, so a change is known to be a gain or a spend
	Known = nil :: number?,

	--> rebuilt with the hud, which is cloned again every respawn
	Connections = {} :: { RBXScriptConnection },
}

--> "Root.CashBar" walked one name at a time, so a hud rebuilt without one of those links gives
--> back nothing to warn about instead of erroring on the way past.
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

--> Only the across is ours. The label and the button are each authored at their own height in the
--> bar, and nothing about the amount should move them up or down.
local function SetX(Object: GuiObject, X: number)
	local Position = Object.Position

	Object.Position = UDim2.new(0, X, Position.Y.Scale, Position.Y.Offset)
end

--> Laid out from the middle out: the number and the button are placed as one thing, so a longer
--> amount grows the pair rather than pushing the button off on its own.
function CashController:_Layout()
	local Bar, Label, Button = self.Bar, self.Label, self.Button

	if not Bar or not Label or not Button then
		return
	end

	local Height = Label.AbsoluteSize.Y

	--> a hud that has not been drawn yet has no size to measure, and the AbsoluteSize it gets on
	--> its first frame brings us back here
	if Height <= 0 or Bar.AbsoluteSize.X <= 0 then
		return
	end

	--> One size for the digits whatever the amount is, tied to the height the label was authored
	--> at, so the counter still scales with the display without scaling with its own text.
	Label.TextSize = math.max(1, math.round(Height))

	local Width = Label.AbsoluteSize.X
	local Between = Height * Gap
	local Total = Width + Between + Button.AbsoluteSize.X
	local Left = Bar.AbsoluteSize.X * self.Center - Total / 2

	SetX(Label, Left)
	SetX(Button, Left + Width + Between)
end

function CashController:_Draw()
	local Label = self.Label

	if Label then
		Label.Text = Format.Cash(math.floor(self.Shown))
	end
end

function CashController:_StopRoll()
	if self.Roll then
		self.Roll:Disconnect()
		self.Roll = nil
	end
end

function CashController:_StartRoll()
	if self.Roll then
		return
	end

	self.Roll = RunService.RenderStepped:Connect(function(Delta: number)
		local Left = self.Target - self.Shown

		--> Eased rather than stepped by a fixed amount per second: a flat rate takes a hundred
		--> times as long to cover a hundred times the cash, and the roll is meant to read the same
		--> whether the number moved by a tip or by a rebirth.
		if math.abs(Left) <= RollEpsilon then
			self.Shown = self.Target

			self:_Draw()
			self:_StopRoll()

			return
		end

		self.Shown += Left * math.min(1, Delta * RollSpeed)

		self:_Draw()
	end)
end

--> Snap is for the first amount we ever see and for a hud handed back fresh: there is nothing on
--> the label to roll up from, so rolling would count the player's balance up from zero every
--> respawn.
function CashController:Set(Amount: number, Snap: boolean?)
	self.Target = Amount

	local Known = self.Known

	self.Known = Amount

	if not Snap and Known and Amount > Known then
		self:_Popup(Amount - Known)
	end

	if Snap then
		self:_StopRoll()

		self.Shown = Amount

		self:_Draw()

		return
	end

	self:_StartRoll()
end

--> A gain floating off the counter, sized off the counter's own text so it reads as part of it.
function CashController:_Popup(Gain: number)
	local Label = self.Label

	if not Label or not Label.Parent or Gain <= 0 then
		return
	end

	local Popup = Instance.new("TextLabel")
	Popup.Name = PopupName
	Popup.AnchorPoint = Vector2.new(0, 1)
	Popup.BackgroundTransparency = 1
	Popup.AutomaticSize = Enum.AutomaticSize.X
	Popup.Size = UDim2.new(0, 0, Label.Size.Y.Scale * 0.6, Label.Size.Y.Offset * 0.6)
	--> the counter's own height is the unit, and the sideways draw is signed so it lands either way
	local Unit = Label.AbsoluteSize.Y
	local Side = Draw:NextNumber(-PopupSpread, PopupSpread) * Unit
	local Drift = Draw:NextNumber(-PopupDrift, PopupDrift) * Unit
	local Rise = Draw:NextNumber(PopupRise.Min, PopupRise.Max) * Unit

	Popup.Position =
		UDim2.new(0, Label.Position.X.Offset + Side, Label.Position.Y.Scale, Label.Position.Y.Offset - PopupLift * Unit)
	Popup.FontFace = Label.FontFace
	Popup.TextSize = math.max(1, math.round(Label.TextSize * 0.6))
	Popup.TextColor3 = PopupColor
	Popup.TextXAlignment = Enum.TextXAlignment.Left
	Popup.Text = ""
	Popup.Rotation = Draw:NextNumber(-PopupTilt, PopupTilt)
	Popup.ZIndex = Label.ZIndex + 1

	local Scale = Instance.new("UIScale")
	Scale.Scale = PopupStartScale
	Scale.Parent = Popup

	local Stroke = Label:FindFirstChildOfClass("UIStroke")

	if Stroke then
		Stroke:Clone().Parent = Popup
	end

	Popup.Parent = Label.Parent

	local Away = UDim2.new(
		Popup.Position.X.Scale,
		Popup.Position.X.Offset + Drift,
		Popup.Position.Y.Scale,
		Popup.Position.Y.Offset - Rise
	)

	--> it settles a little off straight and keeps turning the way it was going as it leaves
	local Rest = Draw:NextNumber(-PopupRestTilt, PopupRestTilt)
	local Spin = Rest + (if Drift < 0 then -PopupSpinOut else PopupSpinOut)

	local Text = "+" .. Format.Cash(math.floor(Gain))
	local PopupStroke = Popup:FindFirstChildOfClass("UIStroke")

	local Punch = TweenService:Create(Scale, PopupPunchTween, { Scale = PopupPunchScale })

	Punch.Completed:Once(function()
		TweenService:Create(Scale, PopupSettleTween, { Scale = 1 }):Play()
	end)

	Punch:Play()
	TweenService:Create(Popup, PopupPunchTween, { Rotation = Rest }):Play()

	task.spawn(function()
		for Length = 1, #Text do
			if not Popup.Parent then
				return
			end

			Popup.Text = string.sub(Text, 1, Length)

			task.wait(PopupTypeTime / #Text)
		end
	end)

	task.delay(PopupHold, function()
		if not Popup.Parent then
			return
		end

		TweenService:Create(Popup, PopupRiseTween, { Position = Away, Rotation = Spin, TextTransparency = 1 }):Play()

		if PopupStroke then
			TweenService:Create(PopupStroke, PopupRiseTween, { Transparency = 1 }):Play()
		end
	end)

	Debris:AddItem(Popup, PopupTime)
end

function CashController:_Bind(Signal: RBXScriptSignal, Handler: () -> ())
	table.insert(self.Connections, Signal:Connect(Handler))
end

--> The hud is built in the place and cloned again every respawn, so this is handed a copy that has
--> never been touched: the authored centre is read off it before anything here moves it.
function CashController:Attach(Hud: ScreenGui)
	for _, Connection in self.Connections do
		Connection:Disconnect()
	end

	table.clear(self.Connections)

	self:_StopRoll()

	local Bar = Resolve(Hud, BarPath)
	local Label = Bar and Bar:FindFirstChild(LabelName)
	local Button = Bar and Bar:FindFirstChild(ButtonName)

	if not Bar or not Bar:IsA("GuiObject") or not Label or not Label:IsA("TextLabel") then
		warn(`[UI] {Hud.Name} has no cash counter at {BarPath}.{LabelName}`)

		self.Bar, self.Label, self.Button = nil, nil, nil

		return
	end

	if not Button or not Button:IsA("GuiObject") then
		warn(`[UI] no {ButtonName} beside the cash counter`)

		self.Bar, self.Label, self.Button = nil, nil, nil

		return
	end

	--> where the middle of the counter was drawn, before its anchor is moved off centre below
	self.Center = Label.Position.X.Scale
	self.Bar, self.Label, self.Button = Bar, Label, Button

	--> The box follows the text rather than the text filling the box. Wrapping is off with it: a
	--> label free to grow across never needs a second line, and one would push the digits out of
	--> the bar.
	Label.TextScaled = false
	Label.TextWrapped = false
	Label.AutomaticSize = Enum.AutomaticSize.X
	Label.AnchorPoint = Vector2.new(0, Label.AnchorPoint.Y)
	Label.Size = UDim2.new(0, 0, Label.Size.Y.Scale, Label.Size.Y.Offset)

	Button.AnchorPoint = Vector2.new(0, Button.AnchorPoint.Y)

	--> AutomaticSize settles a frame after the text changes, so the width is taken from the label
	--> telling us it has resized rather than guessed at the moment it is written.
	self:_Bind(Label:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:_Layout()
	end)

	--> a window resized mid session, and the first frame the hud is drawn on
	self:_Bind(Bar:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:_Layout()
	end)

	local Cash = PlayerData.Cash()

	self:Set(if type(Cash) == "number" then Cash else self.Target, true)
	self:_Layout()
end

function CashController:Init()
	local Cash = PlayerData.Cash()

	--> whatever is already saved on the way in is the amount to start on, not an amount to roll to
	self:Set(if type(Cash) == "number" then Cash else 0, true)

	PlayerData.Cash.Changed(function()
		local New = PlayerData.Cash()

		if type(New) ~= "number" then
			return
		end

		self:Set(New)
	end)
end

return CashController
