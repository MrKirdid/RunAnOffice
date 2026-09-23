--> Roll slots go over the wire as a u8 of 0 to 16, so seventeen pads is the ceiling however many
--> the tree hands out.
local Maximum = 17

return {
	Name = "rolls",
	Description = "Sets how many reroll pads a player has unlocked, 1 to 17. Set outright rather than "
		.. "added, so 'rolls me' is the whole row every time.",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Whose pads to set",
		},
		{
			Type = "integer",
			Name = "Amount",
			Description = `How many pads, 1 to {Maximum}`,
			Default = Maximum,
		},
	},
}
