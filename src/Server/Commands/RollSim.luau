local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)
local Parts = require(Shared.Configs.Parts)

local Types = Kmdr.types

--> High enough to see the rare tail, low enough that the server does not stall on it
local Maximum = 100_000

--> Cheapest first, so the table reads as the rarity ladder
local Order = {}
for Name in Parts.Variants do
	table.insert(Order, Name)
end

table.sort(Order, function(Left: string, Right: string)
	return Parts.Variants[Left].Value < Parts.Variants[Right].Value
end)

local Definition = Kmdr.defineCommand({
	name = "rollsim",
	aliases = { "odds" },
	description = "Draws a pile of variants off the real roll path and prints what landed against what should have.",
	group = "admin",
	args = {
		Rolls = Types.integer("How many variants to draw"),
		Luck = Types.number("Luck to roll at, defaults to your own"):optional(),
	},
})

return Kmdr.implement(Definition, function(Context, Args)
	local Count = Args.Rolls

	if Count < 1 or Count > Maximum then
		return `Roll count has to be between 1 and {Maximum}.`
	end

	local Executor = Context.executor
	local Data = Executor and PlayerData[Executor]
	local Luck = Args.Luck or (Data and Data.Luck()) or 1

	local Tally = {}
	for _ = 1, Count do
		local Variant = Rolling.RollVariant(Luck)
		Tally[Variant] = (Tally[Variant] or 0) + 1
	end

	local Chances = Rolling.Chances(Parts.Variants, Luck)

	local Lines = {
		`{Count} rolls at luck {Luck}`,
		string.format("%-10s %8s %9s %9s", "Variant", "Hits", "Rolled", "Expected"),
	}

	for _, Name in Order do
		local Hits = Tally[Name] or 0

		table.insert(
			Lines,
			string.format("%-10s %8d %8.3f%% %8.3f%%", Name, Hits, Hits / Count * 100, Chances[Name] * 100)
		)
	end

	return table.concat(Lines, "\n")
end)
