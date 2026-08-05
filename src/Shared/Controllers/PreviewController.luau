--> A viewport window for looking at one component model up close, without hunting for it in
--> a plot or building the whole showcase. Driven by the previewmodel command.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local PartConfigs = require(Shared.Configs.Parts)
local PlayerData = require(Shared.PlayerData).client
local Rolling = require(Shared.Utilities.Rolling)
local Parts = require(Assets:WaitForChild("Parts"))

local GuiName = "ModelPreview"

local FieldOfView = 40
local Framing = 1.35 --> how much room to leave around the model
local SpinSpeed = math.rad(50)
local Pitch = math.rad(18)

local Background = Color3.fromRGB(24, 26, 32)
local Panel = Color3.fromRGB(16, 17, 21)
local Outline = Color3.fromRGB(64, 70, 84)
local Faded = Color3.fromRGB(150, 156, 170)

local PreviewController = {
	Gui = nil :: ScreenGui?,
	Connection = nil :: RBXScriptConnection?,
}

local function Round(Parent: Instance, Radius: number)
	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, Radius)
	Corner.Parent = Parent
end

--> "1 in 667" reads better than a percentage this far out on the tail
local function OddsText(Variant: string): string
	local Entry = PartConfigs.Variants[Variant]

	if not Entry then
		return ""
	end

	--> Luck 0 leaves the rare end with no weight at all, which has no "1 in N" to print
	local function Odds(Chance: number): string
		return if Chance > 0 then `1 in {math.floor(1 / Chance + 0.5)}` else "never"
	end

	local Luck = PlayerData.Luck()
	local Text = `{Odds(Rolling.Chances(PartConfigs.Variants, 1)[Variant])}  ·  value {Entry.Value}`

	if Luck ~= 1 then
		Text ..= `  ·  {Odds(Rolling.Chances(PartConfigs.Variants, Luck)[Variant])} at luck {Luck}`
	end

	return Text
end

local function BuildGui(Title: string, Subtitle: string): (ScreenGui, ViewportFrame)
	local Gui = Instance.new("ScreenGui")
	Gui.Name = GuiName
	Gui.ResetOnSpawn = false
	Gui.IgnoreGuiInset = true
	Gui.DisplayOrder = 10

	local Window = Instance.new("Frame")
	Window.Name = "Window"
	Window.AnchorPoint = Vector2.new(0.5, 0.5)
	Window.Position = UDim2.fromScale(0.5, 0.5)
	Window.Size = UDim2.fromOffset(360, 420)
	Window.BackgroundColor3 = Background
	Window.BorderSizePixel = 0
	Window.Parent = Gui

	Round(Window, 12)

	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Outline
	Stroke.Thickness = 1
	Stroke.Parent = Window

	local Heading = Instance.new("TextLabel")
	Heading.Name = "Title"
	Heading.Position = UDim2.fromOffset(14, 12)
	Heading.Size = UDim2.new(1, -52, 0, 22)
	Heading.BackgroundTransparency = 1
	Heading.Text = Title
	Heading.TextColor3 = Color3.fromRGB(255, 255, 255)
	Heading.TextSize = 18
	Heading.TextXAlignment = Enum.TextXAlignment.Left
	Heading.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	Heading.Parent = Window

	local Odds = Instance.new("TextLabel")
	Odds.Name = "Odds"
	Odds.Position = UDim2.fromOffset(14, 36)
	Odds.Size = UDim2.new(1, -52, 0, 16)
	Odds.BackgroundTransparency = 1
	Odds.Text = Subtitle
	Odds.TextColor3 = Faded
	Odds.TextSize = 13
	Odds.TextXAlignment = Enum.TextXAlignment.Left
	Odds.FontFace = Font.fromEnum(Enum.Font.Gotham)
	Odds.Parent = Window

	local Close = Instance.new("TextButton")
	Close.Name = "Close"
	Close.Position = UDim2.new(1, -36, 0, 10)
	Close.Size = UDim2.fromOffset(26, 26)
	Close.BackgroundColor3 = Panel
	Close.BorderSizePixel = 0
	Close.Text = "X"
	Close.TextColor3 = Faded
	Close.TextSize = 14
	Close.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	Close.Parent = Window

	Round(Close, 6)

	Close.Activated:Connect(function()
		PreviewController:Close()
	end)

	local Viewport = Instance.new("ViewportFrame")
	Viewport.Name = "Viewport"
	Viewport.Position = UDim2.fromOffset(12, 62)
	Viewport.Size = UDim2.new(1, -24, 1, -74)
	Viewport.BackgroundColor3 = Panel
	Viewport.BorderSizePixel = 0
	Viewport.Ambient = Color3.fromRGB(180, 180, 190)
	Viewport.LightColor = Color3.fromRGB(255, 255, 255)
	Viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	Viewport.Parent = Window

	Round(Viewport, 8)

	return Gui, Viewport
end

function PreviewController:Close()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	--> Also sweeps a window left behind by a reload, which the field alone would not know about
	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local Existing = self.Gui or (PlayerGui and PlayerGui:FindFirstChild(GuiName))

	if Existing then
		Existing:Destroy()
	end

	self.Gui = nil
end

--> Returns false plus a reason instead of erroring, so the command can report it as output.
function PreviewController:Show(Component: string, Variant: string): (boolean, string?)
	local Loaded, Model = pcall(Parts, Component, Variant)

	if not Loaded or not Model then
		return false, tostring(Model)
	end

	self:Close()

	local Gui, Viewport = BuildGui(`{Variant} {Component}`, OddsText(Variant))

	--> A WorldModel keeps the parts laid out the way the asset has them instead of stacking
	--> everything on the viewport's origin.
	local World = Instance.new("WorldModel")
	World.Parent = Viewport

	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.Anchored = true
			Descendant.CanCollide = false
		end
	end

	Model.Parent = World

	local Camera = Instance.new("Camera")
	Camera.FieldOfView = FieldOfView
	Camera.Parent = Viewport
	Viewport.CurrentCamera = Camera

	local BoxCFrame, BoxSize = Model:GetBoundingBox()
	local Center = BoxCFrame.Position
	local Distance = (BoxSize.Magnitude / 2) / math.tan(math.rad(FieldOfView) / 2) * Framing

	local Yaw = 0
	local Dragging, LastX = false, 0

	Viewport.InputBegan:Connect(function(Input: InputObject)
		if
			Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		then
			Dragging, LastX = true, Input.Position.X
		end
	end)

	Viewport.InputChanged:Connect(function(Input: InputObject)
		if
			Dragging
			and (
				Input.UserInputType == Enum.UserInputType.MouseMovement
				or Input.UserInputType == Enum.UserInputType.Touch
			)
		then
			Yaw += math.rad(Input.Position.X - LastX)
			LastX = Input.Position.X
		end
	end)

	Viewport.InputEnded:Connect(function(Input: InputObject)
		if
			Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		then
			Dragging = false
		end
	end)

	self.Connection = RunService.RenderStepped:Connect(function(Delta: number)
		--> Spinning stops while a drag is in progress so the model does not fight the cursor
		if not Dragging then
			Yaw += SpinSpeed * Delta
		end

		Camera.CFrame = CFrame.new(Center) * CFrame.fromEulerAnglesYXZ(-Pitch, Yaw, 0) * CFrame.new(0, 0, Distance)
	end)

	Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = Gui

	return true
end

return PreviewController
