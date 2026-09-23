local Maximum = 25

return {
	Name = "spawnnpcs",
	Aliases = { "spawnnpc", "npc" },
	Description = "Drops employees at the map's spawn marker right now instead of waiting out the "
		.. "timer, so you can walk over and buy the one you want. Name a type to skip the roll.",
	Group = "Admin",
	Args = {
		{
			Type = "integer",
			Name = "Amount",
			Description = `How many, 1 to {Maximum}`,
			Default = 1,
		},
		{
			Type = "employeeType",
			Name = "Type",
			Description = "Which one. Rolled off the table when left out",
			Optional = true,
		},
	},
}
