--> High enough to see the rare tail, low enough that the server does not stall on it
local Maximum = 100_000

return {
	Name = "odds",
	Aliases = { "sim" },
	Description = "Draws a pile off the real roll path and prints what landed against what should "
		.. "have. variants rolls part quality and defaults to your own luck; employees rolls the spawn "
		.. "table and defaults to the server's employee luck, since spawns ignore anyone's personal luck.",
	Group = "Admin",
	Args = {
		{
			Type = "rollTable",
			Name = "Table",
			Description = "variants or employees",
		},
		{
			Type = "integer",
			Name = "Rolls",
			Description = `How many to draw, up to {Maximum}`,
			Default = 10_000,
		},
		{
			Type = "number",
			Name = "Luck",
			Description = "Luck to roll at. Defaults to whatever the real path would use",
			Optional = true,
		},
	},
}
