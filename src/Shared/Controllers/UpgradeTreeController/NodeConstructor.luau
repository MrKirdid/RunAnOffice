--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Fusion = require(Shared.Packages.Fusion)

export type NodeId = string

export type Price = {
	quantity: number,
	currencyIcon: string,
}

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

--> the display face the rest of the game is set in. the ids this used to carry were condensed
--> and appeared nowhere else, which is what made the tree read as foreign
local DISPLAY_FONT = "rbxassetid://11598289817"

local BUTTON_FONT = Font.new(DISPLAY_FONT, Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
local PRIMARY_FONT = Font.new(DISPLAY_FONT, Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
local HEADER_FONT = Font.new(DISPLAY_FONT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

local NODE_SIZE = UDim2.fromScale(0.09, 0.09)
local HALF_NODE_SIZE = UDim2.fromScale(NODE_SIZE.X.Scale / 2, NODE_SIZE.Y.Scale / 2)
local HOVERED_SIZE = UDim2.fromScale(NODE_SIZE.X.Scale * 1.15, NODE_SIZE.Y.Scale * 1.15)
local PRESSED_SIZE = UDim2.fromScale(NODE_SIZE.X.Scale * 0.85, NODE_SIZE.Y.Scale * 0.85)
--> the hex is the frame, so the icon sits in the upper half and the name and price stack under it,
--> all inside the silhouette. widths are what fits the hex at that height, not the node's box.
--> the label is deliberately small: the icon carries the node and the name only labels it
local ICON_CENTER = 0.37
local ICON_SIZE = 0.62
local LABEL_CENTER = 0.72
local LABEL_WIDTH = 0.92
local LABEL_HEIGHT = 0.16
local PRICE_CENTER = 0.88
local PRICE_WIDTH = 0.7
local PRICE_HEIGHT = 0.14

local HEADER_SIZE = UDim2.fromScale(0.45, 0.25)
local ALERT_SIZE = UDim2.fromScale(0.3, 0.3)
local STROKE_THICKNESS = 0.14

--> Driven fast and damped hard enough that the overshoot is one clear beat rather than a long
--> crawl back to size. A node that is still visibly moving after it has arrived reads as a stall.
local SIZE_SPEED = 32
local SIZE_DAMPING = 0.66
local ROTATION_SPEED = 28
local ROTATION_DAMPING = 0.5

--> the kick given to the size spring as a node lands, and the tilt it unwinds from
local SPAWN_PUNCH = 2.6
local SPAWN_TILT = -22

--> velocity put on the rotation spring when a press is refused. it wobbles in place and settles,
--> which reads as "no" without moving the node anywhere
local DENY_SHAKE = 350

local GLOW_TRANSPARENCY = 1

--> what marks the node you could buy right now. it was 1, which switched the glow off entirely and
--> left an affordable node looking the same as one you cannot pay for yet
local HIGHLIGHT_TRANSPARENCY = 0.4
local MAX_NOTIFICATION_COUNT = 9

local NUMBER_SYMBOLS = { "K", "M", "B", "T", "Q" }

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new()

export type Color = {
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
	--> the sheet named "blue" in ASSETS is the amber one, so blue is drawn off the plain sheet and
	--> gold off the amber sheet. named colours now render as their names
	blue = {
		backgroundImage = ASSETS.background,
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
		backgroundImage = ASSETS.backgroundBlue,
		backgroundTint = WHITE,
		glow = Color3.fromRGB(255, 162, 22),
		icon = WHITE,
		text = WHITE,
		stroke = Color3.fromRGB(84, 55, 5),
	},
	--> the plain background art is a dark blue base that turns almost black under a red tint, so red
	--> is mixed off the amber sheet instead
	red = {
		backgroundImage = ASSETS.backgroundBlue,
		backgroundTint = Color3.fromRGB(255, 58, 58),
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

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className :: any)

	for propertyName, value in properties do
		(instance :: any)[propertyName] = value
	end

	instance.Parent = parent

	return instance
end

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

	create("UIAspectRatioConstraint", {
		Name = "UIAspectRatioConstraint",
		AspectRatio = 1,
		DominantAxis = Enum.DominantAxis.Height,
	}, node)

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

	--> the glow sheets stay in the tree so the colour plumbing keeps working, but they are drawn at
	--> full transparency: the palettes read cleaner without a halo behind every hex
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
		Position = UDim2.fromScale(0.5, ICON_CENTER),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(ICON_SIZE, ICON_SIZE),
		ZIndex = 2,
	}, node)

	local primaryText: TextLabel = create("TextLabel", {
		Name = "PrimaryText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = PRIMARY_FONT,
		Position = UDim2.fromScale(0.5, LABEL_CENTER),
		Size = UDim2.fromScale(LABEL_WIDTH, LABEL_HEIGHT),
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
		Position = UDim2.fromScale(0.5, PRICE_CENTER),
		Size = UDim2.fromScale(PRICE_WIDTH, PRICE_HEIGHT),
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

NodeConstructor.NodeSize = NODE_SIZE

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
	_scope: any,
	_sizeGoal: any,
	_size: any,
	_rotationGoal: any,
	_rotation: any,
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
	local scope = Fusion.scoped(Fusion)
	local instances = buildNodeInstance()

	local sizeGoal = scope:Value(UDim2.new())
	local rotationGoal = scope:Value(0)

	local nodeData: NodeData = {
		_parentNode = parentNode,
		_childNodes = {},
		_instances = instances,
		_scope = scope,
		_sizeGoal = sizeGoal,
		_size = scope:Spring(sizeGoal, SIZE_SPEED, SIZE_DAMPING),
		_rotationGoal = rotationGoal,
		_rotation = scope:Spring(rotationGoal, ROTATION_SPEED, ROTATION_DAMPING),
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

	scope:Hydrate(instances.node)({
		Size = self._size,
		Rotation = self._rotation,
	})

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
	local currencyIcon = self._instances.currencyIcon

	currencyIcon.Image = icon

	--> Configs.Upgrades has no cash icon picked yet, and an empty one still claimed its slot in the
	--> list layout, leaving the amount sitting off to one side of the hex
	currencyIcon.Visible = icon ~= ""
end

function NodeConstructor.setPrice(self: Node, price: Price?)
	if not price then
		self._instances.price.Visible = false
		self:setPriceText("")
		self:setPriceCurrencyIcon("")
		return
	end

	self:setPriceText("$" .. formatLargeNumber(price.quantity))
	self:setPriceCurrencyIcon(price.currencyIcon)
	self._instances.price.Visible = true
end

function NodeConstructor._applyColor(self: Node, color: Color)
	local instances = self._instances

	instances.backgroundIcon.Image = self._backgroundIconOverride or color.backgroundImage
	instances.backgroundIcon.ImageColor3 = color.backgroundTint
	instances.backgroundGlow.ImageColor3 = color.glow
	instances.highlightGlow.ImageColor3 = color.glow
	instances.icon.ImageColor3 = color.icon
	instances.primaryText.TextColor3 = color.text
	instances.priceText.TextColor3 = color.text
	instances.primaryTextStroke.Color = color.stroke
	instances.priceTextStroke.Color = color.stroke
end

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

function NodeConstructor.setIsHighlighted(self: Node, isHighlighted: boolean)
	if self._highlighted == isHighlighted then
		return
	end

	self._highlighted = isHighlighted

	local highlightGlow = self._instances.highlightGlow
	if isHighlighted then
		highlightGlow.Visible = HIGHLIGHT_TRANSPARENCY < 1
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
		if playbackState == Enum.PlaybackState.Completed and not self._alertVisible then
			alert.Visible = false
		end
	end)
end

function NodeConstructor.setNotification(self: Node, text: string?)
	if not text then
		self:setIsAlertVisible(false)
		return
	end

	self:setAlertText(text)
	self:setIsAlertVisible(true)
end

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

function NodeConstructor.getPosition(self: Node): UDim2
	return self._instances.node.Position
end

function NodeConstructor.setPosition(self: Node, position: UDim2)
	self._instances.node.Position = position
end

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

function NodeConstructor._setHovered(self: Node, isHovered: boolean)
	if self._hovering == isHovered then
		return
	end

	self._hovering = isHovered

	if isHovered then
		self._sizeGoal:set(HOVERED_SIZE)
	elseif not self._pressing then
		self._sizeGoal:set(NODE_SIZE)
	end
end

function NodeConstructor._setPressed(self: Node, isPressed: boolean)
	if self._pressing == isPressed then
		return
	end

	self._pressing = isPressed

	if isPressed then
		self._sizeGoal:set(PRESSED_SIZE)
		return
	end

	self._sizeGoal:set(if self._hovering then HOVERED_SIZE else NODE_SIZE)

	--> a release pushes back out rather than easing, so a tap feels like it snaps
	self._size:addVelocity(UDim2.fromScale(SPAWN_PUNCH / 2, SPAWN_PUNCH / 2))
end

--> A kick on the size spring with the goal left alone, for a node that has just been bought. The
--> node is already where it belongs; only the speed it settles at changes.
function NodeConstructor.punch(self: Node, amount: number?)
	local scale = amount or SPAWN_PUNCH

	self._size:addVelocity(UDim2.fromScale(scale, scale))
end

--> The refusal: rotation rather than size, so nothing grows and nothing moves.
function NodeConstructor.nudge(self: Node, amount: number?)
	self._rotation:addVelocity(amount or DENY_SHAKE)
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

function NodeConstructor.setPressedCallback(self: Node, callback: PressedCallback?)
	self._pressedCallback = callback
end

function NodeConstructor.isVisible(self: Node): boolean
	return self._visible
end

function NodeConstructor.setIsVisible(self: Node, isVisible: boolean, optionalDelay: number?)
	local delay = optionalDelay or 0

	self._visible = isVisible

	local node = self._instances.node
	if isVisible then
		task.delay(delay, function()
			if not self._visible then
				return
			end

			self:_enableInput()

			node.Visible = true

			--> lands with a kick and unwinds the tilt, so nodes pop in rather than fade up
			self._sizeGoal:set(NODE_SIZE)
			self._size:addVelocity(UDim2.fromScale(SPAWN_PUNCH, SPAWN_PUNCH))
			self._rotation:setPosition(SPAWN_TILT)
		end)

		return
	end

	self:_disableInput()
	self:_setPressed(false)
	self:_setHovered(false)
	self._sizeGoal:set(UDim2.new())

	task.delay(0.35, function()
		if not self._visible then
			node.Visible = false
		end
	end)
end

function NodeConstructor.destroy(self: Node)
	self:_disableInput()
	Fusion.doCleanup(self._scope)

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
