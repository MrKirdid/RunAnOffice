local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rarities = require(Shared.Configs.Rarities)

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

return Tiers
