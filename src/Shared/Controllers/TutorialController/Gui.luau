--> The tutorial's screen, built here rather than in the place: an arrow for the hud, and the bar at
--> the top that types out what to do. Nothing on it is authored art, so it lives in git with the
--> code that drives it.

local GuiName = "TutorialGUI"

--> Above every screen the hud opens, so the arrow sits over the menu the player is being pointed
--> into as well as the hud itself. Under the console, which is at 100.
local DisplayOrder = 90

local ArrowImage = "rbxassetid://100291291310565"
local ArrowSize = UDim2.fromScale(0.0493685, 0.0739109)

local InformationPosition = UDim2.fromScale(0.5, 0.09)
local InformationSize = UDim2.fromScale(0.56, 0.095)

--> Strokes are given as a fraction of the text they outline, not in pixels. A thickness is read off the box's own
--> height and kept there as it changes, clamped to something visible either way.
local MinStroke = 1.5
local MaxStroke = 14

local Gui = {}

--> A stroke that follows its object's height. Bound once and left; the object outlives the stroke
--> in every case here.
function Gui.ScaleStroke(Stroke: UIStroke, Object: GuiObject, Fraction: number)
	local function Apply()
		Stroke.Thickness = math.clamp(Object.AbsoluteSize.Y * Fraction, MinStroke, MaxStroke)
	end

	Apply()

	Object:GetPropertyChangedSignal("AbsoluteSize"):Connect(Apply)
end

local function BuildArrow(Parent: ScreenGui): ImageLabel
	local Arrow = Instance.new("ImageLabel")
	Arrow.Name = "Arrow"
	Arrow.Image = ArrowImage
	Arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	Arrow.BackgroundTransparency = 1
	Arrow.BorderSizePixel = 0
	Arrow.Position = UDim2.fromScale(0.5, 0.5)
	Arrow.Size = ArrowSize
	Arrow.Visible = false
	Arrow.ZIndex = 1000

	local Aspect = Instance.new("UIAspectRatioConstraint")
	Aspect.AspectRatio = 1
	Aspect.Parent = Arrow

	local Scale = Instance.new("UIScale")
	Scale.Parent = Arrow

	Arrow.Parent = Parent

	return Arrow
end

local function BuildInformation(Parent: ScreenGui): CanvasGroup
	local Information = Instance.new("CanvasGroup")
	Information.Name = "Information"
	Information.AnchorPoint = Vector2.new(0.5, 0.5)
	Information.BackgroundTransparency = 1
	Information.BorderSizePixel = 0
	Information.Position = InformationPosition
	Information.Size = InformationSize
	Information.Visible = false
	Information.ZIndex = 1000

	local Top = Instance.new("Frame")
	Top.Name = "Top"
	Top.AnchorPoint = Vector2.new(0.5, 0.5)
	Top.BackgroundColor3 = Color3.new(0, 0, 0)
	Top.BackgroundTransparency = 0.5
	Top.BorderSizePixel = 0
	Top.Position = UDim2.fromScale(0.5, 0.5)
	Top.Size = UDim2.fromScale(1, 1)
	Top.Parent = Information

	--> solid in the middle and gone at both ends, so the bar has no edges to sit badly against
	--> whatever is behind it
	local Gradient = Instance.new("UIGradient")
	Gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	Gradient.Parent = Top

	local Title = Instance.new("TextLabel")
	Title.Name = "Title"
	Title.AnchorPoint = Vector2.new(0.5, 0.5)
	Title.BackgroundTransparency = 1
	Title.BorderSizePixel = 0
	Title.Position = UDim2.fromScale(0.5, 0.32)
	Title.Size = UDim2.fromScale(1, 0.46)
	Title.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	Title.Text = ""
	Title.TextColor3 = Color3.new(1, 1, 1)
	Title.TextScaled = true
	Title.TextWrapped = true
	Title.Parent = Top

	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Color3.new(0, 0, 0)
	Stroke.LineJoinMode = Enum.LineJoinMode.Bevel
	Stroke.Parent = Title

	Gui.ScaleStroke(Stroke, Title, 0.095)

	--> the line under the instruction that says why, smaller and a shade softer
	local Detail = Instance.new("TextLabel")
	Detail.Name = "Detail"
	Detail.AnchorPoint = Vector2.new(0.5, 0.5)
	Detail.BackgroundTransparency = 1
	Detail.BorderSizePixel = 0
	Detail.Position = UDim2.fromScale(0.5, 0.74)
	Detail.Size = UDim2.fromScale(0.96, 0.32)
	Detail.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
	Detail.Text = ""
	Detail.TextColor3 = Color3.fromRGB(235, 235, 235)
	Detail.TextScaled = true
	Detail.TextWrapped = true
	Detail.Parent = Top

	local DetailStroke = Instance.new("UIStroke")
	DetailStroke.Color = Color3.new(0, 0, 0)
	DetailStroke.LineJoinMode = Enum.LineJoinMode.Bevel
	DetailStroke.Parent = Detail

	Gui.ScaleStroke(DetailStroke, Detail, 0.095)

	Information.Parent = Parent

	return Information
end

function Gui.Build(Parent: Instance): ScreenGui
	local Existing = Parent:FindFirstChild(GuiName)

	if Existing then
		Existing:Destroy()
	end

	local Screen = Instance.new("ScreenGui")
	Screen.Name = GuiName
	--> the whole viewport, so a point off the camera lands where the camera put it
	Screen.IgnoreGuiInset = true
	Screen.ResetOnSpawn = false
	Screen.DisplayOrder = DisplayOrder
	Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	BuildArrow(Screen)
	BuildInformation(Screen)

	Screen.Parent = Parent

	return Screen
end

return Gui
