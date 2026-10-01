--> One entry per node in the upgrade tree. Parent is the upgrade that has to be bought first, and
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
local CashIcon = ""

local Upgrades: { [string]: Upgrade } = {
	Exit = {
		Text = "Exit",
		Color = "red",
		IsAction = true,
	},
	CashI = {
		Parent = "Exit",
		Direction = "Top",
		Text = "Cash I",
		Description = "Million Billion",
		Color = "gold",
		Cost = 1600,
	},
	CashII = {
		Parent = "CashI",
		Direction = "TopLeft",
		Text = "Cash II",
		Color = "gold",
		Cost = 190000,
	},
	CashIII = {
		Parent = "CashII",
		Direction = "BottomLeft",
		Text = "Cash III",
		Color = "gold",
		Cost = 5000000,
	},
	CashIV = {
		Parent = "CashIII",
		Direction = "TopLeft",
		Text = "Cash IV",
		Color = "gold",
		Cost = 59000000,
	},
	FasterEmployees = {
		Parent = "CashI",
		Direction = "TopRight",
		Text = "Faster Employees",
		Color = "green",
		Cost = 51000,
	},
	FasterEmployeesII = {
		Parent = "FasterEmployees",
		Direction = "TopRight",
		Text = "Faster Employees II",
		Color = "green",
		Cost = 1400000,
	},
	FasterRolls = {
		Parent = "CashII",
		Direction = "Top",
		Text = "Faster Rolls",
		Color = "blue",
		Cost = 640000,
	},
	FasterRollsPlus = {
		Parent = "FasterRolls",
		Direction = "Top",
		Text = "Even Faster Rolls",
		Color = "blue",
		Cost = 2700000,
	},
	LuckyI = {
		Parent = "Exit",
		Direction = "BottomLeft",
		Text = "Lucky I",
		Color = "green",
		Cost = 7200,
	},
	LuckyII = {
		Parent = "LuckyI",
		Direction = "BottomLeft",
		Text = "Lucky II",
		Color = "green",
		Cost = 110000,
	},
	LuckyIII = {
		Parent = "LuckyII",
		Direction = "TopLeft",
		Text = "Lucky III",
		Color = "green",
		Cost = 9200000,
	},
	LuckyIV = {
		Parent = "LuckyIII",
		Direction = "TopLeft",
		Text = "Lucky IV",
		Color = "green",
		Cost = 46000000,
	},
	LuckyV = {
		Parent = "LuckyIV",
		Direction = "BottomLeft",
		Text = "Lucky V",
		Color = "green",
		Cost = 190000000,
	},
	NewNode2 = {
		Parent = "FasterEmployeesII",
		Direction = "TopRight",
		Text = "Faster Employees III",
		Color = "green",
		Cost = 19000000,
	},
	NewNode5 = {
		Parent = "FasterRollsPlus",
		Direction = "TopRight",
		Text = "Fastest Rolls",
		Color = "blue",
		Cost = 29000000,
	},
	SmartRoller = {
		Parent = "Exit",
		Direction = "BottomRight",
		Text = "Smart Roller",
		Color = "blue",
		Cost = 8400,
	},
	SpeedI = {
		Parent = "Exit",
		Direction = "TopLeft",
		Text = "Speed I",
		Description = "You walk faster",
		Color = "blue",
		Cost = 3800,
	},
	SpeedII = {
		Parent = "SpeedI",
		Direction = "BottomLeft",
		Text = "Speed II",
		Description = "You walk faster still",
		Color = "blue",
		Cost = 22000,
	},
	GearSlotsI = {
		Parent = "SpeedII",
		Direction = "TopLeft",
		Text = "Gear Slot",
		Description = "Carry one more gear",
		Color = "blue",
		Cost = 69000,
	},
	GearSlotsII = {
		Parent = "GearSlotsI",
		Direction = "TopLeft",
		Text = "Gear Slot II",
		Description = "Carry one more gear again",
		Color = "blue",
		Cost = 2000000,
	},
	HypeRoller = {
		Parent = "LuckyI",
		Direction = "BottomRight",
		Text = "More Rollers",
		Color = "blue",
		Cost = 3500000,
	},
	LegendaryChances = {
		Parent = "LuckyII",
		Direction = "BottomLeft",
		Text = "Legendary Chances",
		Color = "gold",
		Cost = 14000000,
	},
	Luckiest = {
		Parent = "LuckyV",
		Direction = "Bottom",
		Text = "Luckiest",
		Color = "gold",
		Cost = 1200000000,
	},
	MythicChances = {
		Parent = "LegendaryChances",
		Direction = "Bottom",
		Text = "Mythic Chances",
		Color = "gold",
		Cost = 110000000,
	},
	NewNode = {
		Parent = "SmartRoller",
		Direction = "BottomRight",
		Text = "Base Locker",
		Color = "purple",
		Cost = 33000,
	},
	NewNode3 = {
		Parent = "NewNode",
		Direction = "BottomRight",
		Text = "Stronger Defenses",
		Color = "purple",
		Cost = 1000000,
	},
	NewNode4 = {
		Parent = "NewNode3",
		Direction = "Bottom",
		Text = "Super Lasers",
		Color = "purple",
		Cost = 36000000,
	},
	GodlyChances = {
		Parent = "MythicChances",
		Direction = "BottomLeft",
		Text = "Godly Chances",
		Color = "gold",
		Cost = 400000000,
	},
	MegaRoller = {
		Parent = "MythicChances",
		Direction = "Right",
		Text = "Master Rolling",
		Color = "blue",
		Cost = 150000000,
	},
	NewNode6 = {
		Parent = "MegaRoller",
		Direction = "TopRight",
		Text = "Even More  Rollers",
		Color = "blue",
		Cost = 240000000,
	},
	GigaRoller = {
		Parent = "MegaRoller",
		Direction = "Bottom",
		Text = "Super  Many Rollers",
		Color = "blue",
		Cost = 310000000,
	},
	NewNode8 = {
		Parent = "GigaRoller",
		Direction = "BottomRight",
		Text = "Final Roller",
		Color = "blue",
		Cost = 510000000,
	},
}

return {
	CashIcon = CashIcon,
	List = Upgrades,
}
