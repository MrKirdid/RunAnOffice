--> Who sits at a desk once one is filled. Keyed by name and shaped like Parts.Variants on
--> purpose, so Rolling.Pick and Rolling.Chances take this table straight: an employee is rolled
--> the same way a component variant is, off the same luck, through the same weights.
--> Rarity is written as the odds themselves, 1 / N, because Rolling divides every weight by the
--> table's total anyway: the numbers only ever have to be right relative to each other, so
--> there is nothing to be gained by scaling them up into a sum that has to be maintained.
--> The total lands at 0.9889 rather than a clean 1, which is the whole error: every entry is
--> about 1.1% commoner than the N it is written as. Adding an entry eats into that, so a new
--> hire wants a slot the ladder already has room for rather than being wedged in anywhere.
--> Deliberately a much shorter ladder than the variant one: 1 in 2 to 1 in 5,000 rather than
--> out to 1 in 769,231. Employees spawn on a timer instead of per pad, so the whole table has
--> to be reachable in a session, and the rungs sit ~1.6x apart the whole way up rather than
--> pulling wider as they climb. Nothing here is a months long chase.
--> Value is the multiplier the employee puts on the desk they are sat at, running 1x at the
--> bottom to 5x at the top. It climbs slower than the odds do, which is the point: the ladder
--> is a chase, not a payout curve, and a Founder is worth five Interns rather than 2,500.
--> Because the ladder stops at 1 in 5,000, the tiers in Configs/Rarities only reach Legendary
--> and the top five entries all land in it. Those ceilings were spaced off the variant ladder,
--> so employees want their own ceilings before any of this prints a tier name.
--> There is no sort order field: sorting by Rarity descending is the ladder.

return {
	Intern = {
		Value = 1,
		Rarity = 1 / 2,
	},

	Temp = {
		Value = 1.15,
		Rarity = 1 / 5,
	},

	Janitor = {
		Value = 1.3,
		Rarity = 1 / 9,
	},

	Assistant = {
		Value = 1.45,
		Rarity = 1 / 15,
	},

	Receptionist = {
		Value = 1.6,
		Rarity = 1 / 25,
	},

	Analyst = {
		Value = 1.8,
		Rarity = 1 / 40,
	},

	Engineer = {
		Value = 2,
		Rarity = 1 / 60,
	},

	Accountant = {
		Value = 2.2,
		Rarity = 1 / 90,
	},

	Manager = {
		Value = 2.45,
		Rarity = 1 / 140,
	},

	Consultant = {
		Value = 2.7,
		Rarity = 1 / 220,
	},

	Director = {
		Value = 3,
		Rarity = 1 / 350,
	},

	Executive = {
		Value = 3.3,
		Rarity = 1 / 600,
	},

	Partner = {
		Value = 3.6,
		Rarity = 1 / 1_000,
	},

	President = {
		Value = 4,
		Rarity = 1 / 1_800,
	},

	CEO = {
		Value = 4.5,
		Rarity = 1 / 3_000,
	},

	Founder = {
		Value = 5,
		Rarity = 1 / 5_000,
	},
}
