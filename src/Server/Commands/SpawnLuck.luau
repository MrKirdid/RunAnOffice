return {
	Name = "spawnluck",
	Aliases = { "serverluck" },
	Description = "Sets the luck every employee spawn rolls at, for the whole server rather than one "
		.. "player. 1 is the plain table, 2 doubles the rarest odds, 0 kills them. Not saved, so it "
		.. "resets when the server does. Only employee spawns read it today.",
	Group = "Admin",
	Args = {
		{
			Type = "number",
			Name = "Amount",
			Description = "The multiplier to set it to",
		},
	},
}
