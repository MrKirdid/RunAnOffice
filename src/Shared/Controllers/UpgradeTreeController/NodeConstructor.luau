--!strict

--[[
	NodeConstructor

	An upgrade tree node. Every node builds its own GUI, animates itself and
	handles its own input, so nothing else has to ship alongside it — no template
	asset, no support modules.

	A node is an object: it owns its instances, its colour and its notification
	state. Tree logic (who is visible, who is owned) lives outside of it.

		local root = NodeConstructor.new({ icon = ICON, text = "Root" })
		root:setParent(mainFrame)
		root:setIsVisible(true)

		local coins = NodeConstructor.new({
			direction = NodeConstructor.Direction.bottomRight,
			color = "green",
			icon = ICON,
			text = "Coins I",
			price = { quantity = 500, currencyIcon = COIN_ICON },
		}, root)

		coins:setNotificationCount(3)

	Colours live in NodeConstructor.Colors. Pick one through the config's `color`
	field, or swap it at any time with node:setColor("purple").
--]]

local TweenService = game:GetService("TweenService")

export type NodeId = string

export type Price = {
	quantity: number,
	currencyIcon: string,
}

--[[
	Everything a node needs to build itself. `parentNodeId`, `showRootId` and
	`inheritVisibility` are never read by the node — they are here so a whole tree
	can be described in one config table, and are handed back by node:getConfig()
	for whoever manages that tree.
--]]
export type Config = {
	parentNodeId: NodeId?,
	showRootId: NodeId?,
	direction: Vector2?,
	backgroundIcon: string?,
	icon: string,
	text: string,
	price: Price?,
	headerText: string?,
	inheritVisibility: boolean?,
	-- Name of a colour in NodeConstructor.Colors. Defaults to "default".
	color: string?,
}

export type ConfigList = { [NodeId]: Config }

type PressedCallback = () -> ()

local ASSETS = {
	nodeIcon = "rbxassetid://100568518943004",
	background = "rbxassetid://98226451648717",
	backgroundBlue = "rbxassetid://128421674643187",
	backgroundPurple = "rbxassetid://84116313048597",
	backgroundGlow = "rbxassetid://80865197080866",
	highlightGlow = "rbxassetid://112800630292271",
	headerBackground = "rbxassetid://74061183052681",
	alertBackground = "rbxassetid://120266911736999",
}

local BUTTON_FONT = Font.new("rbxassetid://16658221428")
local PRIMARY_FONT = Font.new("rbxassetid://11702779409", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local HEADER_FONT = Font.new("rbxassetid://11702779409", Enum.FontWeight.Bold, Enum.FontStyle.Italic)

local NODE_SIZE = UDim2.fromScale(0.15, 0.15)
local HALF_NODE_SIZE = UDim2.fromScale(NODE_SIZE.X.Scale / 2, NODE_SIZE.Y.Scale / 2)
local HOVERED_SIZE = UDim2.fromScale(NODE_SIZE.X.Scale * 1.15, NODE_SIZE.Y.Scale * 1.15)
local PRESSED_SIZE = UDim2.fromScale(NODE_SIZE.X.Scale * 0.85, NODE_SIZE.Y.Scale * 0.85)
local HEADER_SIZE = UDim2.fromScale(0.45, 0.25)
local ALERT_SIZE = UDim2.fromScale(0.3, 0.3)
local STROKE_THICKNESS = 0.075

local GLOW_TRANSPARENCY = 0.35
local HIGHLIGHT_TRANSPARENCY = 0.4
local MAX_NOTIFICATION_COUNT = 9

local NUMBER_SYMBOLS = { "K", "M", "B", "T", "Q" }

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new()

export type Color = {
	-- Background art. It is tinted by `backgroundTint`, so the neutral artwork
	-- can take any hue without needing its own asset.
	backgroundImage: string,
	backgroundTint: Color3,
	glow: Color3,
	icon: Color3,
	text: Color3,
	stroke: Color3,
}

local Colors: { [string]: Color } = {
	default = {
		backgroundImage = ASSETS.background,
		backgroundTint = WHITE,
		glow = BLACK,
		icon = WHITE,
		text = WHITE,
		stroke = BLACK,
	},
	green = {
		backgroundImage = ASSETS.background,
		backgroundTint = Color3.fromRGB(126, 217, 87),
		glow = Color3.fromRGB(63, 191, 96),
		icon = WHITE,
		text = WHITE,
		stroke = Color3.fromRGB(21, 61, 30),
	},
	blue = {
		backgroundImage = ASSETS.backgroundBlue,
		backgroundTint = WHITE,
		glow = Color3.fromRGB(56, 148, 255),
		icon = WHITE,
		text = WHITE,
		stroke = Color3.fromRGB(15, 40, 82),
	},
	purple = {
		backgroundImage = ASSETS.backgroundPurple,
		backgroundTint = WHITE,
		glow = Color3.fromRGB(152, 76, 255),
		icon = WHITE,
		text = WHITE,
		stroke = Color3.fromRGB(44, 16, 82),
	},
	gold = {
		backgroundImage = ASSETS.background,
		backgroundTint = Color3.fromRGB(255, 199, 61),
		glow = Color3.fromRGB(255, 162, 22),
		icon = WHITE,
		text = WHITE,
		stroke = Color3.fromRGB(84, 55, 5),
	},
	red = {
		backgroundImage = ASSETS.background,
		backgroundTint = Color3.fromRGB(255, 104, 104),
		glow = Color3.fromRGB(214, 44, 44),
		icon = WHITE,
		text = WHITE,
		stroke = Color3.fromRGB(74, 14, 14),
	},
	locked = {
		backgroundImage = ASSETS.background,
		backgroundTint = Color3.fromRGB(105, 105, 115),
		glow = BLACK,
		icon = Color3.fromRGB(170, 170, 180),
		text = Color3.fromRGB(200, 200, 205),
		stroke = BLACK,
	},
}

type Instances = {
	node: TextButton,
	icon: ImageLabel,
	primaryText: TextLabel,
	primaryTextStroke: UIStroke,
	price: Frame,
	priceText: TextLabel,
	priceTextStroke: UIStroke,
	currencyIcon: ImageLabel,
	backgroundIcon: ImageLabel,
	backgroundGlow: ImageLabel,
	header: Frame,
	headerText: TextLabel,
	alert: Frame,
	alertText: TextLabel,
	highlightGlow: ImageLabel,
}

local function playTween(
	object: Instance,
	properties: { [string]: any },
	time: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
): Tween
	local tweenInfo = TweenInfo.new(
		time,
		style or Enum.EasingStyle.Quint,
		direction or Enum.EasingDirection.Out,
		0,
		false,
		delay or 0
	)

	local tween = TweenService:Create(object, tweenInfo, properties)
	tween:Play()

	return tween
end

--- Shortens a price into something that fits on a node: 100000 -> "100K".
local function formatLargeNumber(value: number): string
	local symbol = ""
	local shiftedValue = value

	for index in NUMBER_SYMBOLS do
		if shiftedValue < 1000 then
			break
		end
		symbol = NUMBER_SYMBOLS[index]
		shiftedValue /= 1000
	end

	if shiftedValue < 10 then
		shiftedValue = math.floor(shiftedValue * 10) / 10
	else
		shiftedValue = math.floor(shiftedValue)
	end

	return `{shiftedValue}{symbol}`
end

--[[
	Creates an instance with the given properties already applied. Returns `any`
	so the call site can name the class it expects.
--]]
local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className :: any)

	for propertyName, value in properties do
		(instance :: any)[propertyName] = value
	end

	instance.Parent = parent

	return instance
end

--[[
	Builds one node's instance tree and hands back every instance the class ever
	touches, so nothing has to be looked up by name again.
--]]
local function buildNodeInstance(): Instances
	local node: TextButton = create("TextButton", {
		Name = "Node",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		FontFace = BUTTON_FONT,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = NODE_SIZE,
		Text = "",
		TextColor3 = BLACK,
		TextSize = 14,
		Visible = false,
	})

	local background: Frame = create("Frame", {
		Name = "Background",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, node)

	local backgroundIcon: ImageLabel = create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ASSETS.background,
		Position = UDim2.fromScale(0.5, 0.5),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1.15, 1.15),
		ZIndex = 2,
	}, background)

	local backgroundGlow: ImageLabel = create("ImageLabel", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ASSETS.backgroundGlow,
		ImageColor3 = BLACK,
		ImageTransparency = GLOW_TRANSPARENCY,
		Position = UDim2.fromScale(0.5, 0.5),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1.55, 1.55),
	}, background)

	local icon: ImageLabel = create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ASSETS.nodeIcon,
		Position = UDim2.fromScale(0.5, 0.5),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.6, 0.6),
		ZIndex = 2,
	}, node)

	local primaryText: TextLabel = create("TextLabel", {
		Name = "PrimaryText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = PRIMARY_FONT,
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.fromScale(1.5, 0.225),
		Text = "",
		TextColor3 = WHITE,
		TextScaled = true,
		ZIndex = 3,
	}, node)

	local primaryTextStroke: UIStroke = create("UIStroke", {
		Name = "UIStroke",
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
		Thickness = STROKE_THICKNESS,
	}, primaryText)

	local price: Frame = create("Frame", {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.85),
		Size = UDim2.fromScale(1.5, 0.225),
		Visible = false,
		ZIndex = 3,
	}, node)

	create("UIListLayout", {
		Name = "UIListLayout",
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.035, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, price)

	local currencyIcon: ImageLabel = create("ImageLabel", {
		Name = "CurrencyIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
	}, price)

	create("UIAspectRatioConstraint", { Name = "UIAspectRatioConstraint" }, currencyIcon)

	local priceText: TextLabel = create("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = PRIMARY_FONT,
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		Text = "",
		TextColor3 = WHITE,
		TextScaled = true,
	}, price)

	local priceTextStroke: UIStroke = create("UIStroke", {
		Name = "UIStroke",
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
		Thickness = STROKE_THICKNESS,
	}, priceText)

	-- Notifications: the "NEW!" ribbon and the counter badge. Both start at zero
	-- size so that showing them pops instead of appearing instantly.
	local header: Frame = create("Frame", {
		Name = "HeaderText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.2, 0.1),
		Rotation = -10,
		Size = UDim2.new(),
		Visible = false,
		ZIndex = 5,
	}, node)

	local headerText: TextLabel = create("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = HEADER_FONT,
		Position = UDim2.fromScale(0.6, 0.525),
		Rotation = -5,
		Size = UDim2.fromScale(0.85, 0.85),
		Text = "NEW!",
		TextColor3 = WHITE,
		TextScaled = true,
		ZIndex = 2,
	}, header)

	create("UIStroke", {
		Name = "UIStroke",
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
		Thickness = STROKE_THICKNESS,
	}, headerText)

	create("ImageLabel", {
		Name = "Background",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ASSETS.headerBackground,
		Position = UDim2.fromScale(0.5, 0.5),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1.5, 1.5),
	}, header)

	local alert: Frame = create("Frame", {
		Name = "Alert",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.8, 0.1),
		Size = UDim2.new(),
		Visible = false,
		ZIndex = 5,
	}, node)

	local alertText: TextLabel = create("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = PRIMARY_FONT,
		Position = UDim2.fromScale(0.5, 0.525),
		Size = UDim2.fromScale(0.75, 0.75),
		Text = "",
		TextColor3 = WHITE,
		TextScaled = true,
		ZIndex = 2,
	}, alert)

	create("UIStroke", {
		Name = "UIStroke",
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
		Thickness = STROKE_THICKNESS,
	}, alertText)

	create("ImageLabel", {
		Name = "Background",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ASSETS.alertBackground,
		Position = UDim2.fromScale(0.5, 0.5),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1.5, 1.5),
	}, alert)

	local highlightGlow: ImageLabel = create("ImageLabel", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ASSETS.highlightGlow,
		ImageColor3 = BLACK,
		ImageTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1.5, 1.5),
		Visible = false,
	}, node)

	create("UIAspectRatioConstraint", { Name = "UIAspectRatioConstraint" }, highlightGlow)

	return {
		node = node,
		icon = icon,
		primaryText = primaryText,
		primaryTextStroke = primaryTextStroke,
		price = price,
		priceText = priceText,
		priceTextStroke = priceTextStroke,
		currencyIcon = currencyIcon,
		backgroundIcon = backgroundIcon,
		backgroundGlow = backgroundGlow,
		header = header,
		headerText = headerText,
		alert = alert,
		alertText = alertText,
		highlightGlow = highlightGlow,
	}
end

local NodeConstructor = {}
NodeConstructor.__index = NodeConstructor

NodeConstructor.Colors = Colors

NodeConstructor.Direction = {
	bottom = Vector2.new(0, 2),
	top = Vector2.new(0, -2),
	bottomLeft = Vector2.new(-1, 1),
	bottomRight = Vector2.new(1, 1),
	topLeft = Vector2.new(-1, -1),
	topRight = Vector2.new(1, -1),
}

export type NodeData = {
	_parentNode: Node?,
	_childNodes: { Node },
	_instances: Instances,
	_config: Config,
	_color: Color,
	_colorName: string,
	_backgroundIconOverride: string?,
	_locked: boolean,
	_visible: boolean,
	_alertVisible: boolean,
	_highlighted: boolean,
	_hovering: boolean,
	_pressing: boolean,
	_connections: { RBXScriptConnection },
	_pressedCallback: PressedCallback?,
	_pressedConnection: RBXScriptConnection?,
}

export type Node = typeof(setmetatable({} :: NodeData, NodeConstructor))

function NodeConstructor.new(config: Config, parentNode: Node?): Node
	local nodeData: NodeData = {
		_parentNode = parentNode,
		_childNodes = {},
		_instances = buildNodeInstance(),
		_config = config,
		_color = Colors.default,
		_colorName = "default",
		_locked = false,
		_visible = false,
		_alertVisible = false,
		_highlighted = false,
		_hovering = false,
		_pressing = false,
		_connections = {},
	}

	local self = setmetatable(nodeData, NodeConstructor)

	self._pressedConnection = self._instances.node.Activated:Connect(function()
		if self._pressedCallback then
			self._pressedCallback()
		end
	end)

	self:setColor(config.color or "default")
	if config.backgroundIcon then
		self:setBackgroundIcon(config.backgroundIcon)
	end
	self:setIcon(config.icon)
	self:setPrimaryText(config.text)
	self:setPrice(config.price)
	self:setHeaderText(config.headerText)
	self:setDirection(config.direction or Vector2.zero)

	if parentNode then
		table.insert(parentNode._childNodes, self)
	end

	-- Nodes are built hidden. Whoever owns the tree decides when they pop in.
	self._instances.node.Size = UDim2.new()

	return self
end

function NodeConstructor.getInstance(self: Node): TextButton
	return self._instances.node
end

function NodeConstructor.getConfig(self: Node): Config
	return self._config
end

function NodeConstructor.setParent(self: Node, parent: GuiBase2d)
	self._instances.node.Parent = parent
end

--[[
	Contents
--]]

function NodeConstructor.setIcon(self: Node, icon: string)
	self._instances.icon.Image = icon
end

function NodeConstructor.setPrimaryText(self: Node, text: string)
	self._instances.primaryText.Text = text
end

function NodeConstructor.setPriceText(self: Node, text: string)
	self._instances.priceText.Text = text
end

function NodeConstructor.setPriceCurrencyIcon(self: Node, icon: string)
	self._instances.currencyIcon.Image = icon
end

--- Passing nil hides the price row entirely.
function NodeConstructor.setPrice(self: Node, price: Price?)
	if not price then
		self._instances.price.Visible = false
		self:setPriceText("")
		self:setPriceCurrencyIcon("")
		return
	end

	self:setPriceText(formatLargeNumber(price.quantity))
	self:setPriceCurrencyIcon(price.currencyIcon)
	self._instances.price.Visible = true
end

--[[
	Colour
--]]

function NodeConstructor._applyColor(self: Node, color: Color)
	local instances = self._instances

	-- A config supplied background icon always wins over the palette's, so a
	-- one-off node can keep its own artwork while still being recoloured.
	instances.backgroundIcon.Image = self._backgroundIconOverride or color.backgroundImage
	instances.backgroundIcon.ImageColor3 = color.backgroundTint
	instances.backgroundGlow.ImageColor3 = color.glow
	instances.highlightGlow.ImageColor3 = color.glow
	instances.icon.ImageColor3 = color.icon
	instances.primaryText.TextColor3 = color.text
	instances.priceText.TextColor3 = color.text
	instances.primaryTextStroke.Color = color.stroke
	instances.priceTextStroke.Color = color.stroke

	-- Notifications deliberately keep their own colours so they read the same on
	-- every node.
end

--- Accepts a name from NodeConstructor.Colors, or a palette of your own.
function NodeConstructor.setColor(self: Node, color: string | Color)
	local palette: Color
	local colorName = "custom"

	if typeof(color) == "string" then
		local namedColor = Colors[color]
		assert(namedColor, `"{color}" is not a colour in NodeConstructor.Colors`)
		palette = namedColor
		colorName = color
	else
		palette = color
	end

	self._color = palette
	self._colorName = colorName

	if not self._locked then
		self:_applyColor(palette)
	end
end

function NodeConstructor.getColor(self: Node): Color
	return self._color
end

function NodeConstructor.getColorName(self: Node): string
	return self._colorName
end

--- Greys the node out without forgetting the colour it goes back to.
function NodeConstructor.setIsLocked(self: Node, isLocked: boolean)
	if self._locked == isLocked then
		return
	end

	self._locked = isLocked
	self:_applyColor(if isLocked then Colors.locked else self._color)
end

function NodeConstructor.isLocked(self: Node): boolean
	return self._locked
end

function NodeConstructor.setBackgroundIcon(self: Node, icon: string?)
	self._backgroundIconOverride = icon
	self:_applyColor(if self._locked then Colors.locked else self._color)
end

--- Fades the outer glow in, tinted by the node's colour. Good for "affordable".
function NodeConstructor.setIsHighlighted(self: Node, isHighlighted: boolean)
	if self._highlighted == isHighlighted then
		return
	end

	self._highlighted = isHighlighted

	local highlightGlow = self._instances.highlightGlow
	if isHighlighted then
		highlightGlow.Visible = true
		playTween(highlightGlow, { ImageTransparency = HIGHLIGHT_TRANSPARENCY }, 0.25, Enum.EasingStyle.Quad)
		return
	end

	local fadeTween = playTween(highlightGlow, { ImageTransparency = 1 }, 0.25, Enum.EasingStyle.Quad)
	fadeTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and not self._highlighted then
			highlightGlow.Visible = false
		end
	end)
end

function NodeConstructor.isHighlighted(self: Node): boolean
	return self._highlighted
end

--[[
	Notifications
--]]

function NodeConstructor.setHeaderTextIsVisible(self: Node, isVisible: boolean)
	local header = self._instances.header

	if isVisible then
		header.Visible = true
		playTween(header, { Size = HEADER_SIZE }, 0.3, Enum.EasingStyle.Back)
		return
	end

	local hideTween = playTween(header, { Size = UDim2.new() }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	hideTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed then
			header.Visible = false
		end
	end)
end

--- The ribbon above the node ("NEW!"). Passing nil takes it away.
function NodeConstructor.setHeaderText(self: Node, text: string?)
	if not text then
		self:setHeaderTextIsVisible(false)
		return
	end

	self._instances.headerText.Text = text
	self:setHeaderTextIsVisible(true)
end

function NodeConstructor.setAlertText(self: Node, text: string)
	self._instances.alertText.Text = text
end

function NodeConstructor.setIsAlertVisible(self: Node, isVisible: boolean)
	if self._alertVisible == isVisible then
		return
	end

	self._alertVisible = isVisible

	local alert = self._instances.alert
	if isVisible then
		alert.Visible = true
		playTween(alert, { Size = ALERT_SIZE }, 0.3, Enum.EasingStyle.Back)
		return
	end

	local hideTween = playTween(alert, { Size = UDim2.new() }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	hideTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		-- Guarded, in case the badge came back while it was shrinking.
		if playbackState == Enum.PlaybackState.Completed and not self._alertVisible then
			alert.Visible = false
		end
	end)
end

--- The badge on the corner of the node. Passing nil clears it.
function NodeConstructor.setNotification(self: Node, text: string?)
	if not text then
		self:setIsAlertVisible(false)
		return
	end

	self:setAlertText(text)
	self:setIsAlertVisible(true)
end

--- Counts above MAX_NOTIFICATION_COUNT show as "9+", zero clears the badge.
function NodeConstructor.setNotificationCount(self: Node, count: number)
	if count <= 0 then
		self:setNotification(nil)
	elseif count > MAX_NOTIFICATION_COUNT then
		self:setNotification(`{MAX_NOTIFICATION_COUNT}+`)
	else
		self:setNotification(tostring(count))
	end
end

function NodeConstructor.isNotifying(self: Node): boolean
	return self._alertVisible
end

--[[
	Placement
--]]

function NodeConstructor.getPosition(self: Node): UDim2
	return self._instances.node.Position
end

function NodeConstructor.setPosition(self: Node, position: UDim2)
	self._instances.node.Position = position
end

--- Where a child sitting in `direction` from this node belongs.
function NodeConstructor.getChildPosition(self: Node, direction: Vector2): UDim2
	local offset =
		UDim2.fromScale(HALF_NODE_SIZE.X.Scale * math.sqrt(3) * direction.X, HALF_NODE_SIZE.Y.Scale * direction.Y)

	return self:getPosition() + offset
end

function NodeConstructor.setDirection(self: Node, direction: Vector2)
	local parentNode = self._parentNode
	if not parentNode then
		return
	end

	self:setPosition(parentNode:getChildPosition(direction))
end

function NodeConstructor.getParentNode(self: Node): Node?
	return self._parentNode
end

function NodeConstructor.getChildNodes(self: Node): { Node }
	return self._childNodes
end

--- Runs the callback on this node and every node underneath it.
function NodeConstructor.eachNode(self: Node, callback: (Node) -> ())
	callback(self)

	for _, childNode in self._childNodes do
		childNode:eachNode(callback)
	end
end

function NodeConstructor.getDepth(self: Node): number
	local depth = 0
	local currentNode = self

	while currentNode._parentNode do
		depth += 1
		currentNode = currentNode._parentNode
	end

	return depth
end

--[[
	Input
--]]

function NodeConstructor._setHovered(self: Node, isHovered: boolean)
	if self._hovering == isHovered then
		return
	end

	self._hovering = isHovered

	local node = self._instances.node
	if isHovered then
		-- Hovering a node that is still popping in reads better with a slower,
		-- springier tween than the usual snap.
		local time = 0.1
		local style = Enum.EasingStyle.Quad
		if node.Size.X.Scale < NODE_SIZE.X.Scale then
			time = 0.4
			style = Enum.EasingStyle.Back
		end

		playTween(node, { Size = HOVERED_SIZE }, time, style)
	elseif not self._pressing then
		playTween(node, { Size = NODE_SIZE }, 0.25, Enum.EasingStyle.Sine)
	end
end

function NodeConstructor._setPressed(self: Node, isPressed: boolean)
	if self._pressing == isPressed then
		return
	end

	self._pressing = isPressed

	local node = self._instances.node
	if isPressed then
		playTween(node, { Size = PRESSED_SIZE }, 0.1, Enum.EasingStyle.Exponential)
	else
		playTween(node, { Size = if self._hovering then HOVERED_SIZE else NODE_SIZE }, 0.25, Enum.EasingStyle.Sine)
	end
end

function NodeConstructor._disableInput(self: Node)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

function NodeConstructor._enableInput(self: Node)
	self:_disableInput()

	local node = self._instances.node

	table.insert(
		self._connections,
		node.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self:_setHovered(true)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:_setPressed(true)
			elseif input.UserInputType == Enum.UserInputType.Touch then
				self:_setHovered(true)
				self:_setPressed(true)
			end
		end)
	)

	table.insert(
		self._connections,
		node.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self:_setHovered(false)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:_setPressed(false)
			elseif input.UserInputType == Enum.UserInputType.Touch then
				self:_setHovered(false)
				self:_setPressed(false)
			end
		end)
	)
end

--- Replaces the previous callback rather than stacking another connection.
function NodeConstructor.setPressedCallback(self: Node, callback: PressedCallback?)
	self._pressedCallback = callback
end

--[[
	Visibility
--]]

function NodeConstructor.isVisible(self: Node): boolean
	return self._visible
end

--- `optionalDelay` staggers the pop, which is how a branch opens outwards.
function NodeConstructor.setIsVisible(self: Node, isVisible: boolean, optionalDelay: number?)
	local delay = optionalDelay or 0

	self._visible = isVisible

	local node = self._instances.node
	if isVisible then
		self:_enableInput()

		if delay > 0 then
			node.Size = UDim2.new()
		end
		playTween(node, { Size = NODE_SIZE }, 0.4, Enum.EasingStyle.Back, nil, delay)

		node.Visible = true
		return
	end

	self:_disableInput()
	self:_setPressed(false)
	self:_setHovered(false)

	local hideTween = playTween(node, { Size = UDim2.new() }, 0.2, Enum.EasingStyle.Quint)
	hideTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and not self._visible then
			node.Visible = false
		end
	end)
end

function NodeConstructor.destroy(self: Node)
	self:_disableInput()

	if self._pressedConnection then
		self._pressedConnection:Disconnect()
		self._pressedConnection = nil
	end

	for _, childNode in table.clone(self._childNodes) do
		childNode:destroy()
	end
	table.clear(self._childNodes)

	local parentNode = self._parentNode
	if parentNode then
		local index = table.find(parentNode._childNodes, self)
		if index then
			table.remove(parentNode._childNodes, index)
		end
		self._parentNode = nil
	end

	self._instances.node:Destroy()
end

return NodeConstructor
