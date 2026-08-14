--> The tier name shown on a rolled item. Tiers are read off the variant alone, because the
--> variant is the axis that actually decides how hard something was to get: a Premium keyboard
--> and a Premium computer took the same 1 in 769,231 to land, they just pay out differently.
--> Ceiling is the rarest "1 in N" a tier still covers, so a variant falls into the first tier
--> its odds fit inside. Odds come off the plain table, never the player's luck, or a luck
--> potion would quietly rename everything they own.
--> The ceilings widen faster than the variant ladder does, so each tier holds two or three
--> variants rather than one tier swallowing the whole rare end. They are spaced off the
--> ladder in Parts, so moving a variant's odds across a ceiling renames it: check both.

local Rarities = {
	--> Commonest first, the lookup walks it front to back. The last ceiling is open ended.
	Tiers = {
		{ Name = "Common", Ceiling = 5, Color = Color3.fromRGB(205, 210, 220) },
		{ Name = "Uncommon", Ceiling = 20, Color = Color3.fromRGB(94, 214, 108) },
		{ Name = "Rare", Ceiling = 100, Color = Color3.fromRGB(78, 158, 255) },
		{ Name = "Epic", Ceiling = 500, Color = Color3.fromRGB(178, 96, 245) },
		{ Name = "Legendary", Ceiling = 10_000, Color = Color3.fromRGB(255, 176, 46) },
		{ Name = "Mythic", Ceiling = 150_000, Color = Color3.fromRGB(255, 78, 90) },
		{ Name = "Divine", Ceiling = math.huge, Color = Color3.fromRGB(96, 240, 232) },
	},
}

--> Odds is the "1 in N" side, never a chance, so 1 in 500 is passed as 500.
function Rarities.Of(Odds: number): (string, Color3)
	for _, Tier in Rarities.Tiers do
		if Odds <= Tier.Ceiling then
			return Tier.Name, Tier.Color
		end
	end

	local Last = Rarities.Tiers[#Rarities.Tiers]

	return Last.Name, Last.Color
end

return Rarities
