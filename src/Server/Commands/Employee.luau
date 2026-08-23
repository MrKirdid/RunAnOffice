local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local EmployeeService = require(Server.Services.EmployeeService)
local Employees = require(Shared.Configs.Employees)
local Tiers = require(Shared.Utilities.Tiers)
local Rolling = require(Shared.Utilities.Rolling)

local Types = Kmdr.types

local Maximum = 20

local BaseOdds = Rolling.Chances(Employees, 1)

--> Cheapest first, so the table reads as the ladder
local Order = {}
for Name in Employees do
	table.insert(Order, Name)
end

table.sort(Order, function(Left: string, Right: string)
	return Employees[Left].Value < Employees[Right].Value
end)

local function List(): string
	local Lines = {
		string.format("%-13s %-10s %6s %7s %12s", "Employee", "Tier", "Mult", "Cost", "Odds"),
	}

	for _, Name in Order do
		local Chance = BaseOdds[Name]
		local Odds = if Chance and Chance > 0 then 1 / Chance else math.huge
		local Tier = Tiers.FromOdds(Odds)

		table.insert(
			Lines,
			string.format(
				"%-13s %-10s %5sx %6s %12s",
				Name,
				Tier,
				tostring(Employees[Name].Value),
				"$" .. EmployeeService:GetCost(Name),
				if Odds < math.huge then "1 in " .. math.floor(Odds + 0.5) else "1 in ???"
			)
		)
	end

	return table.concat(Lines, "\n")
end

local Definition = Kmdr.defineCommand({
	name = "employee",
	description = "spawn drops employees at the map's spawn marker right now instead of waiting out the "
		.. "timer, so you do not have to roll for the one you want. list prints the whole ladder with "
		.. "each one's tier, multiplier, cost and odds.",
	group = "admin",
	args = {
		Action = ConsoleTypes.EmployeeAction("spawn some, or list the whole table"),
		Type = ConsoleTypes.EmployeeType("spawn only: which one. Rolled off the table when left out"):optional(),
		Amount = Types.integer(`spawn only: how many, 1 to {Maximum}`):default(1),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	if Args.Action == "list" then
		return List()
	end

	if Args.Amount < 1 or Args.Amount > Maximum then
		return `Amount has to be between 1 and {Maximum}.`
	end

	local Lines = {}

	for _ = 1, Args.Amount do
		local Employee = EmployeeService:RollEmployee(nil, Args.Type)

		EmployeeService:NewEmployee(Employee)
		table.insert(Lines, EmployeeService:Describe(Employee))
	end

	return `Spawned {#Lines}:\n` .. table.concat(Lines, "\n")
end)
