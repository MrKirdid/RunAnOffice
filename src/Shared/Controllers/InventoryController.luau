local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Items = require(Shared.Utilities.Items)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client
local Renders = require(Shared.Configs.Renders)
local SoundController = require(Shared.Controllers.SoundController)
local Tiers = require(Shared.Utilities.Tiers)
local UIController = require(Shared.Controllers.UIController)

--> What UIController files the screen under. It owns the blur, the pop and the X; this fills the
--> window with a grid of everything put away and works the tiles.
local ScreenName = "Inventory"

--> The card drawn in the place, tucked under the Suited folder, cloned once per tile. Read out
--> of StarterGui rather than the PlayerGui so a respawn cannot hand back a copy mid build.
local TemplatePath = { "Suited", "ItemUI", "MainBackground" }

--> Where the grid goes, from the InventoryGUI down: the window's background image.
local PanelPath = { "Frame", "ImageLabel" }

local ListName = "Items"
local RenderName = "Render"
local OddsName = "Odds"
local PressName = "Press"
local EmptyName = "Empty"

--> The grid, in fractions of the window. It starts under the title and stops short of the frame.
local ListPosition = UDim2.fromScale(0.06, 0.2)
local ListSize = UDim2.fromScale(0.88, 0.74)
local Columns = 4

--> The card's own width to height, off its UIAspectRatioConstraint in the place.
local CellAspect = 1.1742

--> Gaps as fractions of a cell's width. Rows get more than columns because the count label sits
--> above the card rather than on it, and it needs the room.
local ColumnGap = 0.06
local RowGap = 0.24

--> The render fills the middle of the card, behind the words: the odds line and the rarity line
--> are drawn over its edges rather than the picture being shrunk to fit between them.
local RenderSize = UDim2.fromScale(0.7, 0.44)
local RenderPosition = UDim2.fromScale(0.5, 0.49)

--> The odds line is cloned off the header and tucked under it, at the header's own left edge.
local OddsPosition = UDim2.fromScale(0.114375174, 0.235)
local OddsSize = UDim2.fromScale(0.765777469, 0.095)

--> Gold on an employee's multiplier, the same gold the card over their head uses.
local MultiplierColor = Color3.fromRGB(255, 215, 0)

local EmptyText = "Nothing put away"

--> Layers inside a tile, bottom up. The card is drawn flat in the place, so they are set here.
local GlowLayer = 1
local RenderLayer = 2
local TextLayer = 3
local PressLayer = 4

type Entry = Items.Entry

--> Identical things drawn as one tile with a count. Index is where the first of them sits in
--> the list, which is the one an equip takes.
type Stack = {
	Entry: Entry,
	Count: number,
	Index: number,
}

local InventoryController = {
	Template = nil :: Frame?,

	--> One equip in flight at a time, or two clicks send two and the second always fails.
	Equipping = false,
}

local function Resolve(Root: Instance, Path: { string }): Instance?
	local Current: Instance? = Root

	for _, Step in Path do
		if not Current then
			return nil
		end

		Current = (Current :: Instance):FindFirstChild(Step)
	end

	return Current
end

--> Two decimals at most, and none on a whole number: Luau prints 2.4 as "2.4" and 90 as "90".
local function FormatValue(Value: number): string
	return tostring(math.round(Value * 100) / 100)
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

local function RenderOf(Entry: Entry): string
	if Items.IsPart(Entry) then
		local Variants = Renders.Components[Entry.Variant :: string]

		return (Variants and Variants[Entry.Component :: string]) or ""
	end

	return Renders.Employees[Entry.Type :: string] or ""
end

--> Everything in the list folded into stacks, best first.
local function BuildStacks(): { Stack }
	local Raw = PlayerData.Inventory()
	local ByKey: { [string]: Stack } = {}
	local Stacks: { Stack } = {}

	if type(Raw) ~= "table" then
		return Stacks
	end

	for Index, Entry in Raw do
		if not Items.IsHeld(Entry) then
			continue
		end

		local Key = Items.Key(Entry)
		local Existing = ByKey[Key]

		if Existing then
			Existing.Count += 1
			continue
		end

		local Stack: Stack = { Entry = Entry, Count = 1, Index = tonumber(Index) :: number }

		ByKey[Key] = Stack
		table.insert(Stacks, Stack)
	end

	table.sort(Stacks, function(Left: Stack, Right: Stack): boolean
		return Items.Compare(Left.Entry, Right.Entry)
	end)

	return Stacks
end

--> Cells sized off the grid's own width, so the columns always fit whatever the window is.
local function SizeCells(List: ScrollingFrame, Layout: UIGridLayout)
	local Width = List.AbsoluteSize.X / (Columns + ColumnGap * (Columns - 1))
	local Height = Width / CellAspect

	Layout.CellSize = UDim2.fromOffset(Width, Height)
	Layout.CellPadding = UDim2.fromOffset(Width * ColumnGap, Width * RowGap)
end

function InventoryController:GetPanel(): GuiObject?
	local Gui = UIController:GetGui(ScreenName)
	local Panel = Gui and Resolve(Gui, PanelPath)

	return if Panel and Panel:IsA("GuiObject") then Panel else nil
end

--> The grid inside the window, built the first time the window is seen and again for every copy
--> a respawn hands back, since the copy has none of it.
function InventoryController:GetList(Panel: GuiObject): ScrollingFrame
	local Existing = Panel:FindFirstChild(ListName)

	if Existing and Existing:IsA("ScrollingFrame") then
		return Existing
	end

	local List = Instance.new("ScrollingFrame")
	List.Name = ListName
	List.BackgroundTransparency = 1
	List.BorderSizePixel = 0
	List.Position = ListPosition
	List.Size = ListSize
	List.CanvasSize = UDim2.new()
	List.AutomaticCanvasSize = Enum.AutomaticSize.Y
	List.ScrollingDirection = Enum.ScrollingDirection.Y
	List.ScrollBarThickness = 6
	List.ZIndex = PressLayer

	local Layout = Instance.new("UIGridLayout")
	Layout.SortOrder = Enum.SortOrder.LayoutOrder
	Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	Layout.Parent = List

	--> the count label hangs over the top of each card, so the first row needs the same room
	--> above it that every other row gets
	local Inset = Instance.new("UIPadding")
	Inset.PaddingTop = UDim.new(RowGap / (Columns + ColumnGap * (Columns - 1)), 0)
	Inset.Parent = List

	local Empty = Instance.new("TextLabel")
	Empty.Name = EmptyName
	Empty.BackgroundTransparency = 1
	Empty.Size = UDim2.fromScale(1, 0.15)
	Empty.Position = UDim2.fromScale(0, 0.4)
	Empty.Text = EmptyText
	Empty.TextColor3 = Color3.fromRGB(255, 255, 255)
	Empty.TextTransparency = 0.4
	Empty.TextScaled = true
	Empty.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	Empty.Visible = false
	Empty.ZIndex = PressLayer
	Empty.Parent = Panel

	List.Parent = Panel

	SizeCells(List, Layout)

	List:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		SizeCells(List, Layout)
	end)

	return List
end

function InventoryController:Equip(Index: number)
	if self.Equipping or Items.IsHeld(PlayerData.Holding()) then
		SoundController:Play("Error")
		return
	end

	self.Equipping = true

	NetworkingClient.Items.Equip
		.Invoke(Index)
		:andThen(function(Equipped: boolean)
			SoundController:Play(if Equipped then "Confirm" else "Error")

			--> The thing is in hand now, and the screen is in the way of placing it. The arms are
			--> drawn off the attribute the server wrote, so there is nothing to build here.
			if Equipped then
				UIController:Close(ScreenName)
			end
		end)
		:catch(function(Problem)
			warn(`[Inventory] {Problem}`)
			SoundController:Play("Error")
		end)
		:finally(function()
			self.Equipping = false
		end)
end

--> One tile, off the card from the place: the render behind the words, the odds line under the
--> header, and a button over the lot.
function InventoryController:_Tile(Order: number, Stack: Stack): Frame
	local Template = self.Template :: Frame
	local Entry = Stack.Entry

	local Tile = Template:Clone()
	Tile.Name = Items.Key(Entry)
	Tile.LayoutOrder = Order
	Tile.Visible = true

	--> the grid sizes the cell, so the card's own aspect lock would only shrink it inside one
	local Lock = Tile:FindFirstChildOfClass("UIAspectRatioConstraint")

	if Lock then
		Lock:Destroy()
	end

	local Odds = Items.Odds(Entry)
	local TierName, TierColor = Tiers.FromOdds(Odds)

	local Glow = Tile:FindFirstChild("BackgroundGlow") :: ImageLabel?
	local Header = Tile:FindFirstChild("Header") :: TextLabel?
	local Rarity = Tile:FindFirstChild("Rarity") :: TextLabel?
	local Cash = Tile:FindFirstChild("CashEarnt") :: TextLabel?
	local Amount = Tile:FindFirstChild("Amount") :: TextLabel?

	if Glow then
		Glow.ImageColor3 = TierColor
		Glow.ZIndex = GlowLayer
	end

	if Header then
		Header.Text = Items.Title(Entry)
		Header.ZIndex = TextLayer

		local OddsLine = Header:Clone()
		OddsLine.Name = OddsName
		OddsLine.Position = OddsPosition
		OddsLine.Size = OddsSize
		OddsLine.Text = FormatOdds(Odds)
		OddsLine.TextColor3 = TierColor
		OddsLine.Parent = Tile
	end

	if Rarity then
		Rarity.Text = if Items.IsEmployee(Entry) then `{TierName} {Entry.Type}` else TierName
		Rarity.TextColor3 = TierColor
		Rarity.ZIndex = TextLayer
	end

	if Cash then
		local Value = FormatValue(Items.Value(Entry))

		if Items.IsEmployee(Entry) then
			Cash.Text = Value .. "x"
			Cash.TextColor3 = MultiplierColor

			--> the green gradient is for money, and a multiplier is not money
			local Gradient = Cash:FindFirstChildOfClass("UIGradient")

			if Gradient then
				Gradient:Destroy()
			end
		else
			Cash.Text = "$" .. Value .. "x"
		end

		Cash.ZIndex = TextLayer
	end

	if Amount then
		Amount.Text = `{Stack.Count}x`
		Amount.ZIndex = TextLayer
	end

	local Render = Instance.new("ImageLabel")
	Render.Name = RenderName
	Render.BackgroundTransparency = 1
	Render.AnchorPoint = Vector2.new(0.5, 0.5)
	Render.Size = RenderSize
	Render.Position = RenderPosition
	Render.Image = RenderOf(Entry)
	Render.ScaleType = Enum.ScaleType.Fit
	Render.ZIndex = RenderLayer
	Render.Parent = Tile

	local Press = Instance.new("TextButton")
	Press.Name = PressName
	Press.BackgroundTransparency = 1
	Press.Size = UDim2.fromScale(1, 1)
	Press.Text = ""
	Press.ZIndex = PressLayer
	Press.Active = true
	Press.Parent = Tile

	Press.MouseEnter:Connect(function()
		SoundController:Play("Hover")
	end)

	Press.Activated:Connect(function()
		self:Equip(Stack.Index)
	end)

	return Tile
end

--> Rebuilt whole on every change: an inventory holds a few dozen tiles at most, and a rebuild
--> cannot leave a stale one pointing at an index that has moved.
function InventoryController:Refresh()
	local Panel = self:GetPanel()

	if not Panel or not self.Template then
		return
	end

	local List = self:GetList(Panel)

	for _, Tile in List:GetChildren() do
		if Tile:IsA("GuiObject") then
			Tile:Destroy()
		end
	end

	local Stacks = BuildStacks()

	for Order, Stack in Stacks do
		self:_Tile(Order, Stack).Parent = List
	end

	local Empty = Panel:FindFirstChild(EmptyName)

	if Empty then
		(Empty :: TextLabel).Visible = #Stacks == 0
	end
end

function InventoryController:Start()
	local Template = Resolve(StarterGui, TemplatePath)

	if not Template or not Template:IsA("Frame") then
		warn(`[Inventory] StarterGui has no {table.concat(TemplatePath, ".")} to clone`)
		return
	end

	self.Template = Template:Clone()

	Players.LocalPlayer:WaitForChild("PlayerGui")

	--> Redrawn only while it can be seen: the list changes on every pickup and placement, and
	--> nobody is looking at it then.
	local function RefreshOpen()
		if UIController:IsOpen(ScreenName) then
			self:Refresh()
		end
	end

	PlayerData.Inventory.Changed(RefreshOpen)
	PlayerData.Holding.Changed(RefreshOpen)

	UIController.Opened:Connect(function(Name: string)
		if Name == ScreenName then
			self:Refresh()
		end
	end)
end

return InventoryController
