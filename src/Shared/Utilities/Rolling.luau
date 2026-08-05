local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Parts = require(Shared.Configs.Parts)

export type Result = { Variant: string, Component: string }
export type Desk = { Computer: string, Keyboard: string, Monitor: string }

type Entries = { [string]: { Value: number, Rarity: number } }
type Weights = { Names: { string }, Total: number, Scarcity: { [string]: number } }

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
	local Commonest, Rarest = 0, math.huge

	for _, Name in Names do
		local Rarity = Entries[Name].Rarity

		Total += Rarity
		Commonest = math.max(Commonest, Rarity)
		Rarest = math.min(Rarest, Rarity)
	end

	--> Scarcity runs from 0 for the commonest entry to 1 for the rarest, on a log scale so
	--> the tiers in between sit evenly apart. Luck is raised to it, which means luck 2
	--> doubles the rarest entry's weight, leaves the commonest alone, and slides everything
	--> between the two in proportion to how rare it already was.
	local Span = math.log(Commonest / Rarest)
	local Scarcity = {}

	for _, Name in Names do
		Scarcity[Name] = if Span > 0 then math.log(Commonest / Entries[Name].Rarity) / Span else 0
	end

	return { Names = Names, Total = Total, Scarcity = Scarcity }
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

--> Negative luck would raise a negative base to a fractional power and hand back NaN, so the
--> floor is clamped instead of trusted. Luck 0 collapses the table onto its commonest entry.
local function Clamp(Luck: number?): number
	return if Luck then math.max(Luck, 0) else 1
end

local Rolling = {}

--> Generator is optional so the caller can pass a seeded Random and have both sides
--> land on the same result. Left out, each context rolls off its own stream.
function Rolling.Pick(Entries: Entries, Luck: number?, Generator: Random?): string
	local Weights = GetWeights(Entries)
	local Names = Weights.Names
	local Stream = Generator or Default
	local Effective = Clamp(Luck)

	--> Plain luck is the common case and skips the reweighting entirely
	if Effective == 1 then
		local Roll = Stream:NextNumber() * Weights.Total

		for _, Name in Names do
			Roll -= Entries[Name].Rarity
			if Roll <= 0 then
				return Name
			end
		end

		--> Floating point drift can leave Roll a hair above zero after the last subtraction
		return Names[#Names]
	end

	local Scarcity = Weights.Scarcity
	local Total = 0

	for _, Name in Names do
		Total += Entries[Name].Rarity * Effective ^ Scarcity[Name]
	end

	local Roll = Stream:NextNumber() * Total

	for _, Name in Names do
		Roll -= Entries[Name].Rarity * Effective ^ Scarcity[Name]
		if Roll <= 0 then
			return Name
		end
	end

	return Names[#Names]
end

--> The odds each entry actually lands on at a given luck, for readouts and tuning.
function Rolling.Chances(Entries: Entries, Luck: number?): { [string]: number }
	local Weights = GetWeights(Entries)
	local Scarcity = Weights.Scarcity
	local Effective = Clamp(Luck)

	local Chances = {}
	local Total = 0

	for _, Name in Weights.Names do
		local Weight = Entries[Name].Rarity * Effective ^ Scarcity[Name]

		Chances[Name] = Weight
		Total += Weight
	end

	for Name, Weight in Chances do
		Chances[Name] = Weight / Total
	end

	return Chances
end

function Rolling.RollOne(Luck: number?, Generator: Random?): Result
	return {
		Variant = Rolling.Pick(Parts.Variants, Luck, Generator),
		Component = Rolling.Pick(Parts.BaseValues, Luck, Generator),
	}
end

--> Just the variant, for blur frames that already know which component they are showing.
function Rolling.RollVariant(Luck: number?, Generator: Random?): string
	return Rolling.Pick(Parts.Variants, Luck, Generator)
end

--> A roll fills a whole desk, so each of the three components draws its own variant.
--> The component itself is no longer picked, only how good each one turns out.
function Rolling.RollDesk(Luck: number?, Generator: Random?): Desk
	return {
		Computer = Rolling.Pick(Parts.Variants, Luck, Generator),
		Keyboard = Rolling.Pick(Parts.Variants, Luck, Generator),
		Monitor = Rolling.Pick(Parts.Variants, Luck, Generator),
	}
end

--> Slots are zero based to match the networked map, which is keyed [0..16].
function Rolling.Roll(Count: number, Luck: number?, Generator: Random?): { [number]: Desk }
	local Results = {}
	for Slot = 0, Count - 1 do
		Results[Slot] = Rolling.RollDesk(Luck, Generator)
	end

	return Results
end

return Rolling
