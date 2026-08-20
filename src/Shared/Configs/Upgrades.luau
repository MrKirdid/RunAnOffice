--> One entry per node in the upgrade tree. Parent is the upgrade that has to be bought first, and
--> Direction places the node against that parent -- one of Top, Bottom, TopLeft, TopRight,
--> BottomLeft, BottomRight. Exactly one entry may omit Parent: that one is the root.
--> Colours are the palettes in NodeConstructor.Colors: default, green, blue, purple, gold, red.

export type Upgrade = {
	Parent: string?,
	Direction: string?,
	Icon: string?,
	Text: string,
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

	RollSpeed = {
		Parent = "Exit",
		Direction = "TopLeft",
		Text = "Roll Speed",
		Color = "blue",
		Cost = 500,
	},

	ExtraRolls = {
		Parent = "RollSpeed",
		Direction = "TopLeft",
		Text = "Extra Rolls",
		Color = "blue",
		Cost = 2_500,
	},

	AutoRoll = {
		Parent = "ExtraRolls",
		Direction = "Top",
		Text = "Auto Roll",
		Header = "NEW!",
		Color = "purple",
		Cost = 25_000,
	},

	Luck = {
		Parent = "Exit",
		Direction = "Top",
		Text = "Luck",
		Color = "green",
		Cost = 1_000,
	},

	BetterLuck = {
		Parent = "Luck",
		Direction = "Top",
		Text = "Better Luck",
		Color = "green",
		Cost = 10_000,
	},

	Income = {
		Parent = "Exit",
		Direction = "TopRight",
		Text = "Income",
		Color = "green",
		Cost = 750,
	},

	BigIncome = {
		Parent = "Income",
		Direction = "TopRight",
		Text = "Big Income",
		Color = "gold",
		Cost = 15_000,
	},

	Desks = {
		Parent = "Exit",
		Direction = "BottomRight",
		Text = "Cheap Desks",
		Color = "default",
		Cost = 5_000,
	},
}

return {
	CashIcon = CashIcon,
	List = Upgrades,
}
