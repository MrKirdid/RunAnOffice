local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local CommandUtil = require(Shared.Console.CommandUtil)
local Employees = require(Shared.Configs.Employees)
local EmployeeService = require(Server.Services.EmployeeService)
local Parts = require(Shared.Configs.Parts)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)

local Pad = CommandUtil.Pad

local Maximum = 100_000

local function Sorted(Entries: { [string]: { Value: number, [string]: any } }): { string }
	local Names = {}

	for Name in Entries do
		table.insert(Names, Name)
	end

	table.sort(Names, function(Left: string, Right: string)
		return Entries[Left].Value < Entries[Right].Value
	end)

	return Names
end

local function Percent(Fraction: number): string
	return math.floor(Fraction * 100_000 + 0.5) / 1000 .. "%"
end

return function(Context, Table: string, Rolls: number, Luck: number?): string
	if Rolls < 1 or Rolls > Maximum then
		return `Roll count has to be between 1 and {Maximum}.`
	end

	local Variants = Table == "variants"
	local Entries = if Variants then Parts.Variants else Employees

	local At = Luck

	if not At then
		if Variants then
			local Executor = Context.Executor
			local Data = Executor and PlayerData[Executor]

			At = (Data and Data.Luck()) or 1
		else
			At = EmployeeService:GetSpawnLuck()
		end
	end

	local Tally = {}
	for _ = 1, Rolls do
		local Name = Rolling.Pick(Entries, At)
		Tally[Name] = (Tally[Name] or 0) + 1
	end

	local Chances = Rolling.Chances(Entries, At)

	local Lines = {
		`{Rolls} {Table} at luck {At}`,
		Pad("Name", 14) .. Pad("Hits", 9) .. Pad("Rolled", 11) .. "Expected",
	}

	for _, Name in Sorted(Entries) do
		local Hits = Tally[Name] or 0

		table.insert(
			Lines,
			Pad(Name, 14) .. Pad(tostring(Hits), 9) .. Pad(Percent(Hits / Rolls), 11) .. Percent(Chances[Name])
		)
	end

	return table.concat(Lines, "\n")
end
