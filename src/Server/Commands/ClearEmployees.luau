return {
	Name = "clearemployees",
	Aliases = { "fire" },
	Description = "Empties every seat a player owns and leaves the desks standing, so the same plot "
		.. "can be seated again without rebuilding it.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose seats to empty",
		},
	},
}
