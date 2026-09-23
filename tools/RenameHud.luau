--> Names every instance under StarterGui.HudGUI after what it actually is. The hud is built in the
--> place rather than synced from disk, so this runs against the DataModel: paste it into the Studio
--> command bar in Edit mode.

--> It prints the plan and changes nothing until Apply is switched on. Read the plan first: a mass
--> rename is not something to run blind, and anything the rules cannot name is listed at the end
--> to be named by hand rather than guessed at.

--> Safe to run twice. Every name comes from what the instance holds, so a second pass lands on the
--> same names instead of stacking suffixes.

--> Nothing outside the hud is touched, and the hud holds no scripts. The only code reading it is
--> UIController, which finds buttons by the words on them rather than by name.

local StarterGui = game:GetService("StarterGui")

local Apply = false

local HudName = "HudGUI"

--> Containers, by the name they carry today.
local Containers = {
	Handler = "Root",
	MoneyGUI = "CashBar",
	ButtonsGUI = "ButtonBar",
	Home_ShopGUI = "TopBar",
	Claim_2xcashGUI = "RewardBar",
	LeftCentre = "SideBar",
	Invenotry = "InventoryButton",
}

--> Names too common to match on their own. "Frame" is half the hud, and only the one directly
--> under Handler is the menu bar, so these carry the parent as well. The pass runs deepest first,
--> which is what keeps a parent under its old name long enough to be read here.
local Paths = {
	["Handler.Frame"] = "MenuBar",
}

--> Named by hand, because the words in them do not say which is which: CashBar and RewardBar each
--> hold two labels and two icons, and only where they sit tells the claimable cash from the robux
--> price. The rules would pull all four back to ValueLabel and Icon, so they are left alone.
local Keep = {
	CashLabel = true,
	FriendMultiplierLabel = true,
	AddCashButton = true,
	FriendIcon = true,
	ClaimAmountLabel = true,
	CashIcon = true,
	RobuxPriceLabel = true,
	RobuxIcon = true,
}

--> Words that do not make a name on their own.
local Words = {
	["2x cash"] = "DoubleCash",
	["Claim!"] = "Claim",
}

--> Not visible in themselves, and there is only ever one of each per parent, so the class is the
--> whole name.
local Decorations = {
	UIStroke = "Stroke",
	UICorner = "Corner",
	UIGradient = "Gradient",
	UIPadding = "Padding",
	UIListLayout = "Layout",
	UIGridLayout = "Layout",
	UIAspectRatioConstraint = "AspectRatio",
	UISizeConstraint = "SizeConstraint",
	UITextSizeConstraint = "TextSizeConstraint",
	UIScale = "Scale",
}

local Plan = {}
local Unnamed = {}

--> A number, a price, a countdown: text the game rewrites, so the words in it now are not a name.
local function IsValue(Text: string): boolean
	return string.match(Text, "^[%d%s%$%.,%+%-/:xKMBTQ]+$") ~= nil
end

local function ToPascal(Text: string): string
	local Mapped = Words[Text]

	if Mapped then
		return Mapped
	end

	local Out = ""

	--> rich text is markup, not words: "Friend Multiplier: <font color=...>+10%</font>" is the
	--> friend multiplier, not the FriendMultiplierFontColorRgbFont
	for Word in string.gmatch(string.gsub(Text, "<[^>]->", ""), "%a+") do
		Out ..= string.upper(string.sub(Word, 1, 1)) .. string.lower(string.sub(Word, 2))
	end

	return Out
end

--> The words on a button, taken from the nearest label. A label deeper inside another button
--> belongs to that one, so the walk stops there.
local function LabelOf(Object: Instance): string?
	for _, Child in Object:GetChildren() do
		if Child:IsA("TextLabel") and Child.Text ~= "" and not IsValue(Child.Text) then
			return Child.Text
		end

		if Child:IsA("GuiButton") then
			continue
		end

		local Found = LabelOf(Child)

		if Found then
			return Found
		end
	end

	return nil
end

--> Art stretched across the whole of its parent is the backdrop; anything smaller sits on top of
--> it. Scale is used rather than the rendered size because nothing in StarterGui is drawn yet.
local function Fills(Object: GuiObject): boolean
	return Object.Size.X.Scale >= 0.95 and Object.Size.Y.Scale >= 0.95
end

local function NameFor(Object: Instance): string?
	if Keep[Object.Name] then
		return Object.Name
	end

	local Parent = Object.Parent
	local Scoped = Parent and Paths[Parent.Name .. "." .. Object.Name]

	if Scoped then
		return Scoped
	end

	local Mapped = Containers[Object.Name]

	if Mapped then
		return Mapped
	end

	local Decoration = Decorations[Object.ClassName]

	if Decoration then
		return Decoration
	end

	if Object:IsA("TextLabel") or Object:IsA("TextBox") then
		--> the text is the name: "Claim!" is the ClaimLabel, and the one reading 18K+ is whatever
		--> number the game happens to be showing, so it is named for the job instead
		if Object.Text == "" then
			return "Label"
		end

		return if IsValue(Object.Text) then "ValueLabel" else ToPascal(Object.Text) .. "Label"
	end

	if Object:IsA("GuiButton") then
		local Label = LabelOf(Object)

		--> art drawn on top of the button it sits in, which is what used to swallow the press
		if not Label then
			return if Fills(Object) then "Background" else "Icon"
		end

		return ToPascal(Label) .. "Button"
	end

	if Object:IsA("ImageLabel") then
		return if Fills(Object) then "Background" else "Icon"
	end

	if Object:IsA("ViewportFrame") then
		return "Viewport"
	end

	if Object:IsA("ScrollingFrame") then
		return "List"
	end

	--> A frame is named for what it holds, since the frame itself looks like nothing.
	if Object:IsA("Frame") then
		local Label = LabelOf(Object)

		return if Label then ToPascal(Label) .. "Group" else nil
	end

	return nil
end

--> Two children of one parent can still want the same name -- two icons in one button, say. The
--> second takes the parent's name with it, which says more than a 2 on the end would.
local function Free(Parent: Instance, Object: Instance, Wanted: string): string
	local Taken = Parent:FindFirstChild(Wanted)

	if not Taken or Taken == Object then
		return Wanted
	end

	--> the parent's new name, not the one it still carries: children are renamed before it is, and
	--> "ClaimXcashGuiIcon" helps nobody
	local Qualified = ToPascal(NameFor(Parent) or Parent.Name) .. Wanted

	Taken = Parent:FindFirstChild(Qualified)

	if not Taken or Taken == Object then
		return Qualified
	end

	local Index = 2

	while true do
		local Candidate = Qualified .. Index
		local Other = Parent:FindFirstChild(Candidate)

		if not Other or Other == Object then
			return Candidate
		end

		Index += 1
	end
end

local Hud = StarterGui:FindFirstChild(HudName)

assert(Hud, `StarterGui.{HudName} is not in this place`)

--> Deepest first, so a parent is still under its old name while its children are read.
local Objects = Hud:GetDescendants()

table.sort(Objects, function(Left: Instance, Right: Instance)
	return #string.split(Left:GetFullName(), ".") > #string.split(Right:GetFullName(), ".")
end)

for _, Object in Objects do
	local Wanted = NameFor(Object)

	if not Wanted then
		table.insert(Unnamed, Object.ClassName .. "  " .. Object:GetFullName())
		continue
	end

	local Parent = Object.Parent :: Instance
	local Final = Free(Parent, Object, Wanted)

	if Object.Name == Final then
		continue
	end

	table.insert(Plan, Object.Name .. "  ->  " .. Final .. "   (" .. Object.ClassName .. " in " .. Parent.Name .. ")")

	if Apply then
		Object.Name = Final
	end
end

--> The whole hud with the detail a name would be chosen from, printed on a dry run so the ones the
--> rules cannot reach can be named by hand off a single pass.
if not Apply then
	print("[RenameHud] tree:")

	for _, Object in Objects do
		local Detail = ""

		if Object:IsA("TextLabel") or Object:IsA("TextButton") then
			Detail = ` text="{Object.Text}"`
		elseif Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
			Detail = ` image={Object.Image}`
		end

		if Object:IsA("GuiObject") then
			Detail ..= ` size={Object.Size}`
		end

		print(`  {Object.ClassName}  {string.gsub(Object:GetFullName(), "StarterGui%.HudGUI%.", "")}{Detail}`)
	end
end

print(`[RenameHud] {if Apply then "renamed" else "would rename"} {#Plan}, cannot name {#Unnamed}`)

for _, Line in Plan do
	print("  " .. Line)
end

for _, Line in Unnamed do
	warn("  needs naming by hand: " .. Line)
end

if not Apply then
	warn("[RenameHud] nothing was changed. set Apply = true at the top to write these names.")
end
