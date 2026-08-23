local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Parts = require(Shared.Configs.Parts)

export type Result = { Variant: string, Component: string }
export type Desk = { Computer: string, Keyboard: string, Monitor: string }

type Entries = { [string]: { Value: number, Rarity: number } }
type Weights = { Names: { string }, Total: number, Scarcity: { [string]: number } }

local Default = Random.new()

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

	local Span = math.log(Commonest / Rarest)
	local Scarcity = {}

	for _, Name in Names do
		Scarcity[Name] = if Span > 0 then math.log(Commonest / Entries[Name].Rarity) / Span else 0
	end

	return { Names = Names, Total = Total, Scarcity = Scarcity }
end

--> Weak keyed: callers pass filtered tables that would otherwise pile up here per roll.
local Cache: { [Entries]: Weights } = setmetatable({}, { __mode = "k" }) :: any

local function GetWeights(Entries: Entries): Weights
	local Cached = Cache[Entries]
	if not Cached then
		Cached = Weigh(Entries)
		Cache[Entries] = Cached
	end

	return Cached
end

local function Clamp(Luck: number?): number
	return if Luck then math.max(Luck, 0) else 1
end

local Rolling = {}

function Rolling.Pick(Entries: Entries, Luck: number?, Generator: Random?): string
	local Weights = GetWeights(Entries)
	local Names = Weights.Names
	local Stream = Generator or Default
	local Effective = Clamp(Luck)

	if Effective == 1 then
		local Roll = Stream:NextNumber() * Weights.Total

		for _, Name in Names do
			Roll -= Entries[Name].Rarity
			if Roll <= 0 then
				return Name
			end
		end

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

function Rolling.RollVariant(Luck: number?, Generator: Random?): string
	return Rolling.Pick(Parts.Variants, Luck, Generator)
end

function Rolling.RollComponent(Luck: number?, Generator: Random?): string
	return Rolling.Pick(Parts.BaseValues, Luck, Generator)
end

function Rolling.RollDesk(Luck: number?, Generator: Random?): Desk
	return {
		Computer = Rolling.Pick(Parts.Variants, Luck, Generator),
		Keyboard = Rolling.Pick(Parts.Variants, Luck, Generator),
		Monitor = Rolling.Pick(Parts.Variants, Luck, Generator),
	}
end

function Rolling.Roll(Count: number, Luck: number?, Generator: Random?): { [number]: Result }
	local Results = {}
	for Slot = 0, Count - 1 do
		Results[Slot] = Rolling.RollOne(Luck, Generator)
	end

	return Results
end

return Rolling
