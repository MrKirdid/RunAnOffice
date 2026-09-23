return {
	Name = "luck",
	Description = "Sets a player's luck outright. 1 is the plain table, 2 doubles the rarest chance, "
		.. "0 kills the rare end entirely. Every roll in the game reads it: parts, desks and hires.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose luck to set",
		},
		{
			Type = "number",
			Name = "Amount",
			Description = "The multiplier to set it to",
		},
	},
}
