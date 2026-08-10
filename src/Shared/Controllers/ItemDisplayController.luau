--> The card that pops over a component the moment a roll lands on it. Nothing else builds one:
--> it is a reward readout, not a label, so parts that were already sitting on a desk when the
--> plot loaded never get one.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local PartConfigs = require(Shared.Configs.Parts)
local Rarities = require(Shared.Configs.Rarities)
local Renders = require(Shared.Configs.Renders)
local Rolling = require(Shared.Utilities.Rolling)

local ContainerName = "ItemDisplays"

local SpinSpeed = 90 --> degrees a second, BackgroundGlow only
local PopIn = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PopOut = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)

--> Odds never move with luck here, so the whole table is worth one pass at require time
local BaseOdds = Rolling.Chances(PartConfigs.Variants, 1)

local ItemDisplayController = {}

local Template: BillboardGui? = nil

local function GetTemplate(): BillboardGui
	if not Template then
		Template = Assets:WaitForChild("UI"):WaitForChild("ItemDisplay") :: BillboardGui
	end

	return Template :: BillboardGui
end

--> One RenderStepped for every card on screen, rather than one per card. Entries drop out on
--> their own once destroyed, and the last one out takes the connection with it.
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

			--> A destroyed card has no parent left to draw into
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

--> A BillboardGui only adorns to a BasePart, and the components are Models with no PrimaryPart,
--> so the card rides an invisible stand-in on the crown of the model. It is kept a single stud
--> across on purpose: ExtentsOffset scales with the adornee, so anything else would hang a
--> keyboard's card in its own keys while a monitor's floated off into the sky.
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

--> Values land on halves at worst, from the 1.5 value Monitor, so one decimal covers every
--> product and a trailing .0 is just noise.
local function FormatValue(Value: number): string
	local Text = string.format("%.1f", Value)

	return (string.gsub(Text, "%.0$", ""))
end

--> Falls out the bottom onto the rarest tier, which is also where an unknown variant belongs:
--> a variant with no odds at all is not a common one. The odds come back alongside the tier
--> because the card prints both, and they have to be read off the same number or the "1 in N"
--> would sit under a tier name that disagrees with it.
local function GetRarity(Variant: string): (string, Color3, number)
	local Chance = BaseOdds[Variant]
	local Odds = if Chance and Chance > 0 then 1 / Chance else math.huge

	for _, Tier in Rarities.Tiers do
		if Odds <= Tier.Ceiling then
			return Tier.Name, Tier.Color, Odds
		end
	end

	local Last = Rarities.Tiers[#Rarities.Tiers]

	return Last.Name, Last.Color, Odds
end

--> Whole numbers only: the ladder runs from 1 in 2 to 1 in 769,231, and a decimal reads as
--> noise at the common end and is invisible at the rare end. Rounding down to 1 is the floor
--> because "1 in 0" is not a thing a player can be told.
local function FormatOdds(Odds: number): string
	--> An unknown variant has no odds to print, only a tier it was defaulted into
	if Odds ~= Odds or Odds == math.huge then
		return "1 / ???"
	end

	local Text = tostring(math.max(math.round(Odds), 1))

	--> Thousands separators right to left. The head stops matching once it is under four
	--> digits, so the loop runs out on its own rather than needing a length counted up front.
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

--> Filled in but not parented, so the caller decides what it adorns to. Glow left out keeps the
--> sparkle, which is what a freshly rolled part wants.
function ItemDisplayController:Build(Component: string, Variant: string, Glow: boolean?): BillboardGui
	local Display = GetTemplate():Clone()
	local Main = Display.Main

	local Render = Renders.Components[Variant] and Renders.Components[Variant][Component]

	if not Render then
		warn(`[ItemDisplay] No render for {Variant}.{Component}`)
	end

	local RarityName, RarityColor, Odds = GetRarity(Variant)

	--> A square glow spinning inside a square window loses its corners to the clip, and the
	--> corners are where the sparkle is
	Display.ClipsDescendants = false

	--> The anchor sits on the model's crown, so half a card's worth of lift is what keeps the
	--> card off the thing it is describing. The template's own offset floats it from there.
	Display.SizeOffset = Vector2.new(0, 0.5)

	Main.ComponentImage.Image = Render or ""
	Main.ComponentImage.ImageTransparency = 0
	Main.Title.Text = `{Variant} {Component}`
	Main.Rarity.Text = RarityName
	Main.Rarity.TextColor3 = RarityColor
	Main.Chance.Text = FormatOdds(Odds)
	Main.Chance.TextColor3 = RarityColor
	Main.CashPerSecond.Text = "$" .. FormatValue(self:Value(Component, Variant)) .. "x"

	--> Tinting the sparkle rather than swapping the art keeps one image behind every tier, and
	--> it is the read a player gets before any of the text resolves: a red halo is a Mythic
	--> from across the plot.
	Main.BackgroundGlow.ImageColor3 = RarityColor

	--> Hidden rather than removed, so the template stays the one place the card is described. A
	--> sparkle nobody can see is also not worth spinning.
	if Glow == false then
		Main.BackgroundGlow.ImageTransparency = 1
	else
		Spin(Main.BackgroundGlow)
	end

	--> Scaling the frame leaves every transparency the template set alone, so the pop cannot
	--> quietly undo the artwork the way tweening each element's transparency back would.
	local Scale = Instance.new("UIScale")
	Scale.Scale = 0
	Scale.Parent = Main

	TweenService:Create(Scale, PopIn, { Scale = 1 }):Play()

	return Display
end

export type Options = {
	--> Left out, the card stays up until the caller dismisses it. That is what a pad roll wants:
	--> the part keeps floating on its pad, so its readout keeps floating with it.
	Duration: number?,

	--> Draws the card over the world instead of behind it. Worth it where the roll happens in a
	--> corner with a wall in the way, not worth it out in the open where depth reads better.
	OnTop: boolean?,

	--> Studs to bring the card down. A card sized to sit over a part on the floor sits too high
	--> over one held at chest height or standing on a desk.
	Drop: number?,

	--> The sparkle behind the artwork. It sells a reward and gets in the way of a readout, so
	--> anything that is only telling the player what is already theirs turns it off.
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
	end

	return Anchor
end

--> Pops the card back down before clearing the anchor, so nothing ever just blinks out.
function ItemDisplayController:Dismiss(Anchor: BasePart)
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
