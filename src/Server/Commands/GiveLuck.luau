local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)
local Parts = require(Shared.Configs.Parts)

local Types = Kmdr.types

--> The rarest variant is the one luck moves the most, so its odds are the honest readout of
--> what the number actually bought.
local Rarest = nil :: string?
for Name, Entry in Parts.Variants do
	if not Rarest or Entry.Rarity < Parts.Variants[Rarest].Rarity then
		Rarest = Name
	end
end

local Definition = Kmdr.defineCommand({
	name = "giveluck",
	aliases = { "luck" },
	description = "Adds luck to a player. Luck 1 is the plain table, 2 doubles the rarest odds, 0 kills them.",
	group = "admin",
	args = {
		Targets = Types.players("The players to bless"),
		Amount = Types.number("How much luck to add, negative to take it away"),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	local Lines = {}

	for _, Target in Args.Targets do
		local Data = PlayerData[Target]

		if not Data then
			table.insert(Lines, `{Target.Name}: no loaded data.`)
			continue
		end

		local Old = Data.Luck()
		local New = Data.Luck(function(Current: number)
			return math.max(Current + Args.Amount, 0)
		end)

		--> Luck 0 leaves the rare end with no weight at all, which has no "1 in N" to print
		local Chance = Rolling.Chances(Parts.Variants, New)[Rarest]
		local Odds = if Chance > 0 then `1 in {math.floor(1 / Chance + 0.5)}` else "never"

		table.insert(Lines, `{Target.Name}: luck {Old} -> {New} ({Rarest} {Odds})`)
	end

	return table.concat(Lines, "\n")
end)
