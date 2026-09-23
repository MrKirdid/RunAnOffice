return {
	Name = "resetdata",
	Description = "Wipes a save outright and kicks whoever it belonged to, so they come back on a " .. "fresh profile.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose save to wipe",
		},
	},
}
