local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local PlayerData = require(Shared.PlayerData).client
local Products = require(Shared.Configs.Products)
local PurchaseController = require(Shared.Controllers.PurchaseController)
local Renders = require(Shared.Configs.Renders)
local Revenue = require(Shared.Utilities.Revenue)
local SoundController = require(Shared.Controllers.SoundController)
local Store = require(Shared.Utilities.Store)
local UIFx = require(Shared.Utilities.UIFx)

--> The shop is a screen UIController opens and shuts; this fills it. Every row is one drawn in
--> the place -- Pack, Feature, Header, Card and CashCard in ShopUI's scroller -- cloned as it
--> is, with its text and images changed and nothing else. Configs.Products.Layout is walked top
--> to bottom, one clone per entry.
local GuiName = "ShopUI"
local PanelPath = "MainBackground.MainBackground"
local TemplatesName = "Templates"

--> The names the drawn rows carry in the place.
local RowTemplates = { "Pack", "Feature", "Header", "Card", "CashCard" }

--> a built header is named for its section with this on the end, which is how a rail jump
--> tells a section that starts with a title from one that is a single row
local HeaderSuffix = "Header"

--> The rate the hud reads, published by RevenueService on the Player. A time skip is worth that
--> many seconds of it, and the card says so in cash rather than in hours.
local RateAttribute = "MoneyPerSecond"

--> The icons down the panel's left edge, each named for the section it jumps to, and the arrow
--> beside them that points at whichever section is on screen.
local RailSections = { "Packs", "Luck", "Passes", "Cash" }
local ArrowName = "Arrow"
local ScrollTween = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local ArrowTween = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--> how far down the view a section's top has to reach before the arrow counts it as read,
--> as a fraction of the view, and how close to the end counts as the bottom, in pixels
local ArrowLine = 0.4
local BottomSlack = 4

--> The pack row was drawn with three item boxes: two captioned underneath with a badge over
--> each, the third labelled beside it. Captions sit in the lower half of the row.
local PackBoxes = 3
local CaptionLine = 0.55

--> The timer line on a pack, coloured the way the row was drawn.
local TimerColor = "rgb(255,23,0)"
local TimerInterval = 1

--> The luck row's subtitle, current tier to the next, coloured the way the row was drawn.
local NextColor = "rgb(255,240,0)"

local OwnedText = "OWNED"
local MaxedText = "MAXED"
local OwnedColor = Color3.fromRGB(190, 190, 190)

type Entry = Products.Entry
type Offer = PurchaseController.Offer
type Place = (GuiObject) -> GuiObject

--> One box on a pack row.
type Item = {
	Icon: string,
	Count: number,
	Name: string,
	--> what the item earns, on the badge over it
	Rate: string,
	--> the third box reads a label pair instead of a caption
	Top: string?,
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

	--> the skip cards' cash numbers, refreshed whenever the rate moves
	SkipLabels = {} :: { { Label: TextLabel, Hours: number } },

	--> the pack timers, ticked once a second
	Timers = {} :: { { Label: TextLabel, ExpiresAt: number } },

	--> cards waiting to be paired into a row, all of one template, see Flush
	PendingCards = {} :: { Entry },
	PendingTemplate = nil :: string?,

	--> true while a rail press is gliding the list, so the scroll does not steer the arrow
	ArrowHeld = false,
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

local function Child(Parent: Instance, Name: string): Instance
	local Found = Parent:FindFirstChild(Name)

	if not Found then
		error(`[Shop] "{Parent.Name}" has nothing called {Name}`)
	end

	return Found
end

local function ByX(A: GuiObject, B: GuiObject): boolean
	return A.Position.X.Scale < B.Position.X.Scale
end

local function ByY(A: GuiObject, B: GuiObject): boolean
	return A.Position.Y.Scale < B.Position.Y.Scale
end

--> The labels drawn directly on a row that pass a test, left to right. A title is drawn twice
--> for its shadow, so a text is set on every label that matches rather than the first.
local function Labels(Parent: Instance, Keep: (TextLabel) -> boolean): { TextLabel }
	local Found = {}

	for _, Object in Parent:GetChildren() do
		if Object:IsA("TextLabel") and Keep(Object) then
			table.insert(Found, Object)
		end
	end

	table.sort(Found, ByX)

	return Found
end

local function SetAll(List: { TextLabel }, Text: string)
	for _, Label in List do
		Label.Text = Text
	end
end

local function Named(Name: string): (GuiObject) -> boolean
	return function(Object: GuiObject): boolean
		return Object.Name == Name
	end
end

local function IsTitle(Label: TextLabel): boolean
	return Label.Name == "Title" and not Label.RichText and Label.TextXAlignment == Enum.TextXAlignment.Left
end

local function IsCentredTitle(Label: TextLabel): boolean
	return Label.Name == "Title" and not Label.RichText and Label.TextXAlignment == Enum.TextXAlignment.Center
end

local function IsTimer(Label: TextLabel): boolean
	return Label.Name == "Title" and Label.RichText
end

local function Children(Parent: Instance, Keep: (GuiObject) -> boolean): { GuiObject }
	local Found = {}

	for _, Object in Parent:GetChildren() do
		if Object:IsA("GuiObject") and Keep(Object) then
			table.insert(Found, Object)
		end
	end

	table.sort(Found, ByX)

	return Found
end

local function Hide(Parent: Instance, Name: string)
	local Found = Parent:FindFirstChild(Name)

	if Found and Found:IsA("GuiObject") then
		Found.Visible = false
	end
end

local function Gradient(Stops: { Color3 }): ColorSequence
	local Keypoints = {}

	for Index, Color in Stops do
		table.insert(Keypoints, ColorSequenceKeypoint.new((Index - 1) / (#Stops - 1), Color))
	end

	return ColorSequence.new(Keypoints)
end

--> Recolours the gradient a row or card was drawn with, only when the entry names one, and sets
--> it drifting either way.
local function Paint(Object: Instance, Name: string?)
	local Stops = if Name then Products.Gradients[Name] else nil
	local Existing = Object:FindFirstChildWhichIsA("UIGradient")

	if not Existing then
		return
	end

	if Stops then
		Existing.Color = Gradient(Stops)
	end

	UIFx.Drift(Existing)
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

local function OfferOf(Entry: Entry, Title: string?, Description: string?): Offer
	return {
		Key = Entry.Key or "?",
		Kind = Entry.Kind or "Product",
		Id = Entry.Id or 0,
		Price = Entry.Price or 0,
		Title = Title or Entry.Title or "",
		Description = Description or Entry.Description or "",
		Icon = IconOf(Entry),
	}
end

--> "1d 10h 10m" the way the timer line was drawn, down to minutes, then seconds for the last one.
local function Clock(Seconds: number): string
	local Left = math.max(math.floor(Seconds), 0)
	local Days = Left // 86400
	local Hours = Left % 86400 // 3600
	local Minutes = Left % 3600 // 60

	if Days > 0 then
		return `{Days}d {Hours}h {Minutes}m`
	end

	if Hours > 0 then
		return `{Hours}h {Minutes}m`
	end

	if Minutes > 0 then
		return `{Minutes}m`
	end

	return `{Left}s`
end

local function BindButton(Button: GuiButton, Press: () -> ())
	Button.Active = true
	Button.Activated:Connect(Press)

	Button.MouseEnter:Connect(function()
		SoundController:Play("Hover")
	end)

	UIFx.Press(Button)
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

--> The rows drawn in the place, copied once per copy of the screen into a hidden Templates
--> folder, and the drawn rows then taken down so the scroller holds only what is built.
function ShopController:_Adopt(Panel: Frame, Scroll: ScrollingFrame): Folder
	local Existing = Panel:FindFirstChild(TemplatesName)

	if Existing and Existing:IsA("Folder") then
		return Existing
	end

	local Templates = Instance.new("Folder")
	Templates.Name = TemplatesName

	for _, Name in RowTemplates do
		local Source = Scroll:FindFirstChild(Name)

		if not Source or not Source:IsA("GuiObject") then
			warn(`[Shop] no row called {Name} to clone`)
			continue
		end

		local Template = Source:Clone()

		Template.Name = Name
		Template.Visible = false
		WidthBound(Template)
		Template.Parent = Templates
	end

	for _, Row in Scroll:GetChildren() do
		if Row:IsA("GuiObject") then
			Row:Destroy()
		end
	end

	--> The scroller fits its rows and scrolls only down. Sized by hand off what the list lays
	--> out: automatic canvas sizing measures the rows before their aspect constraints have
	--> settled and never looks again, so it stopped about halfway down the shop.
	Scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	Scroll.ScrollingDirection = Enum.ScrollingDirection.Y

	local Layout = Scroll:FindFirstChildWhichIsA("UIListLayout")

	if Layout then
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

		Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			self:_FitCanvas()
		end)
	end

	Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_PointArrow()
	end)

	Templates.Parent = Panel

	return Templates
end

--> The canvas is exactly as tall as the rows laid out in it, plus the padding drawn under them.
function ShopController:_FitCanvas()
	local Scroll = self.Scroll

	if not Scroll then
		return
	end

	local Layout = Scroll:FindFirstChildWhichIsA("UIListLayout")
	local Padding = Scroll:FindFirstChildWhichIsA("UIPadding")

	if not Layout then
		return
	end

	local Extra = if Padding then Padding.PaddingTop.Offset + Padding.PaddingBottom.Offset else 0
	local Fraction = if Padding then Padding.PaddingTop.Scale + Padding.PaddingBottom.Scale else 0

	--> The content height is measured on screen, after every UIScale above it -- the panel pops
	--> open on one -- and an offset handed back gets scaled by them again. Divided out, so the
	--> canvas is right at every point of the pop rather than only once it has settled.
	local Scale = 1
	local Ancestor: Instance? = Scroll

	while Ancestor and not Ancestor:IsA("ScreenGui") do
		local UIScale = Ancestor:FindFirstChildOfClass("UIScale")

		if UIScale then
			Scale *= math.max(UIScale.Scale, 0.01)
		end

		Ancestor = Ancestor.Parent
	end

	--> A padding drawn in scale is a fraction of the canvas itself, so the canvas has to be the
	--> height that leaves the rows exactly their room once that fraction is taken off the top.
	local Rows = Layout.AbsoluteContentSize.Y / Scale + Extra

	Scroll.CanvasSize = UDim2.fromOffset(0, Rows / math.max(1 - Fraction, 0.5))
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
function ShopController:_ShowPrice(Offer: Offer, Price: TextLabel)
	local Cached = self.Prices[Offer.Id]

	if Cached then
		Offer.Price = Cached
		Price.Text = Format.Robux(Cached)

		return
	end

	Price.Text = Format.Robux(Offer.Price)

	if Offer.Id == 0 then
		return
	end

	task.spawn(function()
		local InfoType = if Offer.Kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local Ok, Info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, Offer.Id, InfoType)

		if not Ok or type(Info) ~= "table" or type(Info.PriceInRobux) ~= "number" then
			return
		end

		self.Prices[Offer.Id] = Info.PriceInRobux
		Offer.Price = Info.PriceInRobux

		if Price.Parent then
			Price.Text = Format.Robux(Info.PriceInRobux)
		end
	end)
end

function ShopController:_MarkOwned(Buy: ImageButton, Text: string?)
	Buy.ImageColor3 = OwnedColor
	Buy.AutoButtonColor = false
	(Child(Buy, "TitleName") :: TextLabel).Text = Text or OwnedText
end

--> The save is the server's word on a pass and is here before any pass has an id; Roblox is
--> asked once per pass on top of that and remembered, so a card rebuilt on a respawn reads
--> OWNED straight away rather than after the round trip.
function ShopController:_CheckOwned(Offer: Offer, Buy: ImageButton)
	if self.Owned[Offer.Key] or Store.Owns(PlayerData, Offer.Key) then
		self.Owned[Offer.Key] = true
		self:_MarkOwned(Buy)

		return
	end

	if Offer.Kind ~= "Pass" or Offer.Id == 0 then
		return
	end

	task.spawn(function()
		local Ok, Owns =
			pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, Players.LocalPlayer.UserId, Offer.Id)

		if not Ok or not Owns then
			return
		end

		self.Owned[Offer.Key] = true

		if Buy.Parent then
			self:_MarkOwned(Buy)
		end
	end)
end

--> The price button, and anything else on the row that should do what it does: the offer goes
--> to the confirm popup.
function ShopController:_BindBuy(Offer: Offer, Buy: ImageButton, ...: GuiObject)
	self:_ShowPrice(Offer, Child(Buy, "TitleName") :: TextLabel)
	self:_CheckOwned(Offer, Buy)

	local function Press()
		if self.Owned[Offer.Key] then
			SoundController:Play("Error")
			return
		end

		SoundController:Play("ShopClick")
		PurchaseController:Show(Offer)
	end

	BindButton(Buy, Press)

	for _, Object in { ... } do
		if Object:IsA("GuiButton") then
			BindButton(Object, Press)
		else
			BindPress(Object, Press)
		end
	end
end

--> The ladder as a card: the next rung is what is for sale, at its price, and the card says
--> where the player is.
function ShopController:_FillLadder(Card: ImageButton, Entry: Entry)
	local Rungs = Entry.Rungs or {}
	local Owned = PlayerData.Store.CashRung()
	local Current = Rungs[Owned]
	local Next = Rungs[Owned + 1]
	local Buy = Child(Card, "GreenButton") :: ImageButton

	if not Next then
		SetAll(Labels(Card, IsTitle), `Cash x{if Current then Current.Multiplier else 1}`)
		SetAll(Labels(Card, IsCentredTitle), "Every rung bought!")
		self:_MarkOwned(Buy, MaxedText)

		return
	end

	local Title = `Cash x{Next.Multiplier}`
	local Description = if Current then `You have x{Current.Multiplier}!` else "Every desk pays more!"

	SetAll(Labels(Card, IsTitle), Title)
	SetAll(Labels(Card, IsCentredTitle), Description)

	local Offer: Offer = {
		Key = Next.Key,
		Kind = "Product",
		Id = Next.Id,
		Price = Next.Price,
		Title = Title,
		Description = "Every desk pays more, forever!",
		Icon = IconOf(Entry),
	}

	self:_BindBuy(Offer, Buy, Card)
end

--> A pass card: icon, title, description, price.
function ShopController:_FillCard(Card: ImageButton, Entry: Entry)
	local Icon = Child(Card, "TitleIcon") :: ImageLabel

	Card.Name = Entry.Key or Card.Name
	Icon.Image = IconOf(Entry)

	Hide(Card, "GiftButton")
	Paint(Card, Entry.Gradient)
	UIFx.Bob(Icon)

	if Entry.Rungs then
		self:_FillLadder(Card, Entry)
		return
	end

	SetAll(Labels(Card, IsTitle), Entry.Title or "")
	SetAll(Labels(Card, IsCentredTitle), Entry.Description or "")

	self:_BindBuy(OfferOf(Entry), Child(Card, "GreenButton") :: ImageButton, Card)
end

--> A cash card: one big number, which for a skip is the cash it is worth right now.
function ShopController:_FillCashCard(Card: ImageButton, Entry: Entry)
	local Titles = Labels(Card, IsTitle)
	local Icon = Card:FindFirstChild("TitleIcon")

	Card.Name = Entry.Key or Card.Name

	Hide(Card, "GiftButton")
	Paint(Card, Entry.Gradient)
	SetAll(Titles, Entry.Title or "")

	if Icon and Icon:IsA("ImageLabel") then
		Icon.Image = IconOf(Entry)
		UIFx.Bob(Icon)
	end

	if Entry.Hours then
		for _, Label in Titles do
			table.insert(self.SkipLabels, { Label = Label, Hours = Entry.Hours })
		end
	end

	self:_BindBuy(OfferOf(Entry), Child(Card, "GreenButton") :: ImageButton, Card)
end

--> Cards are pooled as the layout is walked and paired into rows when something else comes
--> along, or the list ends. An odd one leaves the second half of its row empty.
function ShopController:_Flush(Place: Place)
	local Cards = self.PendingCards
	local Template = self.PendingTemplate

	if not Template then
		return
	end

	local Fill = if Template == "CashCard" then self._FillCashCard else self._FillCard

	for Index = 1, #Cards, 2 do
		local Row = self:_Template(Template)
		local Slots = Children(Row, Named("Slot"))

		Fill(self, Slots[1] :: ImageButton, Cards[Index])

		local Second = Cards[Index + 1]

		if Second and Slots[2] then
			Fill(self, Slots[2] :: ImageButton, Second)
		elseif Slots[2] then
			Slots[2].Visible = false
		end

		Place(Row)
	end

	table.clear(Cards)
	self.PendingTemplate = nil
end

--> What goes in a pack's boxes, in order: each part set, the workers, the cash.
local function ItemsOf(Entry: Entry): { Item }
	local Items: { Item } = {}
	local Contents: { Products.DeskSet } = Entry.Contents or {}

	--> a part set is the computer, keyboard and monitor of one variant; the badge is what all
	--> the sets in the box pay a second, before any worker or multiplier
	for _, Set in Contents do
		local Render = Renders.Components[Set.Variant]
		local PerSet = 0

		for _, Component in { "Computer", "Keyboard", "Monitor" } do
			PerSet += Revenue.ComponentValue(Component, Set.Variant)
		end

		table.insert(Items, {
			Icon = if Render then Render.Computer else "",
			Count = Set.Sets,
			Name = Set.Variant .. " Pack",
			Rate = Format.Rate(PerSet * Set.Sets),
		})
	end

	if Entry.Employee and Entry.Employees then
		table.insert(Items, {
			Icon = Renders.Employees[Entry.Employee] or Products.Icons.Trophy,
			Count = Entry.Employees,
			Name = Entry.Employee,
			Rate = `x{Revenue.Multiplier(Entry.Employee)} cash`,
		})
	end

	if Entry.Bonus and Entry.Bonus > 0 then
		table.insert(Items, {
			Icon = Products.Icons.Cash,
			Count = 1,
			Name = Format.Cash(Entry.Bonus),
			Rate = "",
			Top = "Bonus",
		})
	end

	return Items
end

--> One function per template name. Each gets the entry and a Place that parents the row in
--> order, and hands back the row so an Anchor can point at it.
local Fillers: { [string]: (any, Entry, Place) -> GuiObject? } = {}

function Fillers.Card(self, Entry: Entry)
	table.insert(self.PendingCards, Entry)

	return nil
end

Fillers.CashCard = Fillers.Card

function Fillers.Header(self, Entry: Entry, Place: Place)
	local Row = self:_Template("Header")

	Row.Name = (Entry.Title or "") .. HeaderSuffix
	SetAll(Labels(Row, Named("Title")), Entry.Title or "")

	return Place(Row)
end

--> Server luck: the row always offers the tier above what the server is running, and reads
--> current to next the way it was drawn.
function Fillers.Feature(self, Entry: Entry, Place: Place)
	local Row = self:_Template("Feature")
	local Icon = Child(Row, "CloseButton") :: ImageButton
	local Buy = Child(Row, "GreenButton") :: ImageButton

	Row.Name = Entry.Key or Row.Name
	Icon.Image = IconOf(Entry)

	SetAll(Labels(Row, IsCentredTitle), Entry.Title or "")
	SetAll(Labels(Row, Named("TitleName")), Entry.Description or "")
	Paint(Row, Entry.Gradient)
	UIFx.Bob(Icon)

	local Next = if Entry.Tiers then Store.NextTier() else nil

	if not Next then
		SetAll(Labels(Row, IsTimer), Entry.Subtitle or "")
		self:_BindBuy(OfferOf(Entry), Buy, Icon)

		return Place(Row)
	end

	local Current = Store.ServerLuck()

	SetAll(Labels(Row, IsTimer), `{Current}x → <font color="{NextColor}">{Next.Multiplier}x</font>`)

	local Offer: Offer = {
		Key = Next.Key,
		Kind = "Product",
		Id = Next.Id,
		Price = Next.Price,
		Title = `Server Luck {Next.Multiplier}x`,
		Description = `{Next.Minutes} minutes of {Next.Multiplier}x luck for the whole server!`,
		Icon = IconOf(Entry),
	}

	self:_BindBuy(Offer, Buy, Icon)

	return Place(Row)
end

--> A pack: the title, the timer line for the starter and the contents line for the rest, and
--> the three boxes -- an icon each, a badge over and a caption under the first two, the label
--> beside the third.
function Fillers.Pack(self, Entry: Entry, Place: Place)
	local Row = self:_Template("Pack")
	local Timer = Labels(Row, IsTimer)[1]
	local Icons = Children(Row, Named("Icon"))
	local Badges = Labels(Row, Named("Badge"))
	local Buy = Child(Row, "GreenButton") :: ImageButton

	local Captions = Labels(Row, function(Label: TextLabel): boolean
		return Label.Name == "TitleName" and Label.Position.Y.Scale > CaptionLine
	end)

	--> the labels beside the third box, top to bottom: drawn as a pair, or as the value alone
	local Sides = Labels(Row, function(Label: TextLabel): boolean
		return Label.Name == "TitleName" and Label.TextXAlignment == Enum.TextXAlignment.Left
	end)

	table.sort(Sides, ByY)

	Row.Name = Entry.Key or Row.Name
	SetAll(Labels(Row, IsTitle), Entry.Title or "")
	Hide(Row, "GiftButton")
	Paint(Row, Entry.Gradient)
	UIFx.Shine(Buy)

	local Items = ItemsOf(Entry)

	for Index = 1, PackBoxes do
		local Item = Items[Index]
		local Icon = Icons[Index]

		if Icon and Icon:IsA("ImageLabel") then
			Icon.Image = if Item then Item.Icon else ""
			Icon.Visible = Item ~= nil

			if Item then
				UIFx.Bob(Icon)
			end
		end

		if Index < PackBoxes then
			local Caption = Captions[Index]
			local Badge = Badges[Index]

			if Caption then
				Caption.Text = if Item then `x{Item.Count} {Item.Name}!` else ""
			end

			if Badge then
				Badge.Text = if Item then Item.Rate else ""
			end

			continue
		end

		local Value = if Item then (if Item.Top then Item.Name else string.upper(Item.Name)) else ""
		local Top = if Item then (Item.Top or `x{Item.Count}`) else ""

		for Line, Label in Sides do
			Label.Text = if #Sides > 1 and Line == 1 then Top else Value
		end
	end

	if Timer and Entry.Timed then
		table.insert(self.Timers, { Label = Timer, ExpiresAt = PlayerData.Store.StarterExpiresAt() })
		self:_TickTimers()
	elseif Timer then
		Timer.Text = Entry.Subtitle or ""
	end

	self:_BindBuy(OfferOf(Entry), Buy)

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

--> The starter's timer line, and the row taken down the second it runs out.
function ShopController:_TickTimers()
	local Now = os.time()

	for _, Timer in self.Timers do
		if not Timer.Label.Parent then
			continue
		end

		--> the server stamps the day on the first join; until the stamp lands the offer is up
		local Left = if Timer.ExpiresAt == 0 then Store.StarterWindow else Timer.ExpiresAt - Now

		if Left <= 0 then
			Timer.Label.Text = "Gone!"
			continue
		end

		Timer.Label.Text = `Only for <font color="{TimerColor}">{Clock(Left)}</font>`
	end
end

--> Where a row's top sits on the canvas.
function ShopController:_CanvasTop(Row: GuiObject): number
	local Scroll = self.Scroll :: ScrollingFrame

	return Row.AbsolutePosition.Y - Scroll.AbsolutePosition.Y + Scroll.CanvasPosition.Y
end

--> Slides the arrow to a section's icon.
function ShopController:_Aim(Section: string)
	local Panel = self.Panel

	if not Panel then
		return
	end

	local Arrow = Panel:FindFirstChild(ArrowName)
	local Icon = Panel:FindFirstChild(Section)

	if not Arrow or not Arrow:IsA("GuiObject") or not Icon or not Icon:IsA("GuiObject") then
		return
	end

	local Goal = UDim2.new(Arrow.Position.X, Icon.Position.Y)

	if Arrow.Position ~= Goal then
		TweenService:Create(Arrow, ArrowTween, { Position = Goal }):Play()
	end
end

--> The arrow points at the last section whose top has scrolled up to just under the top edge of
--> the view: that is the one being read, even when it is a single short row with the next
--> header right under it. At the very bottom it is the last section, whether or not the list
--> was long enough to bring that header to the top. Held still while a rail press is gliding
--> the list, so it goes straight where the press said.
function ShopController:_PointArrow()
	local Scroll = self.Scroll

	if not Scroll or self.ArrowHeld then
		return
	end

	local Line = Scroll.CanvasPosition.Y + Scroll.AbsoluteWindowSize.Y * ArrowLine
	local Bottom = Scroll.AbsoluteCanvasSize.Y - Scroll.AbsoluteWindowSize.Y - BottomSlack
	local AtBottom = Scroll.CanvasPosition.Y >= Bottom
	local Current: string? = nil
	local Best = -math.huge

	for Section, Row in self.Anchors do
		local Top = self:_CanvasTop(Row)

		if (AtBottom or Top <= Line) and Top > Best then
			Best = Top
			Current = Section
		end
	end

	if Current then
		self:_Aim(Current)
	end
end

--> The icons drawn down the panel's left edge, each named for a section. They are labels in the
--> place and stay labels; a press on one is read straight off it and glides the list there.
function ShopController:_BindRail()
	local Panel = self.Panel :: Frame

	for _, Section in RailSections do
		local Icon = Panel:FindFirstChild(Section)

		if not Icon or not Icon:IsA("GuiObject") then
			warn(`[Shop] no rail icon called {Section}`)
			continue
		end

		UIFx.Press(Icon)

		BindPress(Icon, function()
			if self.Anchors[Section] then
				SoundController:Play("Click")
			end

			self:JumpTo(Section)
		end)
	end

	self:_PointArrow()
end

--> Glides the list to a section, one of RailSections, and points the arrow at its icon. For the
--> rail, and for anything outside the shop that opens it on a section, like the + by the cash.
function ShopController:JumpTo(Section: string)
	local Row = self.Anchors[Section]
	local Scroll = self.Scroll

	if not Row or not Scroll then
		return
	end

	--> a section headed by a title lands with the title at the top; one that is a single
	--> row, like server luck, lands with that row in the middle of the view
	local Window = Scroll.AbsoluteWindowSize.Y
	local Limit = math.max(Scroll.AbsoluteCanvasSize.Y - Window, 0)
	local Top = self:_CanvasTop(Row)
	local IsHeader = string.sub(Row.Name, -#HeaderSuffix) == HeaderSuffix
	local Wanted = if IsHeader then Top else Top - (Window - Row.AbsoluteSize.Y) / 2
	local Goal = math.clamp(Wanted, 0, Limit)

	self.ArrowHeld = true
	self:_Aim(Section)

	TweenService:Create(Scroll, ScrollTween, { CanvasPosition = Vector2.new(0, Goal) }):Play()

	task.delay(ScrollTween.Time, function()
		self.ArrowHeld = false
	end)
end

--> Whether an entry is on the shelf at all right now.
local function Offered(Entry: Entry): boolean
	if not Entry.Key or not Entry.Once then
		return true
	end

	if Entry.Timed then
		return Store.StarterOnOffer(PlayerData)
	end

	return not PlayerData.Store.OwnedProducts()[Entry.Key]
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
	table.clear(self.Timers)
	table.clear(self.PendingCards)
	self.PendingTemplate = nil

	--> the first build of a copy reads the drawn rows as templates and takes them down; every
	--> build after that only has the rows it built itself to clear
	local Templates = self:_Adopt(Panel, Scroll)

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

		if not Fill or not Templates:FindFirstChild(Entry.Template) then
			warn(`[Shop] no template for "{Entry.Template}" ({Entry.Key or Entry.Title or "?"})`)
			continue
		end

		--> a run of cards ends the moment something else is placed
		if Entry.Template ~= self.PendingTemplate then
			self:_Flush(Place)
		end

		if not Offered(Entry) then
			continue
		end

		if Fill == Fillers.Card then
			self.PendingTemplate = Entry.Template
		end

		local Row = Fill(self, Entry, Place)

		if Row and Entry.Anchor then
			self.Anchors[Entry.Anchor] = Row
		end
	end

	self:_Flush(Place)
	self:_RefreshSkips()
	self:_BindRail()
	self:_FitCanvas()

	--> the header bar's gold breathes
	local Header = Panel:FindFirstChild("Level")
	local Gold = if Header then Header:FindFirstChildWhichIsA("UIGradient") else nil

	if Gold then
		UIFx.Drift(Gold)
	end
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
		if Player == Players.LocalPlayer and Purchased then
			Rebuild()
		end
	end)

	--> everything the server grants lands in the save, and the shop is redrawn off it: the next
	--> rung, a pass reading OWNED, a one-time pack going away
	PlayerData.Store.Changed(function()
		Rebuild()
	end)

	--> the luck row offers the tier above whatever is running, so it follows the server's boost
	Workspace:GetAttributeChangedSignal(Store.LuckAttribute):Connect(Rebuild)

	task.spawn(function()
		while true do
			task.wait(TimerInterval)

			self:_TickTimers()
		end
	end)
end

return ShopController
