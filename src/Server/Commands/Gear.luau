return {
	Name = "gear",
	Description = "Hands a player a gear from Configs.Gears for nothing and puts it in their backpack.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Who gets it",
		},
		{
			Type = "gear",
			Name = "Key",
			Description = "The gear's key in Configs.Gears",
		},
	},
}
