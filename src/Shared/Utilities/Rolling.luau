local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Parts = require(Shared.Configs.Parts)

export type Result = { Variant: string, Component: string }

type Entries = { [string]: { Value: number, Rarity: number } }
type Weights = { Names: { string }, Total: number }

local Default = Random.new()

--> Dictionary iteration order is an implementation detail, so the pick order is frozen
--> once per entry table. That also saves resumming the weights on every roll.
local function Weigh(Entries: Entries): Weights
	local Names = {}
	for Name in Entries do
		table.insert(Names, Name)
	end

	if #Names == 0 then
		error("No entries to roll from")
	end

	table.sort(Names)

	local Total = 0
	for _, Name in Names do
		Total += Entries[Name].Rarity
	end

	return { Names = Names, Total = Total }
end

local Cache: { [Entries]: Weights } = {}

local function GetWeights(Entries: Entries): Weights
	local Cached = Cache[Entries]
	if not Cached then
		Cached = Weigh(Entries)
		Cache[Entries] = Cached
	end

	return Cached
end

local Rolling = {}

--> Generator is optional so the caller can pass a seeded Random and have both sides
--> land on the same result. Left out, each context rolls off its own stream.
function Rolling.Pick(Entries: Entries, Generator: Random?): string
	local Weights = GetWeights(Entries)
	local Names = Weights.Names

	local Roll = (Generator or Default):NextNumber() * Weights.Total
	for _, Name in Names do
		Roll -= Entries[Name].Rarity
		if Roll <= 0 then
			return Name
		end
	end

	--> Floating point drift can leave Roll a hair above zero after the last subtraction
	return Names[#Names]
end

function Rolling.RollOne(Generator: Random?): Result
	return {
		Variant = Rolling.Pick(Parts.Variants, Generator),
		Component = Rolling.Pick(Parts.BaseValues, Generator),
	}
end

--> Slots are zero based to match the networked map, which is keyed [0..16].
function Rolling.Roll(Count: number, Generator: Random?): { [number]: Result }
	local Results = {}
	for Slot = 0, Count - 1 do
		Results[Slot] = Rolling.RollOne(Generator)
	end

	return Results
end

return Rolling
