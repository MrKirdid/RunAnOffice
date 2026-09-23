return {
	Name = "tutorial",
	Description = "Puts a player on a step of the tutorial, 1 for the first. One past the last step "
		.. "marks it done. A step the save already satisfies is passed again at once, so a "
		.. "replay from the top wants resetdata first.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose tutorial",
		},
		{
			Type = "integer",
			Name = "Stage",
			Description = "The step to put them on",
		},
	},
}
