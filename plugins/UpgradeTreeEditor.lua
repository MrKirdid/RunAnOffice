--> Edit-mode editor for Configs.Upgrades. Drag nodes around a snapping hex grid, hang children off
--> any of the eight sides, and set the label, description and price. Saving POSTs the rebuilt file
--> to tools/treewriter.py, which writes it to disk; Rojo then syncs it back in. Fields the editor
--> does not expose -- Icon, Header, IsAction -- are parsed and written back untouched.

assert(plugin, "UpgradeTreeEditor must be run as a Studio plugin")

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local WriterUrl = "http://127.0.0.1:8790"
local PendingKey = "PendingSave"
local ConfigPath = { "Shared", "Configs", "Upgrades" }

--> Left and Right are not hex neighbours: a hex has no side facing straight across, so the nearest
--> cell that way is two columns over and those two leave a gap. Column and Row place each button in
--> the 3x3 pad, middle left empty.
local Directions = {
	{ Name = "TopLeft", Label = "↖", Step = Vector2.new(-1, -1), Column = 1, Row = 1 },
	{ Name = "Top", Label = "↑", Step = Vector2.new(0, -2), Column = 2, Row = 1 },
	{ Name = "TopRight", Label = "↗", Step = Vector2.new(1, -1), Column = 3, Row = 1 },
	{ Name = "Left", Label = "←", Step = Vector2.new(-2, 0), Column = 1, Row = 2 },
	{ Name = "Right", Label = "→", Step = Vector2.new(2, 0), Column = 3, Row = 2 },
	{ Name = "BottomLeft", Label = "↙", Step = Vector2.new(-1, 1), Column = 1, Row = 3 },
	{ Name = "Bottom", Label = "↓", Step = Vector2.new(0, 2), Column = 2, Row = 3 },
	{ Name = "BottomRight", Label = "↘", Step = Vector2.new(1, 1), Column = 3, Row = 3 },
}

local StepByName, NameByStep = {}, {}

for _, Entry in Directions do
	StepByName[Entry.Name] = Entry.Step
	NameByStep[Entry.Step.X .. "," .. Entry.Step.Y] = Entry.Name
end

local Palette = { "default", "green", "blue", "purple", "gold", "red" }

local Swatch = {
	default = Color3.fromRGB(120, 126, 138),
	green = Color3.fromRGB(96, 186, 88),
	blue = Color3.fromRGB(64, 140, 236),
	purple = Color3.fromRGB(150, 92, 226),
	gold = Color3.fromRGB(226, 172, 60),
	red = Color3.fromRGB(212, 74, 66),
}

local BaseNodeSize = 76
local Padding = 60
local DragThreshold = 5
local MinZoom, MaxZoom = 0.4, 1.5

--> zoom rescales the whole grid, so the step between cells has to follow the node size
local Zoom = 1
local NodeSize = BaseNodeSize
local StepX = NodeSize * 0.866
local StepY = NodeSize * 0.5

local function SetZoom(Value: number)
	Zoom = math.clamp(Value, MinZoom, MaxZoom)
	NodeSize = BaseNodeSize * Zoom
	StepX = NodeSize * 0.866
	StepY = NodeSize * 0.5
end

local Dark = Color3.fromRGB(33, 35, 40)
local Panel = Color3.fromRGB(45, 48, 55)
local Field = Color3.fromRGB(28, 30, 34)
local Line = Color3.fromRGB(72, 76, 85)
local Accent = Color3.fromRGB(0, 145, 255)
local Danger = Color3.fromRGB(190, 60, 60)
local Ink = Color3.fromRGB(240, 242, 245)
local Muted = Color3.fromRGB(150, 156, 166)

type Node = {
	Parent: string?,
	Direction: string?,
	Text: string,
	Description: string?,
	Header: string?,
	Color: string?,
	Cost: number?,
	Icon: string?,
	IsAction: boolean?,
}

local Model: { [string]: Node } = {}
local CashIcon = ""
local Selected: string? = nil
local Origin = Vector2.zero
local Dragging: string? = nil
local DragValid = true
local DragCell = Vector2.zero
local PressedAt: Vector2? = nil
local PressedOn: string? = nil

local Status: TextLabel
local Refresh: () -> ()
local Rebuild: () -> ()
local BeginDrag: (string, Vector2) -> ()
local UpdateDrag: (Vector2) -> ()

local function Create(Class: string, Props: { [string]: any }, Parent: Instance?): any
	local Item = Instance.new(Class)

	for Key, Value in Props do
		Item[Key] = Value
	end

	if Parent then
		Item.Parent = Parent
	end

	return Item
end

local function Say(Message: string, IsBad: boolean?)
	Status.Text = Message
	Status.TextColor3 = if IsBad then Color3.fromRGB(255, 125, 125) else Muted
end

local function Count(): number
	local Total = 0

	for _ in Model do
		Total += 1
	end

	return Total
end

--> money reads better than a raw integer once costs run to millions
local function Pretty(Value: number?): string
	if not Value then
		return "-"
	end

	for _, Unit in { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if Value >= Unit[1] then
			local Scaled = Value / Unit[1]
			local Text = if Scaled % 1 == 0 then tostring(Scaled) else string.format("%.1f", Scaled)

			return Text .. Unit[2]
		end
	end

	return tostring(Value)
end

--> accepts 25000, 25_000 or 25k, because typing zeroes is how you end up with a node that costs ten
--> times what you meant
local function ParseCost(Text: string): number?
	local Clean = Text:lower():gsub("[%s_,]", "")
	local Number, Suffix = Clean:match("^(%d+%.?%d*)([kmb]?)$")

	if not Number then
		return nil
	end

	local Value = tonumber(Number)

	if not Value then
		return nil
	end

	local Scale = if Suffix == "k" then 1e3 elseif Suffix == "m" then 1e6 elseif Suffix == "b" then 1e9 else 1

	return math.floor(Value * Scale + 0.5)
end

local function GetConfigScript(): ModuleScript?
	local Current: Instance? = ReplicatedStorage

	for _, Name in ConfigPath do
		if not Current then
			return nil
		end

		Current = Current:FindFirstChild(Name)
	end

	return if Current and Current:IsA("ModuleScript") then Current else nil
end

--> the file is generated in a fixed shape, so matching entry blocks out of the source beats
--> requiring the module: require caches, and a stale tree is worse than no tree
local function Load(): boolean
	local Script = GetConfigScript()

	if not Script then
		Say("ReplicatedStorage.Shared.Configs.Upgrades not found", true)
		return false
	end

	local Source = Script.Source
	local Fresh: { [string]: Node } = {}
	local Total = 0

	for Name, Body in Source:gmatch("\n\t([%a][%w_]*) = {(.-)\n\t},") do
		local Cost = Body:match("Cost = ([%d_]+)")

		Fresh[Name] = {
			Parent = Body:match('Parent = "([%w_]+)"'),
			Direction = Body:match('Direction = "(%a+)"'),
			Text = Body:match('Text = "([^"]*)"') or Name,
			Description = Body:match('Description = "([^"]*)"'),
			Header = Body:match('Header = "([^"]*)"'),
			Color = Body:match('Color = "(%a+)"'),
			Icon = Body:match('Icon = "([^"]*)"'),
			Cost = if Cost then tonumber((Cost:gsub("_", ""))) else nil,
			IsAction = Body:find("IsAction = true") ~= nil,
		}
		Total += 1
	end

	if Total == 0 then
		Say("could not parse any nodes out of Upgrades.luau", true)
		return false
	end

	Model = Fresh
	CashIcon = Source:match('local CashIcon = "([^"]*)"') or ""
	Selected = nil
	Say("loaded " .. Total .. " nodes")

	return true
end

local function RootName(): string?
	for Name, Node in Model do
		if not Node.Parent then
			return Name
		end
	end

	return nil
end

local function CellOf(Name: string, Guard: { [string]: boolean }?): Vector2?
	local Node = Model[Name]

	if not Node then
		return nil
	end

	if not Node.Parent then
		return Vector2.zero
	end

	local Seen = Guard or {}

	if Seen[Name] then
		return nil
	end

	Seen[Name] = true

	local ParentCell = CellOf(Node.Parent, Seen)
	local Step = Node.Direction and StepByName[Node.Direction]

	if not ParentCell or not Step then
		return nil
	end

	return ParentCell + Step
end

local function Cells(): { [string]: Vector2 }
	local Out = {}

	for Name in Model do
		local Cell = CellOf(Name)

		if Cell then
			Out[Name] = Cell
		end
	end

	return Out
end

local function ChildrenOf(Name: string): { string }
	local Out = {}

	for Other, Node in Model do
		if Node.Parent == Name then
			table.insert(Out, Other)
		end
	end

	table.sort(Out)

	return Out
end

local function Subtree(Name: string): { [string]: boolean }
	local Out, Stack = {}, { Name }

	while #Stack > 0 do
		local Current = table.remove(Stack) :: string
		Out[Current] = true

		for _, Child in ChildrenOf(Current) do
			table.insert(Stack, Child)
		end
	end

	return Out
end

local function KeyFor(Text: string): string
	local Base = (Text:gsub("[^%a%d]", ""))

	if Base == "" or Base:match("^%d") then
		Base = "Node" .. Base
	end

	if not Model[Base] then
		return Base
	end

	local Index = 2

	while Model[Base .. Index] do
		Index += 1
	end

	return Base .. Index
end

local function AddChild(ParentName: string, DirectionName: string)
	local Occupied = Cells()
	local ParentCell = Occupied[ParentName]

	if not ParentCell then
		Say("cannot place against a node that has no position", true)
		return
	end

	local Wanted = ParentCell + StepByName[DirectionName]

	for Name, Cell in Occupied do
		if Cell == Wanted then
			Say("that side is taken by " .. Name, true)
			return
		end
	end

	local Key = KeyFor("New Node")
	Model[Key] = { Parent = ParentName, Direction = DirectionName, Text = "New Node", Color = "default", Cost = 1000 }
	Selected = Key

	Say("added " .. Key .. " " .. DirectionName .. " of " .. ParentName)
	Rebuild()
end

local function DeleteBranch(Name: string)
	if not Model[Name] then
		return
	end

	if not Model[Name].Parent then
		Say("the root cannot be deleted", true)
		return
	end

	local Doomed = Subtree(Name)
	local Removed = 0

	for Key in Doomed do
		Model[Key] = nil
		Removed += 1
	end

	Selected = nil

	Say("deleted " .. Removed .. (if Removed == 1 then " node" else " nodes, branch included"))
	Rebuild()
end

--> moving a node means finding it a new parent: whichever placed node sits one step from the cell it
--> was dropped on. its own descendants are off limits or the tree would form a loop
local function MoveTo(Name: string, Cell: Vector2): (boolean, string)
	local Node = Model[Name]

	if not Node or not Node.Parent then
		return false, "the root stays where it is"
	end

	local Occupied = Cells()
	local Own = Subtree(Name)

	for Other, Taken in Occupied do
		if Taken == Cell and Other ~= Name then
			return false, Other .. " is already there"
		end
	end

	local Best, BestDirection = nil, nil

	for Other, OtherCell in Occupied do
		if Own[Other] then
			continue
		end

		local Key = (Cell - OtherCell).X .. "," .. (Cell - OtherCell).Y
		local DirectionName = NameByStep[Key]

		if DirectionName then
			--> prefer keeping the parent it already had, so a nudge does not silently re-hang a branch
			if Other == Node.Parent then
				Best, BestDirection = Other, DirectionName
				break
			end

			if not Best then
				Best, BestDirection = Other, DirectionName
			end
		end
	end

	if not Best then
		return false, "nothing to hang it off there"
	end

	Node.Parent = Best
	Node.Direction = BestDirection

	return true, "moved " .. Name .. " " .. tostring(BestDirection) .. " of " .. Best
end

local function Serialise(): string
	local Names = {}

	for Name in Model do
		table.insert(Names, Name)
	end

	local Order, Placed = {}, {}
	local Root = RootName()

	if Root then
		table.insert(Order, Root)
		Placed[Root] = true
	end

	local Added = true

	while Added do
		Added = false
		table.sort(Names)

		for _, Name in Names do
			local Node = Model[Name]

			if not Placed[Name] and Node.Parent and Placed[Node.Parent] then
				table.insert(Order, Name)
				Placed[Name] = true
				Added = true
			end
		end
	end

	--> anything left has a broken parent link; keep it rather than silently dropping the user's work
	for _, Name in Names do
		if not Placed[Name] then
			table.insert(Order, Name)
		end
	end

	local Out = {}

	table.insert(
		Out,
		[[--> One entry per node in the upgrade tree. Parent is the upgrade that has to be bought first, and
--> Direction places the node against that parent -- one of Top, Bottom, TopLeft, TopRight,
--> BottomLeft, BottomRight, Left, Right. Exactly one entry may omit Parent: that one is the root.
--> Colours are the palettes in NodeConstructor.Colors: default, green, blue, purple, gold, red.

--> Written by the Upgrade Tree Editor plugin. Hand edits survive a round trip, but the layout of
--> this file is regenerated, so keep notes in the comments above rather than beside an entry.

export type Upgrade = {
	Parent: string?,
	Direction: string?,
	Icon: string?,
	Text: string,

	--> stored for the tree editor and future tooltips; nothing renders it yet
	Description: string?,
	Header: string?,
	Color: string?,
	Cost: number?,

	--> a node that does something other than being bought, like the Exit button at the middle. it
	--> never locks, never shows a price, and counts as owned so the ring around it is reachable.
	IsAction: boolean?,
}

--> fill this in with the cash icon once it exists; an empty id just draws nothing next to the price
local CashIcon = "]]
			.. CashIcon
			.. [["

local Upgrades: { [string]: Upgrade } = {]]
	)

	for _, Name in Order do
		local Node = Model[Name]
		local Lines = { "\t" .. Name .. " = {" }

		if Node.Parent then
			table.insert(Lines, '\t\tParent = "' .. Node.Parent .. '",')
		end

		if Node.Direction then
			table.insert(Lines, '\t\tDirection = "' .. Node.Direction .. '",')
		end

		if Node.Icon and Node.Icon ~= "" then
			table.insert(Lines, '\t\tIcon = "' .. Node.Icon .. '",')
		end

		table.insert(Lines, '\t\tText = "' .. Node.Text .. '",')

		if Node.Description and Node.Description ~= "" then
			table.insert(Lines, '\t\tDescription = "' .. Node.Description .. '",')
		end

		if Node.Header and Node.Header ~= "" then
			table.insert(Lines, '\t\tHeader = "' .. Node.Header .. '",')
		end

		if Node.Color then
			table.insert(Lines, '\t\tColor = "' .. Node.Color .. '",')
		end

		if Node.Cost then
			table.insert(Lines, "\t\tCost = " .. Node.Cost .. ",")
		end

		if Node.IsAction then
			table.insert(Lines, "\t\tIsAction = true,")
		end

		table.insert(Lines, "\t},")
		table.insert(Out, "\n" .. table.concat(Lines, "\n"))
	end

	table.insert(Out, "\n}\n\nreturn {\n\tCashIcon = CashIcon,\n\tList = Upgrades,\n}\n")

	return table.concat(Out)
end

local function Post(Body: string): (boolean, string)
	local Ok, Result = pcall(function()
		return HttpService:RequestAsync({
			Url = WriterUrl,
			Method = "POST",
			Headers = { ["Content-Type"] = "text/plain" },
			Body = Body,
		})
	end)

	if not Ok then
		return false, tostring(Result)
	end

	if Result.StatusCode ~= 200 then
		return false, "writer refused it: " .. tostring(Result.Body)
	end

	return true, ""
end

--> a playtest's HttpService is the running game's, and that one refuses plugin requests outright, so
--> during a test the file is parked in plugin settings and written the moment edit mode is back
--> rojo is the normal route from disk back into the place, but it stalls in a Team Create session,
--> which leaves the game running the old tree however many times the file is written. writing the
--> module here as well costs nothing and means Save always lands, with identical content either way.
local function WriteModule(Body: string): (boolean, string)
	local Script = GetConfigScript()

	if not Script then
		return false, "Shared.Configs.Upgrades is not in this place"
	end

	local Ok, Problem = pcall(function()
		Script.Source = Body
	end)

	if not Ok then
		return false, tostring(Problem)
	end

	return true, ""
end

local function Flush(): boolean
	local Parked = plugin:GetSetting(PendingKey)

	if type(Parked) ~= "string" or Parked == "" then
		return false
	end

	local Sent, Problem = Post(Parked)

	if not Sent then
		warn("[UpgradeTreeEditor] could not flush the parked save: " .. Problem)
		return false
	end

	WriteModule(Parked)
	plugin:SetSetting(PendingKey, nil)
	Say("wrote the save you made during the playtest")

	return true
end

local function Save()
	local Built, Body = pcall(Serialise)

	if not Built then
		Say("could not build the file -- see Output", true)
		warn("[UpgradeTreeEditor] serialise failed: " .. tostring(Body))
		return
	end

	if RunService:IsRunning() then
		plugin:SetSetting(PendingKey, Body)
		Say("playtest running -- parked " .. Count() .. " nodes, writes when you stop")
		return
	end

	local Sent, PostProblem = Post(Body)
	local Wrote, ModuleProblem = WriteModule(Body)

	if not Sent then
		warn("[UpgradeTreeEditor] disk write failed: " .. PostProblem .. "  (is tools/treewriter.py running?)")
	end

	if not Wrote then
		warn("[UpgradeTreeEditor] module write failed: " .. ModuleProblem)
	end

	if not Sent and not Wrote then
		Say("save failed both ways -- see Output", true)
		return
	end

	plugin:SetSetting(PendingKey, nil)

	if Sent and Wrote then
		Say("saved " .. Count() .. " nodes to the file and the place")
	elseif Wrote then
		Say("saved to the place, but not to disk -- start tools/treewriter.py", true)
	else
		Say("saved to disk, but the place still has the old tree", true)
	end
end

--> UI

local Info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 560, 700, 440, 560)
local Widget = plugin:CreateDockWidgetPluginGuiAsync("UpgradeTreeEditor", Info)
Widget.Title = "Upgrade Tree"

--> Global is the default and it lets a raised parent cover its own children, which blanked a node's
--> label the moment it was selected or dragged. Sibling keeps descendants above their ancestor and
--> uses ZIndex only to order siblings.
Widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local InspectorHeight = 236

local Root = Create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Dark,
	BorderSizePixel = 0,
}, Widget)

local TopBar = Create("Frame", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = Panel,
	BorderSizePixel = 0,
}, Root)

local function Button(Text: string, Width: number, Fill: Color3, Parent: Instance): TextButton
	local Item = Create("TextButton", {
		Size = UDim2.fromOffset(Width, 24),
		BackgroundColor3 = Fill,
		BorderSizePixel = 0,
		Text = Text,
		TextColor3 = Ink,
		TextSize = 13,
		Font = Enum.Font.SourceSansBold,
		AutoButtonColor = true,
	}, Parent)

	Create("UICorner", { CornerRadius = UDim.new(0, 4) }, Item)

	return Item
end

local function Box(Placeholder: string, Parent: Instance): TextBox
	local Item = Create("TextBox", {
		BackgroundColor3 = Field,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = Placeholder,
		PlaceholderColor3 = Muted,
		TextColor3 = Ink,
		TextSize = 14,
		Font = Enum.Font.SourceSans,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
	}, Parent)

	Create("UICorner", { CornerRadius = UDim.new(0, 4) }, Item)
	Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, Item)

	return Item
end

local ReloadButton = Button("Reload", 68, Line, TopBar)
ReloadButton.Position = UDim2.fromOffset(8, 5)

local SaveButton = Button("Save to file", 96, Accent, TopBar)
SaveButton.Position = UDim2.fromOffset(82, 5)

local FitButton = Button("Fit", 40, Line, TopBar)
FitButton.Position = UDim2.new(1, -128, 0, 5)

local ZoomOutButton = Button("−", 26, Line, TopBar)
ZoomOutButton.Position = UDim2.new(1, -84, 0, 5)

local ZoomInButton = Button("+", 26, Line, TopBar)
ZoomInButton.Position = UDim2.new(1, -54, 0, 5)

local ZoomLabel = Create("TextLabel", {
	Position = UDim2.new(1, -24, 0, 5),
	Size = UDim2.fromOffset(20, 24),
	BackgroundTransparency = 1,
	Text = "1x",
	TextColor3 = Muted,
	TextSize = 11,
	Font = Enum.Font.SourceSans,
}, TopBar)

Status = Create("TextLabel", {
	Position = UDim2.fromOffset(190, 0),
	Size = UDim2.new(1, -324, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Muted,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Font = Enum.Font.SourceSans,
}, TopBar)

local Preview = Create("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 34),
	Size = UDim2.new(1, 0, 1, -34 - InspectorHeight - 20),
	BackgroundColor3 = Dark,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	ClipsDescendants = true,
}, Root)

local Wires = Create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 1,
}, Preview)

local Hint = Create("TextLabel", {
	Position = UDim2.new(0, 0, 1, -20),
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundColor3 = Panel,
	BorderSizePixel = 0,
	Text = "click to select  ·  drag to move, it snaps  ·  scroll to pan, Fit to see it all",
	TextColor3 = Muted,
	TextSize = 11,
	Font = Enum.Font.SourceSans,
	ZIndex = 20,
}, Root)
Hint.Position = UDim2.new(0, 0, 1, -InspectorHeight - 20)

local Inspector = Create("Frame", {
	Position = UDim2.new(0, 0, 1, -InspectorHeight),
	Size = UDim2.new(1, 0, 0, InspectorHeight),
	BackgroundColor3 = Panel,
	BorderSizePixel = 0,
}, Root)

local SelectedLabel = Create("TextLabel", {
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 16),
	BackgroundTransparency = 1,
	Text = "nothing selected",
	TextColor3 = Ink,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Font = Enum.Font.SourceSansBold,
}, Inspector)

local function Caption(Text: string, X: number, Y: number, Width: number): TextLabel
	return Create("TextLabel", {
		Position = UDim2.fromOffset(X, Y),
		Size = UDim2.fromOffset(Width, 13),
		BackgroundTransparency = 1,
		Text = Text,
		TextColor3 = Muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSans,
	}, Inspector)
end

Caption("LABEL", 12, 30, 100)
local NameBox = Box("shown on the node", Inspector)
NameBox.Position = UDim2.fromOffset(12, 45)
NameBox.Size = UDim2.new(0.5, -18, 0, 26)

Caption("PRICE", 12, 78, 100)
local CostBox = Box("500, 25k, 1.5m", Inspector)
CostBox.Position = UDim2.fromOffset(12, 93)
CostBox.Size = UDim2.fromOffset(120, 26)

Caption("COLOUR", 140, 78, 100)
local ColorButton = Button("default", 110, Line, Inspector)
ColorButton.Position = UDim2.fromOffset(140, 93)
ColorButton.Size = UDim2.fromOffset(110, 26)

Caption("DESCRIPTION", 12, 126, 140)
local DescBox = Box("what this upgrade does", Inspector)
DescBox.Position = UDim2.fromOffset(12, 141)
DescBox.Size = UDim2.new(1, -24, 0, 26)
DescBox.TextWrapped = true

Caption("ADD CHILD ON SIDE", 12, 174, 160)

local DirectionButtons = {}

for Index, Entry in Directions do
	local Item = Button(Entry.Label, 30, Line, Inspector)
	Item.Size = UDim2.fromOffset(28, 18)
	Item.Position = UDim2.fromOffset(12 + (Entry.Column - 1) * 32, 190 + (Entry.Row - 1) * 15)
	Item.TextSize = 13

	Item.MouseButton1Click:Connect(function()
		if Selected then
			AddChild(Selected, Entry.Name)
		end
	end)

	DirectionButtons[Index] = Item
end

local DeleteButton = Button("Delete branch", 116, Danger, Inspector)
DeleteButton.Position = UDim2.new(1, -128, 0, 190)
DeleteButton.Size = UDim2.fromOffset(116, 26)

--> preview

type Parts = { Item: TextButton, Title: TextLabel, Price: TextLabel, Badge: TextLabel }

local NodeParts: { [string]: Parts } = {}
local WireParts = {}

local function CanvasPointOf(Cell: Vector2): Vector2
	return Origin + Vector2.new(Cell.X * StepX, Cell.Y * StepY)
end

local function CellAt(Point: Vector2): Vector2
	local Raw = Point - Origin
	local X = math.round(Raw.X / StepX)
	local Y = math.round(Raw.Y / StepY)

	--> only cells whose coordinates share a parity exist on the grid; nudge the row that moved least
	if (X + Y) % 2 ~= 0 then
		local Ideal = Raw.Y / StepY

		Y += if Ideal > Y then 1 else -1
	end

	return Vector2.new(X, Y)
end

local function DrawWire(From: Vector2, To: Vector2, Highlight: boolean)
	local Delta = To - From
	local Length = Delta.Magnitude

	if Length < 1 then
		return
	end

	local Middle = From + Delta / 2
	local Angle = math.deg(math.atan2(Delta.Y, Delta.X))

	table.insert(
		WireParts,
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Middle.X, Middle.Y),
			Size = UDim2.fromOffset(Length, if Highlight then 3 else 2),
			Rotation = Angle,
			BackgroundColor3 = if Highlight then Accent else Line,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, Wires)
	)

	--> a head two thirds along, so which way the branch runs is readable at a glance
	table.insert(
		WireParts,
		Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(From.X + Delta.X * 0.68, From.Y + Delta.Y * 0.68),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Text = "➤",
			TextColor3 = if Highlight then Accent else Line,
			TextSize = math.max(11, 14 * Zoom),
			Rotation = Angle,
			Font = Enum.Font.SourceSansBold,
			ZIndex = 2,
		}, Wires)
	)
end

local function MakeNode(Name: string): Parts
	local Item = Create("TextButton", {
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
	}, Preview)

	Create("UICorner", { CornerRadius = UDim.new(0, 8) }, Item)
	Create("UIStroke", { Color = Color3.fromRGB(18, 19, 22), Thickness = 1 }, Item)

	local Title = Create("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Ink,
		TextWrapped = true,
		Font = Enum.Font.SourceSansBold,
		ZIndex = 6,
	}, Item)

	local Price = Create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.SourceSansBold,
		ZIndex = 6,
	}, Item)

	local Badge = Create("TextLabel", {
		BackgroundTransparency = 1,
		Text = "≡",
		TextColor3 = Ink,
		Font = Enum.Font.SourceSansBold,
		ZIndex = 6,
	}, Item)

	local Parts: Parts = { Item = Item, Title = Title, Price = Price, Badge = Badge }

	Item.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			BeginDrag(Name, Vector2.new(Input.Position.X, Input.Position.Y))
		end
	end)

	Item.MouseEnter:Connect(function()
		if not Dragging and Name ~= Selected then
			TweenService:Create(Item, TweenInfo.new(0.12), { BackgroundTransparency = 0.15 }):Play()
		end
	end)

	Item.MouseLeave:Connect(function()
		TweenService:Create(Item, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
	end)

	Item.MouseButton1Click:Connect(function()
		if Dragging then
			return
		end

		Selected = Name
		Rebuild()
	end)

	return Parts
end

--> reuses the buttons it already has and slides them to their new cells. rebuilding from scratch on
--> every keystroke is what made the board flicker
function Rebuild()
	local Placed = Cells()

	for Name, Parts in NodeParts do
		if not Placed[Name] then
			Parts.Item:Destroy()
			NodeParts[Name] = nil
		end
	end

	for _, Item in WireParts do
		Item:Destroy()
	end

	table.clear(WireParts)

	local Min, Max = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	local Any = false

	for _, Cell in Placed do
		Min, Max, Any = Min:Min(Cell), Max:Max(Cell), true
	end

	if not Any then
		Preview.CanvasSize = UDim2.new()
		Refresh()
		return
	end

	Origin = Vector2.new(Padding - Min.X * StepX, Padding - Min.Y * StepY)
	Preview.CanvasSize = UDim2.fromOffset(
		(Max.X - Min.X) * StepX + NodeSize + Padding * 2,
		(Max.Y - Min.Y) * StepY + NodeSize + Padding * 2
	)

	local Half = Vector2.new(NodeSize, NodeSize) / 2

	for Name, Cell in Placed do
		local Node = Model[Name]

		if Node.Parent and Placed[Node.Parent] then
			DrawWire(
				CanvasPointOf(Placed[Node.Parent]) + Half,
				CanvasPointOf(Cell) + Half,
				Name == Selected or Node.Parent == Selected
			)
		end
	end

	for Name, Cell in Placed do
		local Node = Model[Name]
		local Parts = NodeParts[Name]

		if not Parts then
			Parts = MakeNode(Name)
			NodeParts[Name] = Parts
			Parts.Item.Position = UDim2.fromOffset(CanvasPointOf(Cell).X, CanvasPointOf(Cell).Y)
		end

		local IsSelected = Name == Selected
		local Fill = Swatch[Node.Color or "default"] or Swatch.default
		local Point = CanvasPointOf(Cell)
		local Item = Parts.Item

		Item.Size = UDim2.fromOffset(NodeSize, NodeSize)
		Item.BackgroundColor3 = if not Node.Parent then Danger else Fill

		if Name == Dragging then
			Item.Position = UDim2.fromOffset(Point.X, Point.Y)
		else
			TweenService:Create(Item, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
				Position = UDim2.fromOffset(Point.X, Point.Y),
			}):Play()
		end

		Item.ZIndex = if IsSelected then 8 else 5

		local Stroke = Item:FindFirstChildOfClass("UIStroke") :: UIStroke
		Stroke.Color = if IsSelected then Ink else Color3.fromRGB(18, 19, 22)
		Stroke.Thickness = if IsSelected then 3 else 1

		--> laid out as fractions of the node. the old fixed offsets ran into each other once a node
		--> shrank past about forty pixels, which is what made zoomed-out nodes look like mush
		local Compact = NodeSize < 48
		local BadgeOn = not Compact and (Node.Description or "") ~= ""

		--> the badge sits in the top right corner, so the title gives up that much width or a long
		--> name runs underneath it
		Parts.Title.Position = UDim2.fromOffset(3, math.floor(NodeSize * 0.12))
		Parts.Title.Size =
			UDim2.new(1, -6 - (if BadgeOn then 12 else 0), 0, math.floor(NodeSize * (if Compact then 0.66 else 0.42)))
		Parts.Title.Text = Node.Text
		Parts.Title.TextSize = math.clamp(math.floor(NodeSize * 0.19), 8, 15)

		Parts.Price.Visible = not Compact
		Parts.Price.Position = UDim2.fromOffset(3, math.floor(NodeSize * 0.6))
		Parts.Price.Size = UDim2.new(1, -6, 0, math.floor(NodeSize * 0.26))
		Parts.Price.Text = if Node.IsAction then "action" else Pretty(Node.Cost)
		Parts.Price.TextSize = math.clamp(math.floor(NodeSize * 0.17), 8, 14)
		Parts.Price.TextColor3 = Color3.fromRGB(255, 255, 255):Lerp(Fill, 0.3)

		Parts.Badge.Position = UDim2.new(1, -14, 0, 2)
		Parts.Badge.Size = UDim2.fromOffset(12, 12)
		Parts.Badge.TextSize = 12
		Parts.Badge.Visible = BadgeOn
	end

	--> the inspector always describes whatever the rebuilt tree now says
	Refresh()
end

--> picks the zoom that shows the whole tree, then centres it
local function FitToView()
	local Placed = Cells()
	local Min, Max = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	local Any = false

	for _, Cell in Placed do
		Min, Max, Any = Min:Min(Cell), Max:Max(Cell), true
	end

	if not Any then
		return
	end

	local Span = Max - Min
	local View = Preview.AbsoluteSize
	local WantX = (View.X - 40) / ((Span.X * 0.866 + 1) * BaseNodeSize)
	local WantY = (View.Y - 40) / ((Span.Y * 0.5 + 1) * BaseNodeSize)

	SetZoom(math.min(WantX, WantY))
	Rebuild()

	Preview.CanvasPosition = Vector2.new(
		math.max(0, (Preview.CanvasSize.X.Offset - View.X) / 2),
		math.max(0, (Preview.CanvasSize.Y.Offset - View.Y) / 2)
	)
end

--> drag
--> a TextButton sinks the mouse press and release, so neither ever reaches the frame underneath.
--> this sheet goes over everything while a drag runs and catches the movement and the drop.
local Catcher = Create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	Active = true,
	ZIndex = 50,
}, Root)

local function ClearDragTint()
	local Parts = if Dragging then NodeParts[Dragging] else nil

	if not Parts then
		return
	end

	local Stroke = Parts.Item:FindFirstChildOfClass("UIStroke") :: UIStroke
	Stroke.Color = Ink
	Stroke.Thickness = 3
end

function BeginDrag(Name: string, At: Vector2)
	PressedOn = Name
	PressedAt = At
end

function UpdateDrag(At: Vector2)
	if PressedOn and not Dragging and PressedAt and (At - PressedAt).Magnitude > DragThreshold then
		if Model[PressedOn] and Model[PressedOn].Parent then
			Dragging = PressedOn
			Catcher.Visible = true
			Say("drop it on a free cell next to another node")
		end
	end

	if not Dragging then
		return
	end

	local Parts = NodeParts[Dragging]

	if not Parts then
		return
	end

	local Local = At - Preview.AbsolutePosition + Preview.CanvasPosition
	local Cell = CellAt(Local - Vector2.new(NodeSize, NodeSize) / 2)
	local Occupied = Cells()
	local Own = Subtree(Dragging)

	DragCell = Cell
	DragValid = true

	for Other, Taken in Occupied do
		if Taken == Cell and Other ~= Dragging then
			DragValid = false
		end
	end

	if DragValid then
		local Anchored = false

		for Other, OtherCell in Occupied do
			if not Own[Other] and NameByStep[(Cell - OtherCell).X .. "," .. (Cell - OtherCell).Y] then
				Anchored = true
				break
			end
		end

		DragValid = Anchored
	end

	local Point = CanvasPointOf(Cell)
	Parts.Item.Position = UDim2.fromOffset(Point.X, Point.Y)
	Parts.Item.ZIndex = 20

	local Stroke = Parts.Item:FindFirstChildOfClass("UIStroke") :: UIStroke
	Stroke.Color = if DragValid then Color3.fromRGB(120, 240, 140) else Color3.fromRGB(255, 105, 105)
	Stroke.Thickness = 3
end

local function EndDrag()
	local Name = Dragging

	ClearDragTint()
	Catcher.Visible = false
	PressedOn, PressedAt, Dragging = nil, nil, nil

	if not Name then
		return
	end

	local Moved, Message = MoveTo(Name, DragCell)

	Say(Message, not Moved)
	Selected = Name
	Rebuild()
end

Catcher.InputChanged:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseMovement then
		UpdateDrag(Vector2.new(Input.Position.X, Input.Position.Y))
	end
end)

Catcher.InputEnded:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 then
		EndDrag()
	end
end)

--> before the catcher is up it is the preview that sees the mouse move past the threshold
Preview.InputChanged:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseMovement then
		UpdateDrag(Vector2.new(Input.Position.X, Input.Position.Y))
	end
end)

Root.InputEnded:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Dragging then
		PressedOn, PressedAt = nil, nil
	end
end)

--> releasing outside the window would otherwise leave a node stuck to the cursor
Widget.WindowFocusReleased:Connect(function()
	if Dragging then
		EndDrag()
	end
end)

function Refresh()
	local Node = if Selected then Model[Selected] else nil

	if not Node or not Selected then
		SelectedLabel.Text = "nothing selected  ·  click a node above"
		NameBox.Text = ""
		DescBox.Text = ""
		CostBox.Text = ""
		ColorButton.Text = "-"
		ColorButton.BackgroundColor3 = Line
		DeleteButton.Visible = false

		for _, Item in DirectionButtons do
			Item.Visible = false
		end

		return
	end

	local Kids = #ChildrenOf(Selected)

	SelectedLabel.Text = Selected
		.. (if Node.Parent then "  ·  " .. tostring(Node.Direction) .. " of " .. Node.Parent else "  ·  root")
		.. (if Kids > 0 then "  ·  " .. Kids .. " child" .. (if Kids == 1 then "" else "ren") else "")

	NameBox.Text = Node.Text
	DescBox.Text = Node.Description or ""
	CostBox.Text = if Node.Cost then tostring(Node.Cost) else ""
	ColorButton.Text = Node.Color or "default"
	ColorButton.BackgroundColor3 = Swatch[Node.Color or "default"] or Line
	DeleteButton.Visible = Node.Parent ~= nil

	local Occupied = Cells()
	local Here = Occupied[Selected]

	for Index, Item in DirectionButtons do
		Item.Visible = true

		local Free = true

		if Here then
			local Wanted = Here + Directions[Index].Step

			for _, Cell in Occupied do
				if Cell == Wanted then
					Free = false
					break
				end
			end
		end

		Item.BackgroundColor3 = if Free then Line else Color3.fromRGB(56, 58, 64)
		Item.TextColor3 = if Free then Ink else Muted
	end
end

NameBox.FocusLost:Connect(function()
	local Node = if Selected then Model[Selected] else nil

	if not Node then
		return
	end

	local Clean = NameBox.Text:gsub('"', "'")

	if Clean == "" then
		NameBox.Text = Node.Text
		return
	end

	Node.Text = Clean
	Say("renamed to " .. Clean)
	Rebuild()
end)

DescBox.FocusLost:Connect(function()
	local Node = if Selected then Model[Selected] else nil

	if not Node then
		return
	end

	Node.Description = (DescBox.Text:gsub('"', "'"))
	Say("description set")
	Rebuild()
end)

CostBox.FocusLost:Connect(function()
	local Node = if Selected then Model[Selected] else nil

	if not Node then
		return
	end

	if CostBox.Text == "" then
		Node.Cost = nil
		Say("price cleared")
		Rebuild()
		return
	end

	local Value = ParseCost(CostBox.Text)

	if not Value then
		Say("could not read that price -- try 500, 25k or 1.5m", true)
		CostBox.Text = if Node.Cost then tostring(Node.Cost) else ""
		return
	end

	Node.Cost = Value
	CostBox.Text = tostring(Value)
	Say("price set to " .. Pretty(Value))
	Rebuild()
end)

ColorButton.MouseButton1Click:Connect(function()
	local Node = if Selected then Model[Selected] else nil

	if not Node then
		return
	end

	local Current = Node.Color or "default"
	local Index = 1

	for Slot, Name in Palette do
		if Name == Current then
			Index = Slot
			break
		end
	end

	Node.Color = Palette[(Index % #Palette) + 1]
	Rebuild()
end)

DeleteButton.MouseButton1Click:Connect(function()
	if Selected then
		DeleteBranch(Selected)
	end
end)

local function Rescale(Factor: number)
	SetZoom(Zoom * Factor)
	Rebuild()
	ZoomLabel.Text = string.format("%.2gx", Zoom)
end

ZoomInButton.MouseButton1Click:Connect(function()
	Rescale(1.2)
end)

ZoomOutButton.MouseButton1Click:Connect(function()
	Rescale(1 / 1.2)
end)

FitButton.MouseButton1Click:Connect(function()
	FitToView()
	ZoomLabel.Text = string.format("%.2gx", Zoom)
end)

ReloadButton.MouseButton1Click:Connect(function()
	if Load() then
		Rebuild()
	end
end)

SaveButton.MouseButton1Click:Connect(Save)

local Toolbar = plugin:CreateToolbar("Run an Office")
local Toggle = Toolbar:CreateButton(
	"Upgrade Tree",
	"Edit Configs.Upgrades in place",
	"rbxasset://textures/ui/GuiImagePlaceholder.png"
)

Toggle.Click:Connect(function()
	Widget.Enabled = not Widget.Enabled

	if Widget.Enabled and next(Model) == nil then
		if Load() then
			Rebuild()
			task.defer(function()
				FitToView()
				ZoomLabel.Text = string.format("%.2gx", Zoom)
			end)
		end
	end
end)

Widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	Toggle:SetActive(Widget.Enabled)
end)

Rebuild()

--> nothing fires when a playtest ends, so poll for it. cheap, and it only does work when a save was
--> parked because http was blocked mid-test
task.spawn(function()
	while true do
		task.wait(2)

		if not RunService:IsRunning() and plugin:GetSetting(PendingKey) then
			Flush()
		end
	end
end)
