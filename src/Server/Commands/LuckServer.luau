local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)
local Parts = require(Shared.Configs.Parts)
local Rolling = require(Shared.Utilities.Rolling)

--> The rarest variant is the one luck moves the most, so its odds are the honest readout of what
--> the number actually bought.
local Rarest = nil :: string?
for Name, Entry in Parts.Variants do
	if not Rarest or Entry.Rarity < Parts.Variants[Rarest].Rarity then
		Rarest = Name
	end
end

return function(_Context, Targets: { Player }, Amount: number): string
	return CommandUtil.ForEach(Targets, function(_Target: Player, Data: any): string
		local Old = Data.Luck()
		local New = Data.Luck(math.max(Amount, 0))

		--> Luck 0 leaves the rare end with no weight at all, which has no "1 in N" to print
		local Chance = Rolling.Chances(Parts.Variants, New)[Rarest]
		local Odds = if Chance > 0 then `1 in {math.floor(1 / Chance + 0.5)}` else "never"

		return `luck {Old} -> {New} ({Rarest} {Odds}).`
	end)
end
