return {
	Name = "cash",
	Description = "Adds cash on top of what a player already has. A negative amount takes it away, "
		.. "and it never drops below zero.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Who to pay",
		},
		{
			Type = "number",
			Name = "Amount",
			Description = "How much to add. Negative takes it away",
		},
	},
}
