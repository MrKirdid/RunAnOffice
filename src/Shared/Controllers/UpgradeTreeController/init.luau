local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Fusion = require(Shared.Packages.Fusion)
local NodeConstructor = require(script.NodeConstructor)
local PanZoom = require(script.PanZoom)
local Signal = require(Shared.Packages.Fastsignal)
local Upgrades = require(Shared.Configs.Upgrades)

local Scope = Fusion.scoped(Fusion)

local GuiName = "UpgradeTree"
local DefaultIcon = "rbxassetid://100568518943004"
--> how far apart, in seconds, each ring of the tree lands
local RevealStep = 0.075

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
type Node = NodeConstructor.Node

local UpgradeTreeController = {
	Nodes = {} :: { [string]: Node },
	Owned = {} :: { [string]: boolean },

	Canvas = nil :: GuiObject?,
	View = nil :: PanZoom.Handle?,
	ViewScope = nil :: any,
	Children = {} :: { [string]: { string } },

	Pressed = Signal.new(),
}

function UpgradeTreeController:GetNode(Id: string): Node?
	return self.Nodes[Id]
end

function UpgradeTreeController:IsOwned(Id: string): boolean
	local Config = Upgrades.List[Id]

	if Config and Config.IsAction then
		return true
	end

	return self.Owned[Id] == true
end

--> an upgrade can be bought when it is not owned yet and its parent is (the root has no parent, so
--> it is available from the start)
function UpgradeTreeController:IsAvailable(Id: string): boolean
	local Config = Upgrades.List[Id]

	if not Config or self:IsOwned(Id) then
		return false
	end

	return Config.Parent == nil or self:IsOwned(Config.Parent)
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

function UpgradeTreeController:Refresh()
	for Id, Node in self.Nodes do
		local Config = Upgrades.List[Id]
		local IsOwned = self:IsOwned(Id)
		local IsAvailable = self:IsAvailable(Id)

		Node:setIsLocked(not IsOwned and not IsAvailable)
		Node:setIsHighlighted(IsAvailable and not Config.IsAction)

		if IsOwned or not Config.Cost then
			Node:setPrice(nil)
			continue
		end

		Node:setPrice({ quantity = Config.Cost, currencyIcon = Upgrades.CashIcon })
	end
end

function UpgradeTreeController:_BuildNode(Id: string, Building: { [string]: boolean }): Node
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

	Node:setParent(self.Canvas :: GuiObject)
	Node:setPressedCallback(function()
		local View = self.View

		if View and View.HasPanned() then
			return
		end

		self.Pressed:Fire(Id, Config)
	end)

	Building[Id] = nil
	self.Nodes[Id] = Node

	return Node
end

--> walks the tree from its roots, so a node is always placed after the parent it hangs off
function UpgradeTreeController:_Layout()
	local Canvas = self.Canvas

	if not Canvas then
		return
	end

	local CanvasSize = Canvas.AbsoluteSize
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

--> the corners the whole tree occupies, in canvas scale, node bodies included
function UpgradeTreeController:GetBounds(): (Vector2, Vector2)
	local Half = NodeConstructor.NodeSize.Y.Scale / 2
	local Aspect = if self.Canvas then self.Canvas.AbsoluteSize.Y / self.Canvas.AbsoluteSize.X else 1
	local Min = Vector2.new(math.huge, math.huge)
	local Max = -Min

	for _, Node in self.Nodes do
		local Position = Node:getPosition()
		local Center = Vector2.new(Position.X.Scale, Position.Y.Scale)
		local Padding = Vector2.new(Half * Aspect, Half)

		Min = Min:Min(Center - Padding)
		Max = Max:Max(Center + Padding)
	end

	return Min, Max
end

function UpgradeTreeController:Build(Canvas: GuiObject)
	self:Clear()
	self.Canvas = Canvas

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

	self:_Layout()

	for _, Node in self.Nodes do
		Node:setIsVisible(true, Node:getDepth() * RevealStep)
	end

	self:Refresh()

	Canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_Layout()
	end)
end

function UpgradeTreeController:Clear()
	for _, Node in self.Nodes do
		Node:destroy()
	end

	table.clear(self.Nodes)
	table.clear(self.Children)
end

function UpgradeTreeController:_Attach(Gui: ScreenGui)
	local Background = Gui:WaitForChild("Background")
	local Canvas = Background:WaitForChild("DragFrame") :: GuiObject
	local Window = Background:WaitForChild("BoundBox") :: GuiObject

	--> everything the old screen owned goes with it: springs, connections, the camera lock
	if self.ViewScope then
		Fusion.doCleanup(self.ViewScope)
	end

	self.ViewScope = Fusion.innerScope(Scope)

	self:Build(Canvas)

	--> panning is handled here instead, so the detector would only fight it
	local Detector = Canvas:FindFirstChildOfClass("UIDragDetector")

	if Detector then
		Detector.Enabled = false
	end

	self.View = PanZoom.Apply(self.ViewScope, Canvas, Window);
	(self.View :: PanZoom.Handle).FitTo(self:GetBounds())
end

function UpgradeTreeController:Init()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	self:_Attach(PlayerGui:WaitForChild(GuiName) :: ScreenGui)

	--> a screen with ResetOnSpawn on is thrown away and cloned again every respawn, and the copy
	--> has none of the tree in it
	PlayerGui.ChildAdded:Connect(function(Child: Instance)
		if Child.Name == GuiName and Child:IsA("ScreenGui") then
			self:_Attach(Child)
		end
	end)
end

return UpgradeTreeController
