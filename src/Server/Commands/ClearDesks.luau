return {
	Name = "cleardesks",
	Description = "Strips every desk out of a plot, employees and all, leaving the floors themselves "
		.. "unlocked. The fast way back to an empty plot without wiping the save.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose plot to strip",
		},
	},
}
