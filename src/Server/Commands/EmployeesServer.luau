local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local CommandUtil = require(Shared.Console.CommandUtil)
local Employees = require(Shared.Configs.Employees)
local EmployeeService = require(Server.Services.EmployeeService)
local Rolling = require(Shared.Utilities.Rolling)
local Tiers = require(Shared.Utilities.Tiers)

local BaseOdds = Rolling.Chances(Employees, 1)

local Pad = CommandUtil.Pad

--> Cheapest first, so the table reads as the ladder
local Order = {}
for Name in Employees do
	table.insert(Order, Name)
end

table.sort(Order, function(Left: string, Right: string)
	return Employees[Left].Value < Employees[Right].Value
end)

return function(_Context): string
	local Lines = {
		Pad("Employee", 14) .. Pad("Tier", 11) .. Pad("Mult", 7) .. Pad("Cost", 9) .. "Odds",
	}

	for _, Name in Order do
		local Chance = BaseOdds[Name]
		local Odds = if Chance and Chance > 0 then 1 / Chance else math.huge

		table.insert(
			Lines,
			Pad(Name, 14)
				.. Pad((Tiers.FromOdds(Odds)), 11)
				.. Pad(Employees[Name].Value .. "x", 7)
				.. Pad("$" .. EmployeeService:GetCost(Name), 9)
				.. (if Odds < math.huge then "1 in " .. math.floor(Odds + 0.5) else "1 in ???")
		)
	end

	return table.concat(Lines, "\n")
end
