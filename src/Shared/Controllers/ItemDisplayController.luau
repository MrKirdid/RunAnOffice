local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local PartConfigs = require(Shared.Configs.Parts)
local Tiers = require(Shared.Utilities.Tiers)
local Renders = require(Shared.Configs.Renders)

local ContainerName = "ItemDisplays"

local SpinSpeed = 90
local PopIn = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PopOut = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local ItemDisplayController = {}

local Template: BillboardGui? = nil

local function GetTemplate(): BillboardGui
	if not Template then
		Template = Assets:WaitForChild("UI"):WaitForChild("ItemDisplay") :: BillboardGui
	end

	return Template :: BillboardGui
end

local Spinning: { ImageLabel } = {}
local SpinConnection: RBXScriptConnection? = nil

local function Spin(Glow: ImageLabel)
	table.insert(Spinning, Glow)

	if SpinConnection then
		return
	end

	SpinConnection = RunService.RenderStepped:Connect(function(Delta: number)
		for Index = #Spinning, 1, -1 do
			local Entry = Spinning[Index]

			if Entry.Parent then
				Entry.Rotation = (Entry.Rotation + SpinSpeed * Delta) % 360
			else
				table.remove(Spinning, Index)
			end
		end

		if #Spinning == 0 and SpinConnection then
			SpinConnection:Disconnect()
			SpinConnection = nil
		end
	end)
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

local function BuildAnchor(Model: Model): BasePart
	local BoxCFrame, BoxSize = Model:GetBoundingBox()

	local Anchor = Instance.new("Part")
	Anchor.Name = "DisplayAnchor"
	Anchor.Size = Vector3.one
	Anchor.CFrame = CFrame.new(BoxCFrame.Position + Vector3.new(0, BoxSize.Y / 2, 0))
	Anchor.Anchored = true
	Anchor.CanCollide = false
	Anchor.CanQuery = false
	Anchor.CanTouch = false
	Anchor.Massless = true
	Anchor.Transparency = 1
	Anchor.Parent = GetContainer()

	return Anchor
end

local function FormatValue(Value: number): string
	local Text = string.format("%.1f", Value)

	return (string.gsub(Text, "%.0$", ""))
end

local function FormatOdds(Odds: number): string
	if Odds ~= Odds or Odds == math.huge then
		return "1 / ???"
	end

	local Text = tostring(math.max(math.round(Odds), 1))

	local Count

	repeat
		Text, Count = string.gsub(Text, "^(%d+)(%d%d%d)", "%1,%2")
	until Count == 0

	return `1 / {Text}`
end

function ItemDisplayController:Value(Component: string, Variant: string): number
	local Base = PartConfigs.BaseValues[Component]
	local Tier = PartConfigs.Variants[Variant]

	return (if Base then Base.Value else 0) * (if Tier then Tier.Value else 0)
end

function ItemDisplayController:Build(Component: string, Variant: string, Glow: boolean?): BillboardGui
	local Display = GetTemplate():Clone()
	local Main = Display.Main

	local Render = Renders.Components[Variant] and Renders.Components[Variant][Component]

	if not Render then
		warn(`[ItemDisplay] No render for {Variant}.{Component}`)
	end

	local RarityName, RarityColor, Odds = Tiers.FromVariant(Variant)

	Display.ClipsDescendants = false

	Display.SizeOffset = Vector2.new(0, 0.5)

	Main.ComponentImage.Image = Render or ""
	Main.ComponentImage.ImageTransparency = 0
	Main.Title.Text = `{Variant} {Component}`
	Main.Rarity.Text = RarityName
	Main.Rarity.TextColor3 = RarityColor
	Main.Chance.Text = FormatOdds(Odds)
	Main.Chance.TextColor3 = RarityColor
	Main.CashPerSecond.Text = "$" .. FormatValue(self:Value(Component, Variant)) .. "x"

	Main.BackgroundGlow.ImageColor3 = RarityColor

	if Glow == false then
		Main.BackgroundGlow.ImageTransparency = 1
	else
		Spin(Main.BackgroundGlow)
	end

	local Scale = Instance.new("UIScale")
	Scale.Scale = 0
	Scale.Parent = Main

	TweenService:Create(Scale, PopIn, { Scale = 1 }):Play()

	return Display
end

export type Options = {
	Duration: number?,

	OnTop: boolean?,

	Drop: number?,

	Glow: boolean?,
}

function ItemDisplayController:Show(Model: Model, Component: string, Variant: string, Options: Options?): BasePart
	local Settings: Options = Options or {}
	local Anchor = BuildAnchor(Model)

	local Display = self:Build(Component, Variant, Settings.Glow)

	Display.AlwaysOnTop = Settings.OnTop == true

	if Settings.Drop then
		Display.StudsOffsetWorldSpace = Vector3.new(0, -Settings.Drop, 0)
	end

	Display.Parent = Anchor

	if Settings.Duration then
		task.delay(Settings.Duration, function()
			self:Dismiss(Anchor)
		end)
	else
		local Connection: RBXScriptConnection

		Connection = Model.AncestryChanged:Connect(function()
			if Model:IsDescendantOf(workspace) then
				return
			end

			Connection:Disconnect()
			self:Dismiss(Anchor)
		end)
	end

	return Anchor
end

function ItemDisplayController:Dismiss(Anchor: BasePart)
	if not Anchor.Parent then
		return
	end

	local Display = Anchor:FindFirstChildOfClass("BillboardGui")
	local Scale = Display and Display.Main:FindFirstChildOfClass("UIScale")

	if not Scale then
		Anchor:Destroy()
		return
	end

	TweenService:Create(Scale, PopOut, { Scale = 0 }):Play()
	Debris:AddItem(Anchor, PopOut.Time)
end

return ItemDisplayController
