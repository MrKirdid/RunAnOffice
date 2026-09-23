return {
	Name = "floors",
	Aliases = { "floor" },
	Description = "Sets how many floors of a plot are unlocked. Opens everything up to the number and "
		.. "closes everything above it, so 'floors me 1' takes a tower back down to the ground floor "
		.. "and the desks standing on the removed ones go with them.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose plot to resize",
		},
		{
			Type = "integer",
			Name = "Count",
			Description = "How many floors should be unlocked",
		},
	},
}
