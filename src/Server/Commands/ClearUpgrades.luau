return {
	Name = "clearupgrades",
	Description = "Unowns every node of the upgrade tree and puts the numbers they moved back where a "
		.. "fresh save has them: multipliers to 1, defense to 0, pads to 9. Luck and cash are left "
		.. "alone, since plenty besides the tree touches those.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose tree to reset",
		},
	},
}
