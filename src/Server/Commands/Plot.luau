return {
	Name = "plot",
	Aliases = { "toplot" },
	Description = "Puts players back on their own plot's spawn. The way out of falling through the "
		.. "map, and the fast way back after wandering off to look at something.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Who to send home",
		},
	},
}
