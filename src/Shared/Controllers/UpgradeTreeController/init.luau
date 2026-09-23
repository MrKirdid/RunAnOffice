local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local Fusion = require(Shared.Packages.Fusion)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PanZoom = require(script.PanZoom)
local PlayerData = require(Shared.PlayerData).client
local ScreenShakeController = require(Shared.Controllers.ScreenShakeController)
local Signal = require(Shared.Packages.Fastsignal)
local SoundController = require(Shared.Controllers.SoundController)
local Tree = require(script.Tree)
local UIController = require(Shared.Controllers.UIController)
local UIMotion = require(Shared.Utilities.UIMotion)
local TutorialConfigs = require(Shared.Configs.Tutorial)
local TutorialController = require(Shared.Controllers.TutorialController)
local UpgradeDefinitions = require(Shared.Configs.UpgradeDefinitions)
local UpgradeRules = require(Shared.Utilities.UpgradeRules)
local Upgrades = require(Shared.Configs.Upgrades)

local Scope = Fusion.scoped(Fusion)

--> The card that follows the pointer over a node: the name, what buying it does, and the price.
--> Built in code and hung under the tree's own screen, so it is thrown away and rebuilt with it.
local TooltipName = "Tooltip"
local TooltipWidth = 0.17
local TooltipOffset = Vector2.new(18, 18)
local TooltipPadding = 10
local TooltipFont = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local TooltipBodyFont = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local TooltipBackground = Color3.fromRGB(18, 18, 24)
--> text as fractions of the screen's height, so the card reads the same on a phone as on a monitor
local TooltipTitleScale = 0.028
local TooltipBodyScale = 0.022

--> how far the tree opens backed off from a view fitted to what is bought, so the first look is
--> of the whole branch ahead rather than the two nodes owned
local OpenZoomOut = 2.3
local TooltipMinText = 12
local PriceColor = Color3.fromRGB(120, 255, 140)
local OwnedText = "Owned"
local NoEffectText = "Does nothing yet"

local GuiName = "UpgradeTree"
--> what UIController files this screen under, so the Exit node can close the same thing the hud
--> button opened
local Screen = "Upgrades"

--> How dark the backdrop sits behind the tree. The frame is built at 0.1, which is very nearly
--> solid black over the whole display: the tree stopped reading as a screen over the game and
--> started reading as a black screen with hexes on it. Every other panel just blurs the world, and
--> this now does the same, only more so.
local BackdropDim = 0.45

type Upgrade = Upgrades.Upgrade
type Node = Tree.Node
type TreeHandle = Tree.Tree

--> The tree is a screen and nothing else. It was drawn twice for a while, here and on a board out
--> on the plot that carried the same nodes on its face; the board is gone, and PlotService takes
--> its display off every plot as it builds one.
local UpgradeTreeController = {
	--> mirrors PlayerData.Upgrades.Owned. The save is what decides this, never the tree: a press
	--> asks the server and waits for the write to come back rather than marking the node itself.
	--> Handed to the tree by reference, so a sync fills it once.
	Owned = {} :: UpgradeRules.Owned,

	--> ids with a purchase in flight, so a second press while the first is still travelling does
	--> not send it twice
	Pending = {} :: { [string]: boolean },

	Menu = nil :: TreeHandle?,
	View = nil :: PanZoom.Handle?,
	Fade = nil :: UIMotion.Handle?,
	ViewScope = nil :: any,

	--> the card and the frame step that keeps it under the pointer while it is up
	Tooltip = nil :: Frame?,
	TooltipStep = nil :: RBXScriptConnection?,

	Pressed = Signal.new(),
}

--> the menu's node, which is the one anything outside the tree has ever meant by a node
local function BuildLabel(Name: string, FontFace: Font, Scale: number, Color: Color3, Parent: Instance): TextLabel
	local Label = Instance.new("TextLabel")
	Label.Name = Name
	Label.BackgroundTransparency = 1
	Label.AutomaticSize = Enum.AutomaticSize.Y
	Label.Size = UDim2.fromScale(1, 0)
	Label.FontFace = FontFace
	Label.TextSize = math.max(TooltipMinText, math.round((Parent.Parent :: GuiBase2d).AbsoluteSize.Y * Scale))
	Label.TextColor3 = Color
	Label.TextWrapped = true
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.RichText = false
	Label.Parent = Parent

	return Label
end

--> The card, empty and hidden, under whichever copy of the screen is up.
local function BuildTooltip(Gui: ScreenGui): Frame
	local Card = Instance.new("Frame")
	Card.Name = TooltipName
	Card.BackgroundColor3 = TooltipBackground
	Card.BackgroundTransparency = 0.1
	Card.BorderSizePixel = 0
	Card.AutomaticSize = Enum.AutomaticSize.Y
	Card.Size = UDim2.fromScale(TooltipWidth, 0)
	Card.Visible = false
	Card.ZIndex = 50

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 8)
	Corner.Parent = Card

	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Color3.new(1, 1, 1)
	Stroke.Transparency = 0.7
	Stroke.Thickness = 1.5
	Stroke.Parent = Card

	local Padding = Instance.new("UIPadding")
	Padding.PaddingTop = UDim.new(0, TooltipPadding)
	Padding.PaddingBottom = UDim.new(0, TooltipPadding)
	Padding.PaddingLeft = UDim.new(0, TooltipPadding)
	Padding.PaddingRight = UDim.new(0, TooltipPadding)
	Padding.Parent = Card

	Card.Parent = Gui

	local List = Instance.new("UIListLayout")
	List.SortOrder = Enum.SortOrder.LayoutOrder
	List.Padding = UDim.new(0, 4)
	List.Parent = Card

	BuildLabel("Title", TooltipFont, TooltipTitleScale, Color3.new(1, 1, 1), Card).LayoutOrder = 1
	BuildLabel("Effect", TooltipBodyFont, TooltipBodyScale, Color3.fromRGB(220, 220, 230), Card).LayoutOrder = 2
	BuildLabel("Price", TooltipFont, TooltipBodyScale, PriceColor, Card).LayoutOrder = 3

	return Card
end

--> Keeps the card just off the pointer, and inside the screen when the pointer is near an edge.
local function PlaceTooltip(Card: Frame)
	local Gui = Card.Parent :: ScreenGui
	local Mouse = UserInputService:GetMouseLocation() - Gui.AbsolutePosition
	local Size = Card.AbsoluteSize
	local Room = Gui.AbsoluteSize

	local X = Mouse.X + TooltipOffset.X
	local Y = Mouse.Y + TooltipOffset.Y

	if X + Size.X > Room.X then
		X = Mouse.X - TooltipOffset.X - Size.X
	end

	if Y + Size.Y > Room.Y then
		Y = Mouse.Y - TooltipOffset.Y - Size.Y
	end

	Card.Position = UDim2.fromOffset(math.max(X, 0), math.max(Y, 0))
end

--> What the card says about a node: its name, the one line its definition gives, and the price
--> or that it is already owned. The Exit node says nothing at all.
function UpgradeTreeController:_ShowTooltip(Id: string, Config: Upgrade)
	local Card = self.Tooltip

	if not Card or Config.IsAction then
		return
	end

	local Definition = UpgradeDefinitions[Id]
	local Effect = if Definition then Definition.Effect else (Config.Description or NoEffectText)

	local Title = Card:FindFirstChild("Title") :: TextLabel
	local Body = Card:FindFirstChild("Effect") :: TextLabel
	local Price = Card:FindFirstChild("Price") :: TextLabel

	Title.Text = Config.Text
	Body.Text = Effect
	Price.Text = if self:IsOwned(Id) then OwnedText else Format.Cash(UpgradeRules.GetCost(Id))

	PlaceTooltip(Card)
	Card.Visible = true

	if not self.TooltipStep then
		self.TooltipStep = RunService.RenderStepped:Connect(function()
			PlaceTooltip(Card)
		end)
	end
end

function UpgradeTreeController:_HideTooltip()
	if self.TooltipStep then
		self.TooltipStep:Disconnect()
		self.TooltipStep = nil
	end

	if self.Tooltip then
		self.Tooltip.Visible = false
	end
end

function UpgradeTreeController:GetNode(Id: string): Node?
	local Menu = self.Menu

	return if Menu then Menu:GetNode(Id) else nil
end

function UpgradeTreeController:IsOwned(Id: string): boolean
	return UpgradeRules.IsOwned(self.Owned, Id)
end

--> an upgrade can be bought when it is not owned yet and its parent is (the root has no parent, so
--> it is available from the start)
function UpgradeTreeController:IsAvailable(Id: string): boolean
	return UpgradeRules.IsAvailable(self.Owned, Id)
end

function UpgradeTreeController:SetOwned(Id: string, IsOwned: boolean)
	self.Owned[Id] = IsOwned or nil
	self:Refresh()
end

function UpgradeTreeController:SetOwnedList(List: { string })
	table.clear(self.Owned)

	for _, Id in List do
		self.Owned[Id] = true
	end

	self:Refresh()
end

--> Reads the owned set straight off the save. Called on open and again on every write to it, so
--> the tree is only ever a picture of the data rather than a second copy of it.
function UpgradeTreeController:Sync()
	table.clear(self.Owned)

	local Saved = PlayerData.Upgrades.Owned()

	if type(Saved) == "table" then
		for Id, IsOwned in Saved do
			self.Owned[Id] = IsOwned == true
		end
	end

	self:Refresh()
end

--> The tree against the owned set as it stands now.
function UpgradeTreeController:Refresh()
	if self.Menu then
		(self.Menu :: TreeHandle):Refresh()
	end
end

--> the node, where the tree is standing, for a purchase's punch and a refusal's wobble
function UpgradeTreeController:_WithNode(Id: string, Callback: (Node) -> ())
	local Node = self:GetNode(Id)

	if Node then
		Callback(Node)
	end
end

--> A press is a request and nothing more: the node does not light up until the server has taken
--> the cash and written the upgrade into the save, which is also the only place its effect runs.
function UpgradeTreeController:Buy(Id: string)
	if self.Pending[Id] then
		return
	end

	--> the tutorial's upgrade is free, and the server waives the price on the same condition
	local Cash = if TutorialConfigs.IsOn(PlayerData, "Upgrades") then math.huge else PlayerData.Cash()
	local Allowed, Reason = UpgradeRules.CanBuy(self.Owned, Id, Cash)

	if not Allowed then
		--> "Cash" is the only refusal a player can act on; the rest mean the tree is out of date,
		--> and the sync that fixes it is already on its way
		SoundController:Play(if Reason == "Cash" then "Error" else "Lock")

		if Reason == "Cash" then
			TutorialController:Notify(TutorialConfigs.Notices.NoCash)
		end

		self:_WithNode(Id, function(Node: Node)
			Node:nudge()
		end)

		return
	end

	self.Pending[Id] = true

	NetworkingClient.Upgrades.Buy
		.Invoke(Id)
		:andThen(function(Bought: boolean)
			SoundController:Play(if Bought then "Upgrade" else "Error")

			if Bought then
				local Config = Upgrades.List[Id]

				ScreenShakeController:Shake(1)
				TutorialController:Notify(`{if Config then Config.Text else Id} unlocked`)
			end

			--> the node is already owned by the time this lands, so this is the only thing marking
			--> the moment it was bought
			self:_WithNode(Id, function(Node: Node)
				if Bought then
					Node:punch()
					return
				end

				Node:nudge()
			end)
		end)
		:catch(function()
			SoundController:Play("Error")
		end)
		:finally(function()
			self.Pending[Id] = nil
		end)
end

--> A screen that is switched off has no size to measure, so the layout and the fit done while the
--> tree was closed are both meaningless. Opening it is the first moment the canvas is real.
function UpgradeTreeController:Refit()
	local Menu = self.Menu
	local View = self.View

	if not Menu or not View then
		return
	end

	Menu:Layout()

	local Min, Max = Menu:GetBounds()

	View.FitTo(Min, Max, OpenZoomOut)
end

function UpgradeTreeController:Replay()
	local Menu = self.Menu

	if not Menu then
		return
	end

	Menu:Replay()

	if self.Fade then
		(self.Fade :: UIMotion.Handle).Show()
	end

	self:Refit()
end

function UpgradeTreeController:Collapse()
	if self.Menu then
		(self.Menu :: TreeHandle):Collapse()
	end

	if self.Fade then
		(self.Fade :: UIMotion.Handle).Hide()
	end
end

function UpgradeTreeController:_Attach(Gui: ScreenGui)
	local Background = Gui:WaitForChild("Background")
	local Canvas = Background:WaitForChild("DragFrame") :: GuiObject
	local Window = Background:WaitForChild("BoundBox") :: GuiObject

	self:_HideTooltip()
	self.Tooltip = BuildTooltip(Gui)

	--> everything the old screen owned goes with it: springs, connections, the camera lock
	if self.ViewScope then
		Fusion.doCleanup(self.ViewScope)
	end

	if self.Menu then
		(self.Menu :: TreeHandle):Destroy()
	end

	self.ViewScope = Fusion.innerScope(Scope)

	self.Menu = Tree.new(Canvas, self.Owned, {
		OnPressed = function(Id: string, Config: Upgrade)
			local View = self.View

			if View and View.HasPanned() then
				return
			end

			self.Pressed:Fire(Id, Config)

			--> the Exit button in the middle has nothing to buy: it closes the screen, the same as
			--> pressing Upgrades on the hud again
			if Config.IsAction then
				UIController:Close(Screen)
				return
			end

			self:Buy(Id)
		end,
		OnHover = function(Id: string, Config: Upgrade, Hovering: boolean)
			if Hovering then
				self:_ShowTooltip(Id, Config)
			else
				self:_HideTooltip()
			end
		end,
		IsOpen = function(): boolean
			return UIController:IsOpen(Screen)
		end,
		ShowActions = true,
	})

	--> panning is handled here instead, so the detector would only fight it
	local Detector = Canvas:FindFirstChildOfClass("UIDragDetector")

	if Detector then
		Detector.Enabled = false
	end

	--> the tree fills the display rather than sitting in the middle of it, so the backdrop fades
	--> instead of popping. it lives on the view scope with everything else the screen owns.
	self.Fade = UIMotion.Fade(self.ViewScope, Background :: GuiObject, BackdropDim)

	local View = PanZoom.Apply(self.ViewScope, Canvas, Window)
	local Min, Max = (self.Menu :: TreeHandle):GetBounds()

	self.View = View

	View.FitTo(Min, Max, OpenZoomOut)
end

function UpgradeTreeController:Init()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	--> read before the tree is built, so a tree opened on a save with half the upgrades already
	--> bought draws them owned rather than popping them in a frame later
	self:Sync()

	--> Changed is a field, not a method: a colon here drops the callback. It fires for the whole
	--> owned table, which is every purchase this player makes, including the one they just pressed
	PlayerData.Upgrades.Owned.Changed(function()
		self:Sync()
	end)

	self:_Attach(PlayerGui:WaitForChild(GuiName) :: ScreenGui)

	UIController.Opened:Connect(function(Name: string)
		if Name == Screen then
			self:Replay()
		end
	end)

	UIController.Closed:Connect(function(Name: string)
		if Name == Screen then
			self:_HideTooltip()
		end

		if Name == Screen then
			self:Collapse()
		end
	end)

	--> Cash moves every second the plot is earning, and each tick can turn the next node from out
	--> of reach into affordable. Only worth redrawing while the tree is being looked at.
	PlayerData.Cash.Changed(function()
		if UIController:IsOpen(Screen) and self.Menu then
			(self.Menu :: TreeHandle):Refresh()
		end
	end)

	--> a screen with ResetOnSpawn on is thrown away and cloned again every respawn, and the copy
	--> has none of the tree in it
	PlayerGui.ChildAdded:Connect(function(Child: Instance)
		if Child.Name == GuiName and Child:IsA("ScreenGui") then
			self:_Attach(Child)
		end
	end)
end

return UpgradeTreeController
