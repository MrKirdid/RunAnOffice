local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Kmdr = require(Shared.Packages.Kmdr)
local Employees = require(Shared.Configs.Employees)
local Offsets = require(Shared.Configs.Offsets)
local Parts = require(Shared.Configs.Parts)

local function ByValue(Entries: { [string]: { Value: number } }): { string }
	local Names = {}

	for Name in Entries do
		table.insert(Names, Name)
	end

	table.sort(Names, function(Left: string, Right: string)
		return Entries[Left].Value < Entries[Right].Value
	end)

	return Names
end

local ComponentNames = {}
for Component in Offsets.Desk do
	table.insert(ComponentNames, Component)
end

table.sort(ComponentNames)

return {
	Variant = Kmdr.enumOf("variant", ByValue(Parts.Variants)),
	Component = Kmdr.enumOf("component", ComponentNames),

	--> Names carry spaces, which the console handles by quoting: employee spawn "Tie Guy"
	EmployeeType = Kmdr.enumOf("employee", ByValue(Employees)),

	Stat = Kmdr.enumOf("stat", { "cash", "luck", "rolls", "floor" }),
	DeskAction = Kmdr.enumOf("action", { "give", "remove" }),
	EmployeeAction = Kmdr.enumOf("action", { "spawn", "list" }),
	Clearable = Kmdr.enumOf("target", { "desks", "employees", "data" }),
	RollTable = Kmdr.enumOf("table", { "variants", "employees" }),
}
