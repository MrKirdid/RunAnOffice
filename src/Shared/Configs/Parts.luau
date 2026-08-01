--> Rarity is a relative weight in parts-per-million. Each group sums to 1_000_000,
--> so a weight doubles as the raw chance and the "1 in N" comments stay honest.
--> Variants step ~1.42x rarer per tier, so every one stays realistically farmable.

return {
	BaseValues = {
		Keyboard = {
			Value = 1,
			Rarity = 500_000, -- 1 in 2
		},
		Monitor = {
			Value = 1.5,
			Rarity = 330_000, -- 1 in 3
		},
		Computer = {
			Value = 3,
			Rarity = 170_000, -- 1 in 5.9
		},
	},
	Variants = {
		Mossy = {
			Value = 4,
			Rarity = 297_000, -- 1 in 3.4
		},

		Wooden = {
			Value = 6,
			Rarity = 209_000, -- 1 in 4.8
		},

		Tree = {
			Value = 8,
			Rarity = 147_000, -- 1 in 6.8
		},

		Coral = {
			Value = 12,
			Rarity = 104_000, -- 1 in 9.6
		},

		Cloudy = {
			Value = 16,
			Rarity = 73_000, -- 1 in 14
		},

		Kitty = {
			Value = 22,
			Rarity = 51_500, -- 1 in 19
		},

		Emotional = {
			Value = 30,
			Rarity = 36_000, -- 1 in 28
		},

		DigCraft = {
			Value = 40,
			Rarity = 25_500, -- 1 in 39
		},

		Tokyo = {
			Value = 55,
			Rarity = 18_000, -- 1 in 56
		},

		Steampunk = {
			Value = 75,
			Rarity = 12_600, -- 1 in 79
		},

		Witch = {
			Value = 100,
			Rarity = 8_900, -- 1 in 112
		},

		Wizzard = {
			Value = 135,
			Rarity = 6_300, -- 1 in 159
		},

		Space = {
			Value = 180,
			Rarity = 4_400, -- 1 in 227
		},

		Galaxy = {
			Value = 240,
			Rarity = 3_100, -- 1 in 323
		},

		Hardcore = {
			Value = 320,
			Rarity = 2_200, -- 1 in 455
		},

		Premium = {
			Value = 450,
			Rarity = 1_500, -- 1 in 667
		},
	},
}
