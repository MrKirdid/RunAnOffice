--> One drawn copy of the upgrade tree: its nodes, where they sit on a canvas and which of them are
--> up. Two stand at once -- the menu, and the board out on the plot -- and both read the same
--> owned set, so a tree knows nothing about what is bought. It only draws.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local NodeConstructor = require(script.Parent.NodeConstructor)
local PlayerData = require(Shared.PlayerData).client
local UpgradeRules = require(Shared.Utilities.UpgradeRules)
local Upgrades = require(Shared.Configs.Upgrades)

local DefaultIcon = "rbxassetid://100568518943004"

--> how far apart, in seconds, each ring of the tree lands. tightened: at 0.075 a tree eight rings
--> deep was still arriving half a second after the backdrop had finished darkening
local RevealStep = 0.045

--> the same, folding away. the tree collapses outside in, so the ring furthest from the middle
--> goes first and the Exit button under the cursor is the last thing left
local CollapseStep = 0.028

--> the spin a node leaves with, as it shrinks into nothing
local CollapseSpin = 220

--> a node revealed by a purchase rather than by the screen opening. long enough that the node
--> being bought reads as the thing that opened it, short enough to still feel like one press
local UnlockDelay = 0.12

--> centre to centre, as a multiple of a node's height. the hex art only fills about nine tenths of
--> its square box, so edge to edge is 0.9 and this leaves the thin dark gap the reference tree has
local NodeSpacing = 1.08

local Diagonal = math.sqrt(3) / 2

--> unit steps, so every neighbour sits the same distance away whatever the canvas' aspect ratio is
local Directions = {
	Top = Vector2.new(0, -1),
	Bottom = Vector2.new(0, 1),
	TopLeft = Vector2.new(-Diagonal, -0.5),
	TopRight = Vector2.new(Diagonal, -0.5),
	BottomLeft = Vector2.new(-Diagonal, 0.5),
	BottomRight = Vector2.new(Diagonal, 0.5),

	--> not neighbours: a hex has no side facing straight left or right, so the nearest cell that way
	--> is two columns across. nodes placed like this sit level with their parent with a gap between
	Left = Vector2.new(-2 * Diagonal, 0),
	Right = Vector2.new(2 * Diagonal, 0),
}

type Upgrade = Upgrades.Upgrade

export type Node = NodeConstructor.Node

export type Options = {
	--> what a press on a node does. the tree only draws; buying is the controller's
	OnPressed: (Id: string, Config: Upgrade) -> (),

	--> the pointer coming onto a node and going off it again, for the tooltip. the tree only
	--> reports; what is said about the node is the controller's
	OnHover: (Id: string, Config: Upgrade, Hovering: boolean) -> (),

	--> whether anybody is looking. nothing stands up while this is false, or a tree behind a
	--> switched off screen is a fully drawn tree on screen for the frame the screen comes on
	IsOpen: () -> boolean,

	--> off for the board: the Exit node in the middle has nothing to close out there
	ShowActions: boolean,
}

type TreeData = {
	Canvas: GuiObject,
	Owned: UpgradeRules.Owned,
	Options: Options,
	Nodes: { [string]: Node },
	Children: { [string]: { string } },

	--> bumped every time the tree opens or folds, so the delays left over from a fold that was
	--> interrupted can tell they are stale and drop out
	Generation: number,
}

local Tree = {}
Tree.__index = Tree

export type Tree = typeof(setmetatable({} :: TreeData, Tree))

function Tree.new(Canvas: GuiObject, Owned: UpgradeRules.Owned, Options: Options): Tree
	local self: Tree = setmetatable({
		Canvas = Canvas,
		Owned = Owned,
		Options = Options,
		Nodes = {},
		Children = {},
		Generation = 0,
	}, Tree)

	local Building = {}

	for Id in Upgrades.List do
		self.Children[Id] = {}
	end

	for Id, Config in Upgrades.List do
		self:_BuildNode(Id, Building)

		if Config.Parent then
			table.insert(self.Children[Config.Parent], Id)
		end
	end

	self:Layout()

	--> the opening pass, so the rings that are yours unfold outwards rather than all landing at once
	self:Refresh(true)

	Canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Layout()
	end)

	return self
end

function Tree.GetNode(self: Tree, Id: string): Node?
	return self.Nodes[Id]
end

--> The tree only draws what is yours and what you could buy next. Anything further out is not
--> dimmed, it is not there: the first press opens the ring behind it.
--> Of what is drawn, three states read differently: owned carries no price, affordable glows, and
--> one you cannot pay for yet keeps its price but greys out.
function Tree.Refresh(self: Tree, Opening: boolean?)
	local Cash = PlayerData.Cash()
	local IsOpen = self.Options.IsOpen()

	for Id, Node in self.Nodes do
		local Config = Upgrades.List[Id]
		local IsOwned = UpgradeRules.IsOwned(self.Owned, Id)
		local IsAvailable = UpgradeRules.IsAvailable(self.Owned, Id)
		local IsVisible = UpgradeRules.IsVisible(self.Owned, Id) and (self.Options.ShowActions or not Config.IsAction)
		local CanAfford = IsAvailable and Cash >= UpgradeRules.GetCost(Id)
		local ShouldShow = IsVisible and IsOpen

		if ShouldShow ~= Node:isVisible() then
			--> opening staggers by ring so the whole tree unfolds; a purchase only ever reveals
			--> the ring next to it, which lands as one beat instead
			local Delay = if not ShouldShow then 0 elseif Opening then Node:getDepth() * RevealStep else UnlockDelay

			Node:setIsVisible(ShouldShow, Delay)
		end

		if not IsVisible then
			continue
		end

		Node:setIsLocked(IsAvailable and not CanAfford)
		Node:setIsHighlighted(CanAfford and not Config.IsAction)

		if IsOwned or not Config.Cost then
			Node:setPrice(nil)
			continue
		end

		Node:setPrice({ quantity = Config.Cost, currencyIcon = Upgrades.CashIcon })
	end
end

function Tree._BuildNode(self: Tree, Id: string, Building: { [string]: boolean }): Node
	local Existing = self.Nodes[Id]

	if Existing then
		return Existing
	end

	local Config = Upgrades.List[Id]
	assert(Config, `"{Id}" is not an upgrade in Configs.Upgrades`)
	assert(not Building[Id], `"{Id}" is its own ancestor in Configs.Upgrades`)

	Building[Id] = true

	local ParentNode: Node? = nil

	if Config.Parent then
		ParentNode = self:_BuildNode(Config.Parent, Building)
	end

	assert(not Config.Direction or Directions[Config.Direction], `"{Config.Direction}" is not a direction ({Id})`)

	local Node = NodeConstructor.new({
		icon = Config.Icon or DefaultIcon,
		text = Config.Text,
		headerText = Config.Header,
		color = Config.Color,
	}, ParentNode)

	Node:setParent(self.Canvas)
	Node:setPressedCallback(function()
		self.Options.OnPressed(Id, Config)
	end)

	local Button = Node:getInstance()

	Button.MouseEnter:Connect(function()
		self.Options.OnHover(Id, Config, true)
	end)

	Button.MouseLeave:Connect(function()
		self.Options.OnHover(Id, Config, false)
	end)

	Building[Id] = nil
	self.Nodes[Id] = Node

	return Node
end

--> walks the tree from its roots, so a node is always placed after the parent it hangs off
function Tree.Layout(self: Tree)
	local CanvasSize = self.Canvas.AbsoluteSize
	local Step = NodeConstructor.NodeSize.Y.Scale * CanvasSize.Y * NodeSpacing

	local function Place(Id: string, Position: UDim2)
		self.Nodes[Id]:setPosition(Position)

		for _, ChildId in self.Children[Id] do
			local Direction = Directions[Upgrades.List[ChildId].Direction or "Top"]
			local Offset = UDim2.fromScale(Direction.X * Step / CanvasSize.X, Direction.Y * Step / CanvasSize.Y)

			Place(ChildId, Position + Offset)
		end
	end

	for Id, Config in Upgrades.List do
		if Config.Parent then
			continue
		end

		Place(Id, UDim2.fromScale(0.5, 0.5))
	end
end

--> the corners the drawn part of the tree occupies, in canvas scale, node bodies included. hidden
--> nodes are still laid out -- their children hang off them -- but a view fitted to those would
--> open zoomed out on empty canvas
function Tree.GetBounds(self: Tree): (Vector2, Vector2)
	local Half = NodeConstructor.NodeSize.Y.Scale / 2
	local CanvasSize = self.Canvas.AbsoluteSize

	--> a canvas that has not been through a render pass yet is 0 by 0, and 0 / 0 is not a ratio
	local Aspect = if CanvasSize.X > 0 then CanvasSize.Y / CanvasSize.X else 1
	local Min = Vector2.new(math.huge, math.huge)
	local Max = -Min

	for Id, Node in self.Nodes do
		if not UpgradeRules.IsVisible(self.Owned, Id) then
			continue
		end

		local Position = Node:getPosition()
		local Center = Vector2.new(Position.X.Scale, Position.Y.Scale)
		local Padding = Vector2.new(Half * Aspect, Half)

		Min = Min:Min(Center - Padding)
		Max = Max:Max(Center + Padding)
	end

	return Min, Max
end

--> The tree's own way of opening, in place of the pop every other screen gets: every node is taken
--> down and then let back in ring by ring, so it unfolds out of the middle each time it is opened
--> rather than only on the first build.
function Tree.Replay(self: Tree)
	self.Generation += 1

	for _, Node in self.Nodes do
		Node:setIsVisible(false)
	end

	self:Layout()
	self:Refresh(true)
end

--> And the way it closes: the nodes shrink into nothing while the screen is still up, so the tree
--> folds away instead of being switched off mid-frame.
function Tree.Collapse(self: Tree)
	self.Generation += 1

	local Generation = self.Generation
	local Deepest = 0

	for _, Node in self.Nodes do
		Deepest = math.max(Deepest, Node:getDepth())
	end

	for _, Node in self.Nodes do
		if not Node:isVisible() then
			continue
		end

		--> outside in, so the tree pulls back towards the middle rather than dropping all at once
		local Delay = (Deepest - Node:getDepth()) * CollapseStep

		task.delay(Delay, function()
			--> a tree reopened mid fold has already put these back up, and this is the older pass
			--> still running out its delays
			if self.Generation ~= Generation then
				return
			end

			Node:nudge(CollapseSpin)
			Node:setIsVisible(false)
		end)
	end
end

function Tree.Destroy(self: Tree)
	for _, Node in self.Nodes do
		Node:destroy()
	end

	table.clear(self.Nodes)
	table.clear(self.Children)
end

return Tree
