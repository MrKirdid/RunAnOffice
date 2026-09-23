--> The shop, top to bottom, in the order it is drawn: the packs, the server luck row, a Passes
--> header with cards under it, a Cash header with cards under it. Every entry names the row in
--> the place it is drawn with; ShopController clones that row and only ever changes its text and
--> images. MonetizationService grants off the same entries.

--> Templates, by the name of the row in the place:
--> Pack      StarterGui.ShopPackSetup.Pack: a title, a timer line, three icons with a caption under
-->           the first two and a label pair beside the third, one button. What a pack hands out
-->           goes in the boxes: the desks, the workers, then the cash bonus.
--> Feature   ShopUI's luck row: a title, a subtitle, a description, a big icon, one button.
--> Header    ShopUI's section title.
--> Card      ShopUI's pass card: icon, title, description, price. Paired two to a row.
--> CashCard  ShopUI's cash card: one big number and a price. Paired two to a row.

--> Ids are the Creator Hub ids. A 0 is a product not made there yet; the shop shows Price as a
--> stand-in until it is, and once the id is real the number on the button comes from Roblox
--> through GetProductInfo -- that is what lets Managed Pricing test prices.

export type Kind = "Pass" | "Product"

export type DeskSet = {
	Variant: string,
	Sets: number,
}

export type Rung = {
	Key: string,
	Id: number,
	Price: number,
	Multiplier: number,
}

export type Tier = {
	Key: string,
	Id: number,
	Price: number,
	Multiplier: number,
	Minutes: number,
}

export type Entry = {
	Template: string,
	Gradient: string?,
	--> a rail icon of this name scrolls to this row
	Anchor: string?,

	Key: string?,
	Kind: Kind?,
	Id: number?,
	Price: number?,
	Title: string?,
	Subtitle: string?,
	Description: string?,
	Icon: string?,

	--> sold once per account, and only inside the first day: the row goes away after either
	Once: boolean?,
	Timed: boolean?,

	--> CashCard: Hours makes the number the cash that many hours of income is worth right now.
	--> Pack and Card: Variant draws that part set's computer as the icon.
	Hours: number?,
	Variant: string?,

	--> Pack: the desk sets, the employees and the cash the server hands out
	Contents: { DeskSet }?,
	Employee: string?,
	Employees: number?,
	Bonus: number?,

	--> Feature: the server luck tiers, bought lowest to highest as the server's luck rises
	Tiers: { Tier }?,

	--> Card: the cash ladder, one rung for sale at a time
	Rungs: { Rung }?,
}

--> Placeholder art already in the place, until every product has its own icon.
local Icons = {
	Trophy = "rbxassetid://73898620648802",
	Clover = "rbxassetid://78045260176458",
	Ticket = "rbxassetid://109116277315334",
	Cash = "rbxassetid://139241177703025",
}

--> The colours the rows were drawn in stay as drawn; a name here only recolours when given.
local Gradients: { [string]: { Color3 } } = {
	--> the blue the pack was first drawn in; the row in the place now carries Pro's green
	Starter = {
		Color3.fromRGB(0, 255, 255),
		Color3.fromRGB(0, 128, 255),
		Color3.fromRGB(0, 193, 255),
	},
	Pro = {
		Color3.fromRGB(150, 255, 60),
		Color3.fromRGB(0, 190, 90),
		Color3.fromRGB(120, 255, 120),
	},
	Executive = {
		Color3.fromRGB(220, 120, 255),
		Color3.fromRGB(120, 0, 220),
		Color3.fromRGB(255, 140, 255),
	},
	CEO = {
		Color3.fromRGB(255, 235, 80),
		Color3.fromRGB(255, 150, 0),
		Color3.fromRGB(255, 245, 140),
	},
	Founder = {
		Color3.fromRGB(255, 0, 0),
		Color3.fromRGB(255, 191, 0),
		Color3.fromRGB(127, 255, 0),
		Color3.fromRGB(0, 255, 255),
		Color3.fromRGB(127, 0, 255),
		Color3.fromRGB(255, 0, 191),
	},
}

local Layout: { Entry } = {
	--> Packs. The starter sits on top for the day it is on offer, the rest stay.
	{ Template = "Header", Anchor = "Packs", Title = "Packs" },
	{
		Template = "Pack",
		Gradient = "Starter",
		Key = "Starter",
		Kind = "Product",
		Id = 0,
		Price = 49,
		Once = true,
		Timed = true,
		Title = "Starter Pack!",
		Description = "2 Steampunk desks, 2 Hamsters and $10K!",
		Variant = "Steampunk",
		Contents = { { Variant = "Steampunk", Sets = 2 } },
		Employee = "Hamster",
		Employees = 2,
		Bonus = 10000,
	},
	{
		Template = "Pack",
		Gradient = "Pro",
		Key = "Pro",
		Kind = "Product",
		Id = 0,
		Price = 399,
		Title = "Pro Pack!",
		Subtitle = "4 desks + 4 workers",
		Description = "4 Space desks, 4 Shark Bosses and $250K!",
		Variant = "Space",
		Contents = { { Variant = "Space", Sets = 4 } },
		Employee = "Shark Boss",
		Employees = 4,
		Bonus = 250000,
	},
	{
		Template = "Pack",
		Gradient = "Executive",
		Key = "Executive",
		Kind = "Product",
		Id = 0,
		Price = 999,
		Title = "Executive Pack!",
		Subtitle = "8 desks + 8 workers",
		Description = "8 Galaxy desks, 8 MrBossys and $1.5M!",
		Variant = "Galaxy",
		Contents = { { Variant = "Galaxy", Sets = 8 } },
		Employee = "MrBossy",
		Employees = 8,
		Bonus = 1500000,
	},
	{
		Template = "Pack",
		Gradient = "CEO",
		Key = "CEO",
		Kind = "Product",
		Id = 0,
		Price = 2999,
		Title = "CEO Pack!",
		Subtitle = "24 desks + 16 workers",
		Description = "24 Galaxy desks, 16 Mr Moneys and $8M!",
		Variant = "Galaxy",
		Contents = { { Variant = "Galaxy", Sets = 24 } },
		Employee = "Mr Money",
		Employees = 16,
		Bonus = 8000000,
	},

	--> Everyone in the server gets it and the buyer's name goes on the banner. One row: it
	--> always offers the tier above whatever the server is running.
	{
		Template = "Feature",
		Anchor = "Luck",
		Key = "ServerLuck",
		Title = "Server Luck!",
		Description = "Boosts server luck & employee rolling!",
		Icon = Icons.Clover,
		Tiers = {
			{ Key = "Luck2", Id = 0, Price = 49, Multiplier = 2, Minutes = 10 },
			{ Key = "Luck3", Id = 0, Price = 99, Multiplier = 3, Minutes = 15 },
			{ Key = "Luck5", Id = 0, Price = 249, Multiplier = 5, Minutes = 20 },
			{ Key = "Luck8", Id = 0, Price = 599, Multiplier = 8, Minutes = 30 },
		},
	},

	{ Template = "Header", Anchor = "Passes", Title = "Passes" },
	{
		Template = "Card",
		Key = "Sprint",
		Kind = "Pass",
		Id = 0,
		Price = 25,
		Title = "Sprint Shoes",
		Description = "Walk 2.5x faster!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Key = "FastSpin",
		Kind = "Pass",
		Id = 0,
		Price = 49,
		Title = "Fast Spin",
		Description = "Rolls land 2x faster!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Key = "AutoRoll",
		Kind = "Pass",
		Id = 0,
		Price = 149,
		Title = "Auto Roll",
		Description = "Your pads roll themselves!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Key = "LuckyRoller",
		Kind = "Pass",
		Id = 0,
		Price = 199,
		Title = "Lucky Roller",
		Description = "2x luck, forever!",
		Icon = Icons.Clover,
	},
	{
		Template = "Card",
		Key = "VIP",
		Kind = "Pass",
		Id = 0,
		Price = 399,
		Title = "VIP",
		Description = "+25% cash, a day of income, +1 pad & the VIP tag!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Key = "GravCoil",
		Kind = "Pass",
		Id = 0,
		Price = 79,
		Title = "Grav Coil",
		Description = "Jump higher, fall slower!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Key = "Trolley",
		Kind = "Pass",
		Id = 0,
		Price = 99,
		Title = "Trolley",
		Description = "Carry two parts at once!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Key = "Jetpack",
		Kind = "Pass",
		Id = 0,
		Price = 299,
		Title = "Jetpack",
		Description = "Fly around the map!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Key = "Everything",
		Kind = "Pass",
		Id = 0,
		Price = 999,
		Title = "Everything!",
		Description = "Every pass above, 23% off!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Card",
		Gradient = "Founder",
		Key = "Founder",
		Kind = "Pass",
		Id = 0,
		Price = 9999,
		Title = "Founder",
		Description = "Your name on the Founders wall & the Founder tag!",
		Icon = Icons.Trophy,
	},

	{ Template = "Header", Anchor = "Cash", Title = "Cash" },
	--> The ladder as one card: whichever rung is next, at its price.
	{
		Template = "Card",
		Key = "Ladder",
		Title = "Cash Multiplier",
		Icon = Icons.Cash,
		Rungs = {
			{ Key = "Cash1", Id = 0, Price = 19, Multiplier = 1.5 },
			{ Key = "Cash2", Id = 0, Price = 39, Multiplier = 2 },
			{ Key = "Cash3", Id = 0, Price = 69, Multiplier = 3 },
			{ Key = "Cash4", Id = 0, Price = 99, Multiplier = 4 },
			{ Key = "Cash5", Id = 0, Price = 149, Multiplier = 6 },
			{ Key = "Cash6", Id = 0, Price = 249, Multiplier = 8 },
		},
	},
	{
		Template = "Card",
		Key = "Pad",
		Kind = "Product",
		Id = 0,
		Price = 79,
		Title = "+1 Roll Pad",
		Description = "One more pad, up to 9!",
		Icon = Icons.Ticket,
	},
	--> Time skips: the player's own income for N hours, banked now. The card's number is the cash.
	{
		Template = "CashCard",
		Key = "Skip1h",
		Kind = "Product",
		Id = 0,
		Price = 19,
		Description = "1 hour of income, right now!",
		Icon = Icons.Cash,
		Hours = 1,
	},
	{
		Template = "CashCard",
		Key = "Skip8h",
		Kind = "Product",
		Id = 0,
		Price = 49,
		Description = "8 hours of income, right now!",
		Icon = Icons.Cash,
		Hours = 8,
	},
	{
		Template = "CashCard",
		Key = "Skip1d",
		Kind = "Product",
		Id = 0,
		Price = 99,
		Description = "A day of income, right now!",
		Icon = Icons.Cash,
		Hours = 24,
	},
	{
		Template = "CashCard",
		Key = "Skip3d",
		Kind = "Product",
		Id = 0,
		Price = 249,
		Description = "3 days of income, right now!",
		Icon = Icons.Cash,
		Hours = 72,
	},
}

return {
	Icons = Icons,
	Gradients = Gradients,
	Layout = Layout,
}
