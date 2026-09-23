local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--> The small motions that make a screen feel alive: a button that grows under the cursor and
--> squashes on a press, an icon that bobs, a gradient that drifts, a shine that sweeps a button.
--> Everything continuous runs off one Heartbeat and lets go of anything that has been
--> destroyed, so a screen rebuilt every respawn never leaks.

local ScaleName = "FxScale"
local ShineName = "FxShine"

--> hover and press, as a scale on the button
local HoverScale = 1.06
local PressScale = 0.92
local HoverTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PressTween = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ReleaseTween = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--> how far a bobbing icon travels, as a fraction of its parent, and how fast
local BobAmplitude = 0.02
local BobSpeed = 1.6

--> how far a drifting gradient slides either way, and how fast
local DriftAmplitude = 0.18
local DriftSpeed = 0.35

--> the shine: a narrow white band swept across the button every so often
local ShinePeriod = 3.2
local ShineSweep = 0.7
local ShineWidth = 0.12

local Spread = Random.new()

type Bob = { Object: GuiObject, Base: UDim2, Phase: number }
type Drift = { Gradient: UIGradient, Phase: number }
type Shine = { Gradient: UIGradient, Started: number }

local UIFx = {
	Bobbing = {} :: { Bob },
	Drifting = {} :: { Drift },
	Shining = {} :: { Shine },
	Stepping = false,
}

local function Gone(Object: Instance): boolean
	return Object.Parent == nil
end

local function ScaleOf(Object: GuiObject): UIScale
	local Existing = Object:FindFirstChild(ScaleName)

	if Existing and Existing:IsA("UIScale") then
		return Existing
	end

	local Scale = Instance.new("UIScale")
	Scale.Name = ScaleName
	Scale.Parent = Object

	return Scale
end

--> Grows under the cursor, squashes while held, springs back on release.
function UIFx.Press(Button: GuiObject)
	local Scale = ScaleOf(Button)
	local Over = false

	Button.MouseEnter:Connect(function()
		Over = true
		TweenService:Create(Scale, HoverTween, { Scale = HoverScale }):Play()
	end)

	Button.MouseLeave:Connect(function()
		Over = false
		TweenService:Create(Scale, HoverTween, { Scale = 1 }):Play()
	end)

	Button.InputBegan:Connect(function(Input: InputObject)
		if
			Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		then
			TweenService:Create(Scale, PressTween, { Scale = PressScale }):Play()
		end
	end)

	Button.InputEnded:Connect(function(Input: InputObject)
		if
			Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		then
			TweenService:Create(Scale, ReleaseTween, { Scale = if Over then HoverScale else 1 }):Play()
		end
	end)
end

--> Floats up and down around where it was drawn.
function UIFx.Bob(Object: GuiObject)
	table.insert(UIFx.Bobbing, { Object = Object, Base = Object.Position, Phase = Spread:NextNumber(0, math.pi * 2) })
	UIFx._Run()
end

--> Slides the gradient's offset back and forth, so the colour breathes.
function UIFx.Drift(Gradient: UIGradient)
	table.insert(UIFx.Drifting, { Gradient = Gradient, Phase = Spread:NextNumber(0, math.pi * 2) })
	UIFx._Run()
end

--> A white band swept across the button now and then. A gradient can only take colour away
--> from an image, so the band lives on a white copy of the button's own image laid over it,
--> transparent everywhere but the band, under the button's text.
function UIFx.Shine(Button: ImageButton)
	if Button:FindFirstChild(ShineName) then
		return
	end

	local Overlay = Instance.new("ImageLabel")
	Overlay.Name = ShineName
	Overlay.BackgroundTransparency = 1
	Overlay.Size = UDim2.fromScale(1, 1)
	Overlay.Image = Button.Image
	Overlay.ScaleType = Button.ScaleType
	Overlay.SliceCenter = Button.SliceCenter
	Overlay.SliceScale = Button.SliceScale
	Overlay.ImageColor3 = Color3.new(1, 1, 1)
	Overlay.ZIndex = 0
	Overlay.Parent = Button

	local Gradient = Instance.new("UIGradient")
	Gradient.Rotation = 20
	Gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - ShineWidth, 1),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(0.5 + ShineWidth, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	Gradient.Offset = Vector2.new(-1, 0)
	Gradient.Parent = Overlay

	table.insert(UIFx.Shining, { Gradient = Gradient, Started = os.clock() - Spread:NextNumber(0, ShinePeriod) })
	UIFx._Run()
end

function UIFx._Step()
	local Now = os.clock()

	for Index = #UIFx.Bobbing, 1, -1 do
		local Bob = UIFx.Bobbing[Index]

		if Gone(Bob.Object) then
			table.remove(UIFx.Bobbing, Index)
			continue
		end

		local Lift = math.sin(Now * BobSpeed + Bob.Phase) * BobAmplitude

		Bob.Object.Position = Bob.Base + UDim2.fromScale(0, Lift)
	end

	for Index = #UIFx.Drifting, 1, -1 do
		local Drift = UIFx.Drifting[Index]

		if Gone(Drift.Gradient) then
			table.remove(UIFx.Drifting, Index)
			continue
		end

		Drift.Gradient.Offset = Vector2.new(math.sin(Now * DriftSpeed + Drift.Phase) * DriftAmplitude, 0)
	end

	for Index = #UIFx.Shining, 1, -1 do
		local Shine = UIFx.Shining[Index]

		if Gone(Shine.Gradient) then
			table.remove(UIFx.Shining, Index)
			continue
		end

		local Into = (Now - Shine.Started) % ShinePeriod
		local Along = if Into < ShineSweep then Into / ShineSweep else 1

		Shine.Gradient.Offset = Vector2.new(-1 + Along * 2, 0)
	end
end

function UIFx._Run()
	if UIFx.Stepping then
		return
	end

	UIFx.Stepping = true

	RunService.Heartbeat:Connect(function()
		UIFx._Step()
	end)
end

return UIFx
