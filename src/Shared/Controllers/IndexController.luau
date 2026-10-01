local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Discoveries = require(Shared.Utilities.Discoveries)
local InventoryController = require(Shared.Controllers.InventoryController)
local PartConfigs = require(Shared.Configs.Parts)
local PlayerData = require(Shared.PlayerData).client
local SoundController = require(Shared.Controllers.SoundController)
local UIController = require(Shared.Controllers.UIController)

--> The Index in the place is a panel, a title, an X and three category buttons down the side, and
--> nothing to put a part in. The grid is built here, inside the panel, one card per variant of the
--> picked component, commonest first, drawn as the inventory draws its cards: found ones whole,
--> the rest as a dark shape that still says how rare it is, so the Index is also the list of what
--> to chase.
local GuiName = "IndexGUI"
local ScreenName = "Index"
local PanelPath = { "Frame", "ImageLabel" }
local CategoriesPath = { "Frame", "Categories" }
local ListName = "IndexList"
local CountName = "IndexCount"

local Buttons = {
	Keyboard = "KeyboardButton",
	Monitor = "MonitorButton",
	Computer = "ComputerButton",
}

local TextFont = Font.new("rbxassetid://11598289817", Enum.FontWeight.Bold)
local Unpicked = Color3.fromRGB(150, 150, 150)

--> the grid sits under the title and the X, and keeps clear of the panel's rounded edge
local ListPosition = UDim2.fromScale(0.5, 0.57)
local ListSize = UDim2.fromScale(0.9, 0.74)
local Columns = 3
local CellGap = 0.02

local IndexController = {
	Gui = nil :: ScreenGui?,
	Component = "Keyboard" :: string,
	Bound = nil :: ScreenGui?,
}

local function Walk(From: Instance, Path: { string }): Instance?
	local At: Instance? = From

	for _, Name in Path do
		At = At and At:FindFirstChild(Name)
	end

	return At
end

--> Commonest first, so the page reads as a ladder from what everybody has to what nobody does.
local function Ordered(): { string }
	local Names = {}

	for Name in PartConfigs.Variants do
		table.insert(Names, Name)
	end

	table.sort(Names, function(A: string, B: string): boolean
		return PartConfigs.Variants[A].Rarity > PartConfigs.Variants[B].Rarity
	end)

	return Names
end

local Variants = Ordered()

--> The found count beside the title.
local function Label(Parent: Instance, Name: string, Position: UDim2, Size: UDim2): TextLabel
	local Created = Instance.new("TextLabel")
	Created.Name = Name
	Created.BackgroundTransparency = 1
	Created.AnchorPoint = Vector2.new(0.5, 0.5)
	Created.Position = Position
	Created.Size = Size
	Created.FontFace = TextFont
	Created.TextScaled = true
	Created.TextColor3 = Color3.new(1, 1, 1)

	local Stroke = Instance.new("UIStroke")
	Stroke.Thickness = 1.5
	Stroke.Parent = Created

	Created.Parent = Parent

	return Created
end

function IndexController:GetGui(): ScreenGui?
	if self.Gui and self.Gui.Parent then
		return self.Gui
	end

	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	self.Gui = PlayerGui and PlayerGui:FindFirstChild(GuiName) :: ScreenGui?

	return self.Gui
end

--> The scrolling grid and the found count, made once per copy of the screen: a ResetOnSpawn
--> screen is a new copy after every respawn, and the old one took its grid with it.
function IndexController:_Build(Gui: ScreenGui): (ScrollingFrame?, TextLabel?)
	local Panel = Walk(Gui, PanelPath)

	if not Panel then
		warn(`[Index] {GuiName} has no {table.concat(PanelPath, ".")} to put the parts in`)
		return nil, nil
	end

	local List = Panel:FindFirstChild(ListName) :: ScrollingFrame?
	local Count = Panel:FindFirstChild(CountName) :: TextLabel?

	if List and Count then
		return List, Count
	end

	List = Instance.new("ScrollingFrame")
	List.Name = ListName
	List.AnchorPoint = Vector2.new(0.5, 0.5)
	List.Position = ListPosition
	List.Size = ListSize
	List.BackgroundTransparency = 1
	List.BorderSizePixel = 0
	List.ScrollBarThickness = 6
	List.AutomaticCanvasSize = Enum.AutomaticSize.Y
	List.CanvasSize = UDim2.new()
	List.ScrollingDirection = Enum.ScrollingDirection.Y

	local Padding = Instance.new("UIPadding")
	Padding.PaddingTop = UDim.new(0, 6)
	Padding.PaddingBottom = UDim.new(0, 6)
	Padding.PaddingLeft = UDim.new(0, 6)
	Padding.PaddingRight = UDim.new(0, 12)
	Padding.Parent = List

	local Grid = Instance.new("UIGridLayout")
	Grid.SortOrder = Enum.SortOrder.LayoutOrder
	Grid.CellPadding = UDim2.new(CellGap, 0, 0, 8)
	Grid.FillDirectionMaxCells = Columns
	Grid.Parent = List

	--> The width is a share of the list, the height has to be pixels: a scale height would be a
	--> share of the canvas, which grows with the cards. Worked out again whenever the list resizes.
	local Width = (1 - CellGap * (Columns - 1)) / Columns
	local function Fit()
		local Inner = List.AbsoluteSize.X - Padding.PaddingLeft.Offset - Padding.PaddingRight.Offset

		Grid.CellSize = UDim2.new(Width, 0, 0, math.floor(Inner * Width / InventoryController.CellAspect))
	end

	List:GetPropertyChangedSignal("AbsoluteSize"):Connect(Fit)

	List.Parent = Panel
	Fit()

	Count = Label(Panel, CountName, UDim2.fromScale(0.62, 0.083), UDim2.fromScale(0.4, 0.07))

	return List, Count
end

--> Re-reads the save and lays the picked component out from scratch. Sixteen cards, and only on
--> opening, picking a category or a new find, so there is nothing to gain from patching.
function IndexController:Refresh()
	local Gui = self:GetGui()

	if not Gui then
		return
	end

	self:_Bind(Gui)

	local List, Count = self:_Build(Gui)

	if not List or not Count then
		return
	end

	for _, Child in List:GetChildren() do
		if Child:IsA("Frame") then
			Child:Destroy()
		end
	end

	local Found = PlayerData.Discovered() or {}
	local Total = 0

	for Order, Variant in Variants do
		local Has = Found[Discoveries.Key(self.Component, Variant)] == true

		if Has then
			Total += 1
		end

		local Card = InventoryController:Card({ Component = self.Component, Variant = Variant }, Has)

		if Card then
			Card.LayoutOrder = Order
			Card.Parent = List
		end
	end

	Count.Text = `{self.Component}s found: {Total}/{#Variants}`

	local Categories = Walk(Gui, CategoriesPath)

	for Component, ButtonName in Buttons do
		local Button = Categories and Categories:FindFirstChild(ButtonName)

		if Button and Button:IsA("ImageButton") then
			Button.ImageColor3 = if Component == self.Component then Color3.new(1, 1, 1) else Unpicked
		end
	end
end

--> The category buttons, once per copy of the screen.
function IndexController:_Bind(Gui: ScreenGui)
	if self.Bound == Gui then
		return
	end

	self.Bound = Gui

	local Categories = Walk(Gui, CategoriesPath)

	if not Categories then
		warn(`[Index] {GuiName} has no {table.concat(CategoriesPath, ".")}, so there is nothing to pick a part with`)
		return
	end

	for Component, ButtonName in Buttons do
		local Button = Categories:FindFirstChild(ButtonName)

		if not Button or not Button:IsA("GuiButton") then
			continue
		end

		Button.Active = true

		Button.Activated:Connect(function()
			if self.Component == Component then
				return
			end

			SoundController:Play("ShopClick")

			self.Component = Component
			self:Refresh()
		end)
	end
end

function IndexController:Init()
	UIController.Opened:Connect(function(Name: string)
		if Name == ScreenName then
			self:Refresh()
		end
	end)

	PlayerData.Discovered.Changed(function()
		local Gui = self:GetGui()

		if Gui and Gui.Enabled then
			self:Refresh()
		end
	end)
end

return IndexController
