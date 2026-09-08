return {
	Name = "grantproduct",
	Description = "Hands a player a shop product or gamepass by its key in Configs.Products, exactly as a "
		.. "real purchase would, without Robux changing hands. For testing the store.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Who gets it",
		},
		{
			Type = "string",
			Name = "Key",
			Description = "The product key: Sprint, VIP, Cash1, Pad, Skip1h, Luck2, Pro, Starter ...",
		},
	},
}
