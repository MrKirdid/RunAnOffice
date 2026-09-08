local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local PlayerData = require(Shared.PlayerData).client
local Products = require(Shared.Configs.Products)
local Renders = require(Shared.Configs.Renders)
local SoundController = require(Shared.Controllers.SoundController)
local Store = require(Shared.Utilities.Store)

--> The shop is a screen UIController opens and shuts; this fills it. ShopUI in the place is the
--> drawn one, exactly as it was drawn: a panel, a header, icons down its left edge and a
--> scroller of example rows. Nothing in the place is renamed or removed. On build the example
--> rows are read as templates -- one of each kind is cloned into a Templates folder and shaped,
--> the originals go -- and then Configs.Products.Layout is walked top to bottom, cloning a
--> template per entry. So the shop looks like whatever was drawn, and sells whatever is listed.
local GuiName = "ShopUI"
local PanelPath = "MainBackground.MainBackground"
local TemplatesName = "Templates"

--> The rate the hud reads, published by RevenueService on the Player. A time skip is worth that
--> many seconds of it, and the card says so in cash rather than in hours.
local RateAttribute = "MoneyPerSecond"

--> Where the six rungs sit across the ladder row, as fractions of its width. The row was drawn
--> with five boxes; a sixth needs them a touch slimmer.
local StepStart = 0.27
local StepGap = 0.126
local StepY = 0.475
local StepSize = UDim2.fromScale(0.105, 0.27)

--> The icons down the panel's left edge, top to bottom, and the row each one jumps to.
local RailSections = { "Passes", "Luck", "Packs", "Cash" }
local RailMinWidth = 0.1

local OwnedText = "OWNED"
local MaxedText = "MAXED"
local BoughtMark = "✓"

local OwnedColor = Color3.fromRGB(190, 190, 190)
local NextStrokeColor = Color3.fromRGB(255, 255, 255)

type Entry = Products.Entry
type Rung = Products.Rung
type Place = (GuiObject) -> GuiObject

--> Everything a button needs to ask Roblox for a purchase.
type Product = {
	Key: string,
	Kind: Products.Kind,
	Id: number,
	Price: number,
}

local ShopController = {
	Panel = nil :: Frame?,
	Scroll = nil :: ScrollingFrame?,

	--> the row each rail icon jumps to, by section name
	Anchors = {} :: { [string]: GuiObject },

	--> which passes this player already has, by key. Filled in as the checks come back.
	Owned = {} :: { [string]: boolean },

	--> what Roblox says each id costs, so a rebuild does not ask again
	Prices = {} :: { [number]: number },

	--> the skip cards' cash labels, refreshed whenever the rate moves
	SkipLabels = {} :: { { Label: TextLabel, Hours: number } },

	--> cards waiting to be paired into a row, see Flush
	PendingCards = {} :: { Entry },
}

--> "MainBackground.MainBackground" walked one name at a time, so a screen rebuilt without one of
--> those links gives back nothing instead of erroring.
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

local function Gradient(Stops: { Color3 }): ColorSequence
	local Keypoints = {}

	for Index, Color in Stops do
		table.insert(Keypoints, ColorSequenceKeypoint.new((Index - 1) / (#Stops - 1), Color))
	end

	return ColorSequence.new(Keypoints)
end

--> Recolours the gradient a row or card was drawn with, if it has one.
local function Paint(Object: Instance, Name: string?)
	local Stops = if Name then Products.Gradients[Name] else nil
	local Existing = Object:FindFirstChildWhichIsA("UIGradient")

	if Stops and Existing then
		Existing.Color = Gradient(Stops)
	end
end

local function Rate(): number
	return Players.LocalPlayer:GetAttribute(RateAttribute) or 0
end

--> What a card draws: its own icon, or the computer of the part set it hands out.
local function IconOf(Entry: Entry): string
	if Entry.Icon and Entry.Icon ~= "" then
		return Entry.Icon
	end

	local Render = if Entry.Variant then Renders.Components[Entry.Variant] else nil

	return if Render then Render.Computer else ""
end

local function ProductOf(Entry: Entry): Product
	return {
		Key = Entry.Key or "?",
		Kind = Entry.Kind or "Product",
		Id = Entry.Id or 0,
		Price = Entry.Price or 0,
	}
end

local function BindButton(Button: GuiButton, Press: () -> ())
	Button.Active = true
	Button.Activated:Connect(Press)

	Button.MouseEnter:Connect(function()
		SoundController:Play("Hover")
	end)
end

--> An icon drawn as a label rather than a button still takes a press.
local function BindPress(Object: GuiObject, Press: () -> ())
	Object.Active = true

	Object.InputBegan:Connect(function(Input: InputObject)
		if
			Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		then
			Press()
		end
	end)
end

local function Label(Parent: Instance, Name: string): TextLabel
	local Found = Parent:FindFirstChild(Name)

	if not Found or not Found:IsA("TextLabel") then
		error(`[Shop] template "{Parent.Name}" has no label called {Name}`)
	end

	return Found
end

local function Child(Parent: Instance, Name: string): Instance
	local Found = Parent:FindFirstChild(Name)

	if not Found then
		error(`[Shop] template "{Parent.Name}" has nothing called {Name}`)
	end

	return Found
end

local function TextLabelsOf(Parent: Instance): { TextLabel }
	local Labels = {}

	for _, Object in Parent:GetChildren() do
		if Object:IsA("TextLabel") then
			table.insert(Labels, Object)
		end
	end

	return Labels
end

local function ByX(A: GuiObject, B: GuiObject): boolean
	return A.Position.X.Scale < B.Position.X.Scale
end

local function ByY(A: GuiObject, B: GuiObject): boolean
	return A.Position.Y.Scale < B.Position.Y.Scale
end

--> A row is sized by its width and nothing else, so an auto-sizing canvas can grow under it
--> without the row shrinking to meet it. Drawn "fit within", which is fine against a fixed
--> canvas and a feedback loop against a growing one.
local function WidthBound(Row: GuiObject)
	local Constraint = Row:FindFirstChildWhichIsA("UIAspectRatioConstraint")

	if Constraint then
		Constraint.AspectType = Enum.AspectType.ScaleWithParentSize
		Constraint.DominantAxis = Enum.DominantAxis.Width
	end
end

--> Which kind of example row this is, read off what was drawn in it.
local function KindOf(Row: Instance): string?
	local Steps, Slots, Buys, Close = 0, 0, 0, false

	for _, Object in Row:GetChildren() do
		if Object.Name == "Main" then
			Steps += 1
		elseif Object.Name == "Slot" and Object:IsA("ImageButton") then
			Slots += 1
		elseif Object.Name == "GreenButton" then
			Buys += 1
		elseif Object.Name == "CloseButton" then
			Close = true
		end
	end

	if Steps >= 2 then
		return "Ladder"
	end

	if Slots >= 1 then
		return "CardRow"
	end

	if Close and Buys >= 1 then
		return "Feature"
	end

	if Row:FindFirstChild("Title") then
		return "Header"
	end

	return nil
end

--> The drawn ladder: five step boxes, three buttons, a title drawn twice for its shadow, a timer
--> on the right and a big icon. Kept: one step, one button, one title, the timer as a subtitle.
local function ShapeLadder(Row: GuiObject)
	local Steps, Buys, Titles = {}, {}, {}

	for _, Object in Row:GetChildren() do
		if Object.Name == "Main" and Object:IsA("GuiObject") then
			table.insert(Steps, Object)
		elseif Object.Name == "GreenButton" and Object:IsA("ImageButton") then
			table.insert(Buys, Object)
		elseif Object:IsA("TextLabel") then
			table.insert(Titles, Object)
		end
	end

	table.sort(Steps, ByX)
	table.sort(Buys, ByX)

	for Index = 2, #Steps do
		Steps[Index]:Destroy()
	end

	for Index = 1, #Buys - 1 do
		Buys[Index]:Destroy()
	end

	local Step = Steps[1]
	local StepLabels = TextLabelsOf(Step)

	table.sort(StepLabels, ByY)

	Step.Name = "Step"
	Step.Size = StepSize
	StepLabels[1].Name = "Rung"
	StepLabels[2].Name = "Price"

	local Buy = Buys[#Buys]

	Buy.Name = "Buy"
	Child(Buy, "TitleName").Name = "Price"

	local Big, Timer = {}, nil

	for _, Title in Titles do
		if Title.Size.X.Scale > 0.5 then
			table.insert(Big, Title)
		else
			Timer = Title
		end
	end

	table.sort(Big, function(A: TextLabel, B: TextLabel)
		return A.Position.Y.Scale > B.Position.Y.Scale
	end)

	Big[1].Name = "Title"

	for Index = 2, #Big do
		Big[Index]:Destroy()
	end

	if Timer then
		Timer.Name = "Subtitle"
	end

	Child(Row, "CloseButton").Name = "Icon"
end

--> The drawn feature row: a title drawn twice, a subtitle, a description, a big icon, a button.
local function ShapeFeature(Row: GuiObject)
	local Big, Sub = {}, nil

	for _, Title in TextLabelsOf(Row) do
		if Title.Name == "TitleName" then
			Title.Name = "Description"
		elseif Title.Size.X.Scale > 0.5 then
			table.insert(Big, Title)
		else
			Sub = Title
		end
	end

	table.sort(Big, function(A: TextLabel, B: TextLabel)
		return A.Position.Y.Scale > B.Position.Y.Scale
	end)

	Big[1].Name = "Title"

	for Index = 2, #Big do
		Big[Index]:Destroy()
	end

	if Sub then
		Sub.Name = "Subtitle"
	end

	Child(Row, "CloseButton").Name = "Icon"

	local Buy = Child(Row, "GreenButton")

	Buy.Name = "Buy"
	Child(Buy, "TitleName").Name = "Price"
end

--> The drawn card row: two slot buttons, each with a title drawn twice, a description, an icon,
--> a price button and a gift badge.
local function ShapeCardRow(Row: GuiObject)
	local Cards = {}

	for _, Object in Row:GetChildren() do
		if Object:IsA("ImageButton") then
			table.insert(Cards, Object)
		end
	end

	table.sort(Cards, ByX)

	for Index, Card in Cards do
		local Names, Description = {}, nil

		for _, Title in TextLabelsOf(Card) do
			if Title.TextXAlignment == Enum.TextXAlignment.Left then
				table.insert(Names, Title)
			else
				Description = Title
			end
		end

		Names[1].Name = "Title"

		for Extra = 2, #Names do
			Names[Extra]:Destroy()
		end

		if Description then
			Description.Name = "Description"
		end

		Child(Card, "TitleIcon").Name = "Icon"

		local Buy = Child(Card, "GreenButton")

		Buy.Name = "Buy"
		Child(Buy, "TitleName").Name = "Price"

		local Badge = Card:FindFirstChild("GiftButton")

		if Badge and Badge:IsA("GuiObject") then
			Badge.Name = "Badge"
			Badge.Visible = false

			local Timer = Badge:FindFirstChild("UnlockTimerLabel")

			if Timer then
				Timer.Name = "Label"
			end
		end

		Card.Name = if Index == 1 then "CardA" else "CardB"
		Card.LayoutOrder = Index
	end
end

local Shapers: { [string]: (GuiObject) -> () } = {
	Ladder = ShapeLadder,
	Feature = ShapeFeature,
	CardRow = ShapeCardRow,
	Header = function() end,
}

--> Reads the example rows out of the scroller as templates: the first of each kind is cloned
--> into a Templates folder and shaped, and every example row is then taken down. Runs once per
--> copy of the screen, which is once per respawn.
function ShopController:_Adopt(Panel: Frame, Scroll: ScrollingFrame): Folder
	local Existing = Panel:FindFirstChild(TemplatesName)

	if Existing and Existing:IsA("Folder") then
		return Existing
	end

	local Templates = Instance.new("Folder")
	Templates.Name = TemplatesName

	for _, Row in Scroll:GetChildren() do
		if not Row:IsA("GuiObject") then
			continue
		end

		local Kind = KindOf(Row)

		if Kind and not Templates:FindFirstChild(Kind) then
			local Template = Row:Clone()

			Template.Name = Kind
			Template.Visible = false

			Shapers[Kind](Template)
			WidthBound(Template)

			Template.Parent = Templates
		end

		Row:Destroy()
	end

	for _, Kind in { "Ladder", "Feature", "CardRow", "Header" } do
		if not Templates:FindFirstChild(Kind) then
			warn(`[Shop] {GuiName} has no example row to use as a {Kind}`)
		end
	end

	--> the scroller fits its rows and scrolls only down
	Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Scroll.CanvasSize = UDim2.new()
	Scroll.ScrollingDirection = Enum.ScrollingDirection.Y

	local Layout = Scroll:FindFirstChildWhichIsA("UIListLayout")

	if Layout then
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end

	Templates.Parent = Panel

	return Templates
end

function ShopController:_Template(Name: string): GuiObject
	local Panel = self.Panel :: Frame
	local Templates = Panel:FindFirstChild(TemplatesName)
	local Template = Templates and Templates:FindFirstChild(Name)

	if not Template or not Template:IsA("GuiObject") then
		error(`[Shop] the panel has no template called {Name}`)
	end

	local Row = Template:Clone()
	Row.Visible = true

	return Row
end

--> What the button reads. Roblox is the source of a price once the product exists there; the
--> config number is only what a product shows before it does.
function ShopController:_ShowPrice(Product: Product, Price: TextLabel)
	local Cached = self.Prices[Product.Id]

	if Cached then
		Price.Text = tostring(Cached)
		return
	end

	Price.Text = tostring(Product.Price)

	if Product.Id == 0 then
		return
	end

	task.spawn(function()
		local InfoType = if Product.Kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local Ok, Info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, Product.Id, InfoType)

		if not Ok or type(Info) ~= "table" or type(Info.PriceInRobux) ~= "number" then
			return
		end

		self.Prices[Product.Id] = Info.PriceInRobux

		if Price.Parent then
			Price.Text = tostring(Info.PriceInRobux)
		end
	end)
end

function ShopController:Prompt(Product: Product)
	if Product.Id == 0 then
		SoundController:Play("Error")
		warn(`[Shop] "{Product.Key}" has no product id yet`)

		return
	end

	SoundController:Play("ShopClick")

	if Product.Kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, Product.Id)
		return
	end

	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, Product.Id)
end

function ShopController:_MarkOwned(Buy: ImageButton)
	Buy.ImageColor3 = OwnedColor
	Buy.AutoButtonColor = false

	Label(Buy, "Price").Text = OwnedText
end

--> The save is the server's word on a pass and is here before any pass has an id; Roblox is
--> asked once per pass on top of that and remembered, so a card rebuilt on a respawn reads
--> OWNED straight away rather than after the round trip.
function ShopController:_CheckOwned(Product: Product, Buy: ImageButton)
	if self.Owned[Product.Key] or Store.Owns(PlayerData, Product.Key) then
		self.Owned[Product.Key] = true
		self:_MarkOwned(Buy)

		return
	end

	if Product.Kind ~= "Pass" or Product.Id == 0 then
		return
	end

	task.spawn(function()
		local Ok, Owns =
			pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, Players.LocalPlayer.UserId, Product.Id)

		if not Ok or not Owns then
			return
		end

		self.Owned[Product.Key] = true

		if Buy.Parent then
			self:_MarkOwned(Buy)
		end
	end)
end

--> The price button, and anything else on the row that should do what it does.
function ShopController:_BindBuy(Product: Product, Buy: ImageButton, ...: GuiButton)
	self:_ShowPrice(Product, Label(Buy, "Price"))
	self:_CheckOwned(Product, Buy)

	local function Press()
		if self.Owned[Product.Key] then
			return
		end

		self:Prompt(Product)
	end

	BindButton(Buy, Press)

	for _, Button in { ... } do
		BindButton(Button, Press)
	end
end

function ShopController:_FillCard(Card: ImageButton, Entry: Entry)
	local Description = Label(Card, "Description")

	Card.Name = Entry.Key or Card.Name
	Label(Card, "Title").Text = Entry.Title or ""
	Description.Text = Entry.Description or ""
	(Child(Card, "Icon") :: ImageLabel).Image = IconOf(Entry)

	Paint(Card, Entry.Gradient)

	if Entry.Hours then
		table.insert(self.SkipLabels, { Label = Description, Hours = Entry.Hours })
	end

	self:_BindBuy(ProductOf(Entry), Child(Card, "Buy") :: ImageButton, Card)
end

--> Cards are pooled as the layout is walked and paired into rows when something that is not a
--> card comes along, or the list ends. An odd one leaves the second half of its row empty
--> rather than stretching across it.
function ShopController:_Flush(Place: Place)
	local Cards = self.PendingCards

	for Index = 1, #Cards, 2 do
		local Row = self:_Template("CardRow")
		local CardA = Child(Row, "CardA") :: ImageButton
		local CardB = Child(Row, "CardB") :: ImageButton

		self:_FillCard(CardA, Cards[Index])

		local Second = Cards[Index + 1]

		if Second then
			self:_FillCard(CardB, Second)
		else
			CardB.Visible = false
		end

		Place(Row)
	end

	table.clear(Cards)
end

--> One function per template name. Each gets the entry and a Place that parents the row in
--> order, and hands back the row so an Anchor can point at it.
local Fillers: { [string]: (any, Entry, Place) -> GuiObject? } = {}

function Fillers.Card(self, Entry: Entry)
	table.insert(self.PendingCards, Entry)

	return nil
end

function Fillers.Header(self, Entry: Entry, Place: Place)
	local Row = self:_Template("Header")

	Row.Name = (Entry.Title or "Header") .. "Header"
	Label(Row, "Title").Text = Entry.Title or ""

	return Place(Row)
end

function Fillers.Feature(self, Entry: Entry, Place: Place)
	local Row = self:_Template("Feature")
	local Icon = Child(Row, "Icon") :: ImageButton

	Row.Name = Entry.Key or Row.Name
	Label(Row, "Title").Text = Entry.Title or ""
	Label(Row, "Subtitle").Text = Entry.Subtitle or ""
	Label(Row, "Description").Text = Entry.Description or ""
	Icon.Image = IconOf(Entry)

	Paint(Row, Entry.Gradient)

	self:_BindBuy(ProductOf(Entry), Child(Row, "Buy") :: ImageButton, Icon)

	return Place(Row)
end

--> The rungs drawn as steps, the ones already bought ticked, the next one lit and priced on the
--> button. Only that one is ever for sale.
function Fillers.Ladder(self, Entry: Entry, Place: Place)
	local Row = self:_Template("Ladder")
	local Subtitle = Label(Row, "Subtitle")
	local Buy = Child(Row, "Buy") :: ImageButton
	local Step = Child(Row, "Step") :: Frame
	local Rungs = Entry.Rungs or {}

	local Owned = PlayerData.Store.CashRung()
	local Next = Rungs[Owned + 1]

	Row.Name = Entry.Key or Row.Name
	Label(Row, "Title").Text = Entry.Title or ""
	(Child(Row, "Icon") :: ImageButton).Image = IconOf(Entry)

	Paint(Row, Entry.Gradient)

	for Index, Rung in Rungs do
		local Box = if Index == 1 then Step else Step:Clone()
		local Stroke = Box:FindFirstChildWhichIsA("UIStroke")

		Box.Name = Rung.Key
		Box.Position = UDim2.fromScale(StepStart + (Index - 1) * StepGap, StepY)
		Label(Box, "Rung").Text = "x" .. Rung.Multiplier
		Label(Box, "Price").Text = if Index <= Owned then BoughtMark else tostring(Rung.Price)

		if Stroke and Index == Owned + 1 then
			Stroke.Color = NextStrokeColor
		end

		Box.Parent = Row
	end

	if not Next then
		Subtitle.Text = "Every rung bought!"
		Label(Buy, "Price").Text = MaxedText
		Buy.ImageColor3 = OwnedColor
		Buy.AutoButtonColor = false

		return Place(Row)
	end

	Subtitle.Text = `Next: x{Next.Multiplier} cash`

	local Product: Product = { Key = Next.Key, Kind = "Product", Id = Next.Id, Price = Next.Price }

	self:_ShowPrice(Product, Label(Buy, "Price"))

	BindButton(Buy, function()
		self:Prompt(Product)
	end)

	return Place(Row)
end

--> A skip card is worth whatever the plot makes right now, and says so in cash.
function ShopController:_RefreshSkips()
	local Current = Rate()

	for _, Entry in self.SkipLabels do
		if Entry.Label.Parent then
			Entry.Label.Text = "+" .. Format.Cash(Current * Entry.Hours * 3600)
		end
	end
end

--> The icons drawn down the panel's left edge, top to bottom, each jumping to a section. They
--> are labels in the place and stay labels; a press on one is read straight off it.
function ShopController:_BindRail()
	local Panel = self.Panel :: Frame
	local Scroll = self.Scroll :: ScrollingFrame
	local Icons = {}

	for _, Object in Panel:GetChildren() do
		if Object.Name == "Icon" and Object:IsA("ImageLabel") and Object.Size.X.Scale > RailMinWidth then
			table.insert(Icons, Object)
		end
	end

	table.sort(Icons, ByY)

	for Index, Icon in Icons do
		local Section = RailSections[Index]

		if not Section then
			break
		end

		BindPress(Icon, function()
			local Row = self.Anchors[Section]

			if not Row then
				return
			end

			SoundController:Play("Click")

			local Offset = Row.AbsolutePosition.Y - Scroll.AbsolutePosition.Y + Scroll.CanvasPosition.Y

			Scroll.CanvasPosition = Vector2.new(0, math.max(Offset, 0))
		end)
	end
end

function ShopController:Build(Gui: ScreenGui)
	local Panel = Resolve(Gui, PanelPath)

	if not Panel or not Panel:IsA("Frame") then
		warn(`[Shop] {GuiName} has no panel at {PanelPath}`)
		return
	end

	local Scroll = Panel:FindFirstChildWhichIsA("ScrollingFrame")

	if not Scroll then
		warn(`[Shop] {GuiName} has no scroller`)
		return
	end

	self.Panel = Panel
	self.Scroll = Scroll
	table.clear(self.Anchors)
	table.clear(self.SkipLabels)
	table.clear(self.PendingCards)

	--> the first build of a copy reads the drawn rows as templates and takes them down; every
	--> build after that only has the rows it built itself to clear
	local Adopted = self:_Adopt(Panel, Scroll)

	for _, Existing in Scroll:GetChildren() do
		if Existing:IsA("GuiObject") then
			Existing:Destroy()
		end
	end

	local Order = 0

	local function Place(Row: GuiObject): GuiObject
		Order += 1
		Row.LayoutOrder = Order
		Row.Parent = Scroll

		return Row
	end

	for _, Entry in Products.Layout do
		local Fill = Fillers[Entry.Template]

		if not Fill or not Adopted:FindFirstChild(if Entry.Template == "Card" then "CardRow" else Entry.Template) then
			warn(`[Shop] no template for "{Entry.Template}" ({Entry.Key or Entry.Title or "?"})`)
			continue
		end

		--> a run of cards ends the moment something else is placed
		if Entry.Template ~= "Card" then
			self:_Flush(Place)
		end

		--> sold once and already bought: the row is simply not there any more
		if Entry.Once and Entry.Key and PlayerData.Store.OwnedProducts()[Entry.Key] then
			continue
		end

		local Row = Fill(self, Entry, Place)

		if Row and Entry.Anchor then
			self.Anchors[Entry.Anchor] = Row
		end
	end

	self:_Flush(Place)
	self:_RefreshSkips()
	self:_BindRail()
end

function ShopController:Start()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	self:Build(PlayerGui:WaitForChild(GuiName) :: ScreenGui)

	--> Cloned again every respawn, drawn rows and all, and the copy has none of these connections.
	PlayerGui.ChildAdded:Connect(function(Added: Instance)
		if Added:IsA("ScreenGui") and Added.Name == GuiName then
			self:Build(Added)
		end
	end)

	Players.LocalPlayer:GetAttributeChangedSignal(RateAttribute):Connect(function()
		self:_RefreshSkips()
	end)

	local function Rebuild()
		local Gui = PlayerGui:FindFirstChild(GuiName)

		if Gui and Gui:IsA("ScreenGui") then
			self:Build(Gui)
		end
	end

	--> a pass just bought reads OWNED without waiting for a respawn
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(Player: Player, _Id: number, Purchased: boolean)
		if Player ~= Players.LocalPlayer or not Purchased then
			return
		end

		SoundController:Play("PurchaseSuccess")
		Rebuild()
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(UserId: number, _Id: number, Purchased: boolean)
		if UserId ~= Players.LocalPlayer.UserId or not Purchased then
			return
		end

		SoundController:Play("PurchaseSuccess")
	end)

	--> everything the server grants lands in the save, and the shop is redrawn off it: the next
	--> rung, a pass reading OWNED, a one-time pack going away
	PlayerData.Store.Changed(function()
		Rebuild()
	end)
end

return ShopController
