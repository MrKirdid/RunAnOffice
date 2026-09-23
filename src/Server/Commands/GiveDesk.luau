local Maximum = 50

return {
	Name = "givedesk",
	Aliases = { "desk" },
	Description = "Drops desks into the next free slots of a plot, rolling their three parts exactly "
		.. "like a purchase would unless a variant is named. Stops early and says so when the unlocked "
		.. "floors run out.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose plot to fill",
		},
		{
			Type = "integer",
			Name = "Amount",
			Description = `How many desks, 1 to {Maximum}`,
			Default = 1,
		},
		{
			Type = "variant",
			Name = "Variant",
			Description = "Force all three parts to this variant",
			Optional = true,
		},
	},
}
