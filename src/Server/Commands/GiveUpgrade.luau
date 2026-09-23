return {
	Name = "giveupgrade",
	Aliases = { "upgrade" },
	Description = "Hands a player a node of the upgrade tree for free, running its effect exactly like "
		.. "a purchase would, but with no price and no parent to buy first. 'all' grants the whole tree "
		.. "in order, which is the quick way to a maxed save.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Who to give it to",
		},
		{
			Type = "upgrade",
			Name = "Upgrade",
			Description = "Which node, or 'all' for the whole tree",
		},
	},
}
