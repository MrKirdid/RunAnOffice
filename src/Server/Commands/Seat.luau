local Maximum = 50

return {
	Name = "seat",
	Aliases = { "hire" },
	Description = "Sits employees straight down at the lowest free desks, skipping the walk across the "
		.. "map. The fast way to check seating, the desk offset, the typing animation and revenue.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose desks to seat",
		},
		{
			Type = "integer",
			Name = "Amount",
			Description = `How many to sit down, 1 to {Maximum}`,
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
