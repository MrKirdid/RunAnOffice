--> The shop, top to bottom. Every entry names the template in ShopUI's Templates folder it is
--> drawn with, and the fields that template reads. ShopController walks this list in order and
--> nothing about a product is drawn into the place, so adding a gamepass, a pack or a luck tier
--> is adding an entry here. MonetizationService grants off the same entries, by Key.

--> Templates:
--> Header   a section title. Title, and an Anchor if a rail button jumps here.
--> Card     half a row: Icon, Title, Description, one price button. Cards are paired two to a
-->          row automatically; an odd one leaves the other half empty.
--> Feature  a full row with a big icon, Title, Subtitle, Description and one price button.
--> Ladder   the cash multiplier: six Rungs drawn as steps, only the next one for sale.

--> Ids are the Creator Hub ids. A 0 is a product not made there yet; the shop shows Price as a
--> stand-in until it is, and once the id is real the number on the button comes from Roblox
--> through GetProductInfo -- that is what lets Managed Pricing test prices.

export type Kind = "Pass" | "Product"

export type DeskSet = {
	Variant: string,
	Sets: number,
}

export type Entry = {
	Template: string,
	--> the gradient every card in this stretch is painted with, by name in Gradients below
	Gradient: string?,
	--> a rail button of this name scrolls to this row
	Anchor: string?,

	Key: string?,
	Kind: Kind?,
	Id: number?,
	Price: number?,
	Title: string?,
	Subtitle: string?,
	Description: string?,
	Icon: string?,

	--> sold once per account; the row goes away once OwnedProducts has it
	Once: boolean?,

	--> Card only. Hours turns the description into the cash that many hours of income is worth
	--> right now, and Variant draws the computer of that part set as the icon.
	Hours: number?,
	Variant: string?,

	--> What the server hands out. Server luck: Multiplier for Minutes. A pack: desk sets, and
	--> Employees of one Employee type sat at the seats they make.
	Multiplier: number?,
	Minutes: number?,
	Contents: { DeskSet }?,
	Employee: string?,
	Employees: number?,

	--> Ladder only
	Rungs: { Rung }?,
}

export type Rung = {
	Key: string,
	Id: number,
	Price: number,
	Multiplier: number,
}

--> Placeholder art already in the place, until every product has its own icon.
local Icons = {
	Trophy = "rbxassetid://73898620648802",
	Clover = "rbxassetid://78045260176458",
	Ticket = "rbxassetid://109116277315334",
	Cash = "rbxassetid://139241177703025",
}

local Gradients: { [string]: { Color3 } } = {
	Passes = { Color3.fromRGB(141, 229, 249), Color3.fromRGB(63, 192, 246) },
	Gears = { Color3.fromRGB(236, 121, 234), Color3.fromRGB(178, 73, 236) },
	Cash = { Color3.fromRGB(165, 255, 163), Color3.fromRGB(73, 255, 103) },
	Luck = { Color3.fromRGB(211, 247, 13), Color3.fromRGB(7, 253, 0) },
	Packs = { Color3.fromRGB(245, 207, 81), Color3.fromRGB(242, 167, 67) },
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
	--> Packs: desk sets and nothing else. The starter sits at the top for the day it is on offer.
	{
		Template = "Feature",
		Gradient = "Packs",
		Anchor = "Packs",
		Key = "Starter",
		Kind = "Product",
		Id = 0,
		Price = 49,
		Once = true,
		Title = "Starter Pack!",
		Subtitle = "First 24 hours only!",
		Description = "2 Steampunk desks + 2 Hamsters!",
		Variant = "Steampunk",
		Contents = { { Variant = "Steampunk", Sets = 2 } },
		Employee = "Hamster",
		Employees = 2,
	},

	{ Template = "Header", Anchor = "Passes", Title = "Passes" },
	{
		Template = "Card",
		Gradient = "Passes",
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
		Gradient = "Passes",
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
		Gradient = "Passes",
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
		Gradient = "Passes",
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
		Gradient = "Passes",
		Key = "VIP",
		Kind = "Pass",
		Id = 0,
		Price = 399,
		Title = "VIP",
		Description = "+25% cash, a day of income, +1 pad, VIP tag & Golden Coil!",
		Icon = Icons.Trophy,
	},
	{
		Template = "Feature",
		Gradient = "Packs",
		Key = "Everything",
		Kind = "Pass",
		Id = 0,
		Price = 999,
		Title = "Everything!",
		Subtitle = "23% off, one tap",
		Description = "Every pass and every gear. 1,298 apart!",
		Icon = Icons.Trophy,
	},

	{ Template = "Header", Title = "Gears" },
	{
		Template = "Card",
		Gradient = "Gears",
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
		Gradient = "Gears",
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
		Gradient = "Gears",
		Key = "Jetpack",
		Kind = "Pass",
		Id = 0,
		Price = 299,
		Title = "Jetpack",
		Description = "Fly around the map!",
		Icon = Icons.Trophy,
	},

	{ Template = "Header", Anchor = "Cash", Title = "Cash" },
	{
		Template = "Ladder",
		Gradient = "Cash",
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
	--> Time skips: the player's own income for N hours, banked now. The card says it in cash.
	{
		Template = "Card",
		Gradient = "Cash",
		Key = "Skip1h",
		Kind = "Product",
		Id = 0,
		Price = 19,
		Title = "1 Hour",
		Icon = Icons.Cash,
		Hours = 1,
	},
	{
		Template = "Card",
		Gradient = "Cash",
		Key = "Skip8h",
		Kind = "Product",
		Id = 0,
		Price = 49,
		Title = "8 Hours",
		Icon = Icons.Cash,
		Hours = 8,
	},
	{
		Template = "Card",
		Gradient = "Cash",
		Key = "Skip1d",
		Kind = "Product",
		Id = 0,
		Price = 99,
		Title = "1 Day",
		Icon = Icons.Cash,
		Hours = 24,
	},
	{
		Template = "Card",
		Gradient = "Cash",
		Key = "Skip3d",
		Kind = "Product",
		Id = 0,
		Price = 249,
		Title = "3 Days",
		Icon = Icons.Cash,
		Hours = 72,
	},
	{
		Template = "Card",
		Gradient = "Cash",
		Key = "Pad",
		Kind = "Product",
		Id = 0,
		Price = 79,
		Title = "+1 Roll Pad",
		Description = "One more pad, up to 9!",
		Icon = Icons.Ticket,
	},

	--> Everyone in the server gets it and the buyer's name goes on the banner.
	{ Template = "Header", Anchor = "Luck", Title = "Server Luck" },
	{
		Template = "Card",
		Gradient = "Luck",
		Key = "Luck2",
		Kind = "Product",
		Id = 0,
		Price = 49,
		Title = "2x Luck",
		Description = "10 minutes, whole server!",
		Icon = Icons.Clover,
		Multiplier = 2,
		Minutes = 10,
	},
	{
		Template = "Card",
		Gradient = "Luck",
		Key = "Luck3",
		Kind = "Product",
		Id = 0,
		Price = 99,
		Title = "3x Luck",
		Description = "15 minutes, whole server!",
		Icon = Icons.Clover,
		Multiplier = 3,
		Minutes = 15,
	},
	{
		Template = "Card",
		Gradient = "Luck",
		Key = "Luck5",
		Kind = "Product",
		Id = 0,
		Price = 249,
		Title = "5x Luck",
		Description = "20 minutes, whole server!",
		Icon = Icons.Clover,
		Multiplier = 5,
		Minutes = 20,
	},
	{
		Template = "Card",
		Gradient = "Luck",
		Key = "Luck8",
		Kind = "Product",
		Id = 0,
		Price = 599,
		Title = "8x Luck",
		Description = "30 minutes, whole server!",
		Icon = Icons.Clover,
		Multiplier = 8,
		Minutes = 30,
	},

	{ Template = "Header", Title = "Packs" },
	{
		Template = "Card",
		Gradient = "Packs",
		Key = "Pro",
		Kind = "Product",
		Id = 0,
		Price = 399,
		Title = "Pro Pack",
		Description = "4 Space desks + 4 Shark Boss!",
		Variant = "Space",
		Contents = { { Variant = "Space", Sets = 4 } },
		Employee = "Shark Boss",
		Employees = 4,
	},
	{
		Template = "Card",
		Gradient = "Packs",
		Key = "Executive",
		Kind = "Product",
		Id = 0,
		Price = 999,
		Title = "Executive Pack",
		Description = "8 Galaxy desks + 8 MrBossy!",
		Variant = "Galaxy",
		Contents = { { Variant = "Galaxy", Sets = 8 } },
		Employee = "MrBossy",
		Employees = 8,
	},
	{
		Template = "Card",
		Gradient = "Packs",
		Key = "CEO",
		Kind = "Product",
		Id = 0,
		Price = 2999,
		Title = "CEO Pack",
		Description = "16 Galaxy + 8 Space desks + 16 Mr Money!",
		Variant = "Galaxy",
		Contents = { { Variant = "Galaxy", Sets = 16 }, { Variant = "Space", Sets = 8 } },
		Employee = "Mr Money",
		Employees = 16,
	},

	--> A name on the wall and a tag nobody else gets. Nothing else, on purpose.
	{
		Template = "Feature",
		Gradient = "Founder",
		Key = "Founder",
		Kind = "Pass",
		Id = 0,
		Price = 9999,
		Title = "Founder",
		Subtitle = "Be seen",
		Description = "Your name on the Founders wall, and the Founder tag!",
		Icon = Icons.Trophy,
	},
}

return {
	Icons = Icons,
	Gradients = Gradients,
	Layout = Layout,
}
