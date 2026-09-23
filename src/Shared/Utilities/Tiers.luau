local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PartConfigs = require(Shared.Configs.Parts)
local Rarities = require(Shared.Configs.Rarities)
local Rolling = require(Shared.Utilities.Rolling)

--> At no luck, which is what a tier is: the name on a part is what that part is, and it does not
--> get rarer because the player who rolled it was unlucky.
local BaseOdds = Rolling.Chances(PartConfigs.Variants, 1)

local Tiers = {}

--> The tier a "1 in N" falls into. Anything past the last ceiling, including odds that could not be
--> worked out at all, lands in the rarest tier rather than the commonest.
function Tiers.FromOdds(Odds: number): (string, Color3)
	for _, Tier in Rarities.Tiers do
		if Odds <= Tier.Ceiling then
			return Tier.Name, Tier.Color
		end
	end

	local Last = Rarities.Tiers[#Rarities.Tiers]

	return Last.Name, Last.Color
end

--> The same thing for a part, off the name of its variant. The odds come back too, since everything
--> that wants the tier of a part tends to want to print the odds beside it.
function Tiers.FromVariant(Variant: string): (string, Color3, number)
	local Chance = BaseOdds[Variant]
	local Odds = if Chance and Chance > 0 then 1 / Chance else math.huge
	local Name, Color = Tiers.FromOdds(Odds)

	return Name, Color, Odds
end

return Tiers
