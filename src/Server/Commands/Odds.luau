local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local EmployeeService = require(Server.Services.EmployeeService)
local PlayerData = require(Shared.PlayerData).server
local Employees = require(Shared.Configs.Employees)
local Rolling = require(Shared.Utilities.Rolling)
local Parts = require(Shared.Configs.Parts)

local Types = Kmdr.types

--> High enough to see the rare tail, low enough that the server does not stall on it
local Maximum = 100_000

local function Sorted(Entries: { [string]: { Value: number } }): { string }
	local Names = {}

	for Name in Entries do
		table.insert(Names, Name)
	end

	table.sort(Names, function(Left: string, Right: string)
		return Entries[Left].Value < Entries[Right].Value
	end)

	return Names
end

local Definition = Kmdr.defineCommand({
	name = "odds",
	aliases = { "sim" },
	description = "Draws a pile off the real roll path and prints what landed against what should have. "
		.. "variants rolls part quality and defaults to your own luck; employees rolls the spawn table "
		.. "and defaults to the server's employee luck, since spawns ignore anyone's personal luck.",
	group = "admin",
	args = {
		Table = ConsoleTypes.RollTable("variants or employees"),
		Rolls = Types.integer(`How many to draw, up to {Maximum}`),
		Luck = Types.number("Luck to roll at. Defaults to whatever the real path would use"):optional(),
	},
})

return Kmdr.implement(Definition, function(Context, Args)
	local Count = Args.Rolls

	if Count < 1 or Count > Maximum then
		return `Roll count has to be between 1 and {Maximum}.`
	end

	local Variants = Args.Table == "variants"
	local Entries = if Variants then Parts.Variants else Employees

	local Luck = Args.Luck

	if not Luck then
		if Variants then
			local Executor = Context.executor
			local Data = Executor and PlayerData[Executor]

			Luck = (Data and Data.Luck()) or 1
		else
			Luck = EmployeeService:GetSpawnLuck()
		end
	end

	local Tally = {}
	for _ = 1, Count do
		local Name = Rolling.Pick(Entries, Luck)
		Tally[Name] = (Tally[Name] or 0) + 1
	end

	local Chances = Rolling.Chances(Entries, Luck)

	local Lines = {
		`{Count} {Args.Table} at luck {Luck}`,
		string.format("%-13s %8s %9s %9s", "Name", "Hits", "Rolled", "Expected"),
	}

	for _, Name in Sorted(Entries) do
		local Hits = Tally[Name] or 0

		table.insert(
			Lines,
			string.format("%-13s %8d %8.3f%% %8.3f%%", Name, Hits, Hits / Count * 100, Chances[Name] * 100)
		)
	end

	return table.concat(Lines, "\n")
end)
