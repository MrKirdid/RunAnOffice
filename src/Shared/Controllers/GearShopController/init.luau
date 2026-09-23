local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local GearConfigs = require(Shared.Configs.Gears)
local GearController = require(Shared.Controllers.GearController)
local PlayerData = require(Shared.PlayerData).client
local UIController = require(Shared.Controllers.UIController)
local UIFx = require(Shared.Utilities.UIFx)

--> The gear shop on the screen: GearsUI, built in the place, with one Slot row cloned per gear off
--> the template row it ships with. It opens on its own when the player walks up to the shop model
--> on any plot and shuts again when they walk off, and goes through UIController like every other
--> screen so it gets the blur, the pop and the X for free. Buying and equipping go through
--> GearController, which asks the server.

local ScreenName = "GearShop"
local GuiName = "GearsUI"

--> where the rows live, the X sits and the title is, from the ScreenGui down
local ListPath = "MainBackground.MainBackground.ScrollingFrame"
local ClosePath = "MainBackground.MainBackground.CloseButton"
local TitlePath = "MainBackground.MainBackground.Level.TitleName"
local SlotName = "Slot"
local TitleText = "Gear Shop"

--> where the shop stands on a plot, and how close the player has to be to it
local ContainerName = "PlotContainer"
local ShopPath = { "Fcts", "Shop" }
local OpenRange = 14

--> how often the distance is looked at
local Poll = 0.2

--> how the tool sits in the row's icon: how far back the camera is for its longest side, how far
--> the tool itself is rolled off upright before it is spun so the spin wobbles and shows its
--> sides, how fast it turns while the shop is up, and how far and how fast it bobs. Each tool
--> gets its own draw around these, so the rows are not all in step.
local Framing = 1.15
local Tilt = math.rad(30)
local TurnSpeed = 0.8
local BobHeight = 0.08
local BobSpeed = 2.2
local Vary = 0.35

local Draw = Random.new()

type Motion = {
	Spin: number,
	Bob: number,
	Lean: number,
	Phase: number,
	BobPhase: number,
}

--> the dark tile behind the tool, so a bat is not lost against the row
local IconBackdrop = Color3.new(0, 0, 0)
local IconBackdropTransparency = 0.55

--> how far the description stops short of the button, as a share of the row
local LineGap = 0.02

--> What the button says and wears in each state. Not bought yet is a dimmed row with the price
--> on the button as drawn; bought reads Equip on the button as drawn; equipped is tinted so it
--> reads apart from the other two.
local EquipText = "Equip"
local EquippedText = "Equipped"
local EquippedTint = Color3.fromRGB(110, 170, 255)
local UnownedRowTransparency = 0.5

--> a little room under the last row, in pixels, so it is not flush with the bottom
local ListTail = 24

local Assets = ReplicatedStorage:WaitForChild("Assets")

type Row = {
	Frame: Frame,
	Button: TextLabel,

	--> the button art and the row as authored, so a state can be undone
	Art: GuiButton,
	Tint: Color3,
	RowTransparency: number,
}

local GearShopController = {
	Name = "GearShopController",

	--> the rows of whichever copy of the screen is up, by gear, and its title
	Rows = {} :: { [string]: Row },
	Title = nil :: TextLabel?,

	--> the models turning in the icons, spun together off one clock
	Models = {} :: { [string]: Model },

	--> each one's own speeds and offsets
	Motions = {} :: { [string]: Motion },

	--> whether the shop was opened by walking up, so walking off is what closes it
	Near = false,
}

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

local function Walk(Root: Instance, Path: { string }): Instance?
	local Current: Instance? = Root

	for _, Step in Path do
		if not Current then
			return nil
		end

		Current = (Current :: Instance):FindFirstChild(Step)
	end

	return Current
end

--> The row carries two labels both called TitleName: the one nearer the top is the name, the
--> other the line under it.
local function FindLabels(Row: Frame): (TextLabel?, TextLabel?)
	local Labels = {}

	for _, Child in Row:GetChildren() do
		if Child:IsA("TextLabel") then
			table.insert(Labels, Child)
		end
	end

	table.sort(Labels, function(Left: TextLabel, Right: TextLabel): boolean
		return Left.Position.Y.Scale < Right.Position.Y.Scale
	end)

	return Labels[1], Labels[2]
end

--> The Tool's look, out of the place, or a block in the gear's colour when there is none yet.
local function BuildModel(Key: string): Model
	local Config = GearConfigs.List[Key]
	local Folder = Assets:FindFirstChild(GearConfigs.Folder)
	local Tool = if Config.Plain then nil else Folder and Folder:FindFirstChild(Key)
	local Model = Instance.new("Model")
	Model.Name = Key

	if Tool then
		for _, Child in Tool:GetChildren() do
			if Child:IsA("BasePart") or Child:IsA("Constraint") or Child:IsA("WeldConstraint") then
				Child:Clone().Parent = Model
			end
		end
	end

	if not Model:FindFirstChildWhichIsA("BasePart") then
		local Block = Instance.new("Part")
		Block.Name = "Handle"
		Block.Size = Config.Placeholder.Size
		Block.Color = Config.Placeholder.Color
		Block.Shape = Config.Placeholder.Shape or Enum.PartType.Block
		Block.Material = Config.Placeholder.Material or Enum.Material.SmoothPlastic
		Block.Parent = Model
	end

	if Config.Scale then
		Model.PrimaryPart = Model:FindFirstChild("Handle") :: BasePart?
		Model:ScaleTo(Config.Scale)
	end

	for _, Part in Model:GetDescendants() do
		if Part:IsA("BasePart") then
			Part.Anchored = true
		end
	end

	return Model
end

--> The tool turning where the row's icon is drawn: a viewport laid over the icon, the icon's own
--> image put away under it and its background darkened. The icon's art is not touched, so taking
--> the viewport out brings it back.
function GearShopController:_FillIcon(Key: string, Icon: ImageLabel)
	local Viewport = Instance.new("ViewportFrame")
	Viewport.Name = "Viewport"
	Viewport.BackgroundTransparency = 1
	Viewport.Size = UDim2.fromScale(1, 1)
	Viewport.Ambient = Color3.fromRGB(180, 180, 200)
	Viewport.LightColor = Color3.new(1, 1, 1)
	Viewport.LightDirection = Vector3.new(-1, -1, -1)

	local Camera = Instance.new("Camera")
	Camera.Parent = Viewport
	Viewport.CurrentCamera = Camera

	local World = Instance.new("WorldModel")
	World.Parent = Viewport

	local Model = BuildModel(Key)
	Model:PivotTo(CFrame.new())
	Model.Parent = World

	--> backed off by the longest side, so a bat and a bomb both fill the icon about the same
	local _, Size = Model:GetBoundingBox()
	local Distance = math.max(Size.X, Size.Y, Size.Z) * Framing

	Camera.CFrame = CFrame.lookAt(Vector3.new(0, Distance * 0.25, Distance), Vector3.zero)

	Icon.ImageTransparency = 1
	Icon.BackgroundColor3 = IconBackdrop
	Icon.BackgroundTransparency = IconBackdropTransparency
	Viewport.Parent = Icon

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0.15, 0)
	Corner.Parent = Icon

	self.Models[Key] = Model
	self.Motions[Key] = {
		Spin = TurnSpeed * (1 + Draw:NextNumber(-Vary, Vary)),
		Bob = BobSpeed * (1 + Draw:NextNumber(-Vary, Vary)),
		Lean = Tilt * (1 + Draw:NextNumber(-Vary, Vary)),
		Phase = Draw:NextNumber(0, math.pi * 2),
		BobPhase = Draw:NextNumber(0, math.pi * 2),
	}
end

--> What each row says and wears right now, off the save, and the slot count in the title.
function GearShopController:_Refresh()
	for Key, Row in self.Rows do
		local Config = GearConfigs.List[Key]
		local Equipped = GearController:IsEquipped(Key)
		local Owned = GearController:IsOwned(Key)

		if Equipped then
			Row.Button.Text = EquippedText
		elseif Owned then
			Row.Button.Text = EquipText
		else
			Row.Button.Text = Format.Cash(Config.Price)
		end

		if Row.Art:IsA("ImageButton") then
			Row.Art.ImageColor3 = if Equipped then EquippedTint else Row.Tint
		end

		Row.Frame.BackgroundTransparency = if Owned then Row.RowTransparency else UnownedRowTransparency
	end

	local Title = self.Title

	if Title then
		local Count, Slots = GearController:GetSlots()

		Title.Text = `{TitleText}  {Count}/{Slots}`
	end
end

--> One press does whichever the row is showing: buys, equips, or takes an equipped gear out.
function GearShopController:_Press(Key: string)
	if GearController:IsEquipped(Key) then
		GearController:Unequip(Key)
		return
	end

	if GearController:IsOwned(Key) then
		GearController:Equip(Key)
		return
	end

	GearController:Buy(Key)
end

--> The canvas is exactly as tall as the rows, measured, plus the list's own padding, which the
--> layout's measure leaves out, so the last one can always be reached. Set by hand off the
--> layout rather than left automatic: the rows are sized in scale, and an automatic canvas
--> measured against rows measured against it does not settle.
local function FitCanvas(List: ScrollingFrame, Layout: UIListLayout)
	local Padding = List:FindFirstChildWhichIsA("UIPadding")
	local Extra = 0

	if Padding then
		local Height = List.AbsoluteSize.Y

		Extra = Padding.PaddingTop.Scale * Height
			+ Padding.PaddingTop.Offset
			+ Padding.PaddingBottom.Scale * Height
			+ Padding.PaddingBottom.Offset
	end

	List.AutomaticCanvasSize = Enum.AutomaticSize.None
	List.CanvasSize = UDim2.fromOffset(0, Layout.AbsoluteContentSize.Y + Extra + ListTail)
end

--> Clones the template row once per gear, in shop order, and puts the template itself away.
function GearShopController:_Bind(Gui: ScreenGui)
	local List = Resolve(Gui, ListPath)
	local Template = List and List:FindFirstChild(SlotName)
	local Title = Resolve(Gui, TitlePath)

	if not List or not List:IsA("ScrollingFrame") or not Template or not Template:IsA("Frame") then
		warn(`[GearShop] {GuiName} has no {SlotName} row under {ListPath}`)
		return
	end

	table.clear(self.Rows)
	table.clear(self.Models)
	table.clear(self.Motions)

	self.Title = if Title and Title:IsA("TextLabel") then Title else nil

	Template.Visible = false

	--> the list ships sorted by name; the rows go in shop order
	local Layout = List:FindFirstChildWhichIsA("UIListLayout")

	if Layout then
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	for Order, Key in GearConfigs.Sorted() do
		local Config = GearConfigs.List[Key]
		local Row = Template:Clone()
		Row.Name = Key
		Row.LayoutOrder = Order
		Row.Visible = true

		local RowTitle, Line = FindLabels(Row)
		local Icon = Row:FindFirstChild("Icon")
		local Button = Row:FindFirstChildWhichIsA("GuiButton")
		local Price = Button and Button:FindFirstChildWhichIsA("TextLabel", true)

		if RowTitle then
			RowTitle.Text = Config.Name
		end

		--> the line stops before the button, or it runs on under it
		if Line and Button then
			Line.Text = Config.Description
			Line.Size = UDim2.fromScale(
				Button.Position.X.Scale - Button.Size.X.Scale * Button.AnchorPoint.X - Line.Position.X.Scale - LineGap,
				Line.Size.Y.Scale
			)
		elseif Line then
			Line.Text = Config.Description
		end

		if Icon and Icon:IsA("ImageLabel") then
			self:_FillIcon(Key, Icon)
		end

		Row.Parent = List

		if not Button or not Price then
			warn(`[GearShop] the {SlotName} row has no button with a label on it`)
			continue
		end

		UIFx.Press(Button)

		Button.Activated:Connect(function()
			self:_Press(Key)
		end)

		self.Rows[Key] = {
			Frame = Row,
			Button = Price,
			Art = Button,
			Tint = if Button:IsA("ImageButton") then Button.ImageColor3 else Color3.new(1, 1, 1),
			RowTransparency = Row.BackgroundTransparency,
		}
	end

	if Layout then
		FitCanvas(List, Layout)

		--> the rows are sized off the screen, so the canvas follows them through a resize
		Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			FitCanvas(List, Layout)
		end)
	end

	self:_Refresh()
end

--> The shop model nearest the character, on whichever plot, and how far it is.
local function NearestShop(): number
	local Character = Players.LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	local Container = workspace:FindFirstChild(ContainerName)

	if not Root or not Root:IsA("BasePart") or not Container then
		return math.huge
	end

	local Best = math.huge

	for _, Plot in Container:GetChildren() do
		local Shop = Walk(Plot, ShopPath)

		if not Shop or not Shop:IsA("PVInstance") then
			continue
		end

		local Distance = (Shop:GetPivot().Position - Root.Position).Magnitude

		if Distance < Best then
			Best = Distance
		end
	end

	return Best
end

function GearShopController:Init()
	UIController:Register(ScreenName, { Gui = GuiName, Close = ClosePath })

	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local Gui = PlayerGui:FindFirstChild(GuiName)

	if Gui and Gui:IsA("ScreenGui") then
		self:_Bind(Gui)
	end

	--> the screen resets on spawn, and the copy comes back with only the template row in it
	PlayerGui.ChildAdded:Connect(function(Child: Instance)
		if Child.Name == GuiName and Child:IsA("ScreenGui") then
			self:_Bind(Child)
		end
	end)

	--> the rows read the save: a purchase, an equip, or the cash for one changes what they say
	PlayerData.Changed(function()
		self:_Refresh()
	end)

	UIController.Opened:Connect(function(Name: string)
		if Name == ScreenName then
			self:_Refresh()
		end
	end)
end

function GearShopController:Start()
	--> walking up opens it, walking off shuts it; the X shuts it too, and then it stays shut until
	--> the player has walked off and come back
	task.spawn(function()
		while true do
			task.wait(Poll)

			local Close = NearestShop() <= OpenRange

			if Close and not self.Near then
				self.Near = true
				UIController:Open(ScreenName)
			elseif not Close and self.Near then
				self.Near = false
				UIController:Close(ScreenName, true)
			end
		end
	end)

	--> the tools turn and bob together, leaning towards the camera so the turn reads, only while
	--> the shop is up
	RunService.RenderStepped:Connect(function()
		if not UIController:IsOpen(ScreenName) then
			return
		end

		local Now = os.clock()
		local Lift = math.sin(Now * BobSpeed) * BobHeight
		--> the roll is inside the spin: the tool is tipped over on its own axis and that tipped tool
		--> is what turns, so the lean swings round with it rather than facing one way
		local Pose = CFrame.new(0, Lift, 0) * CFrame.Angles(0, Now * TurnSpeed, 0) * CFrame.Angles(0, 0, Tilt)

		for Key, Model in self.Models do
			local Config = GearConfigs.List[Key]

			Model:PivotTo(Pose * (Config.IconRotation or CFrame.identity))
		end
	end)
end

return GearShopController
