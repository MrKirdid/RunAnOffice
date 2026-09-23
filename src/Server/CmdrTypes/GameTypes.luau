--> The argument types the game's own commands take. Cmdr moves this module into ReplicatedStorage
--> and runs it on both realms, so everything it reads has to be replicated: Configs are, Services
--> are not.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Employees = require(Shared.Configs.Employees)
local Gears = require(Shared.Configs.Gears)
local Offsets = require(Shared.Configs.Offsets)
local Parts = require(Shared.Configs.Parts)
local Upgrades = require(Shared.Configs.Upgrades)

--> Cheapest first, so autocomplete reads as the ladder rather than as whatever the table hashed to.
local function ByValue(Entries: { [string]: { Value: number, [string]: any } }): { string }
	local Names = {}

	for Name in Entries do
		table.insert(Names, Name)
	end

	table.sort(Names, function(Left: string, Right: string)
		return Entries[Left].Value < Entries[Right].Value
	end)

	return Names
end

local function Sorted(Values: { string }): { string }
	table.sort(Values)

	return Values
end

local ComponentNames = {}
for Component in Offsets.Desk do
	table.insert(ComponentNames, Component)
end

--> "all" rides in the same argument rather than a second flag, so granting the whole tree is
--> `giveupgrade me all` and granting one node is the same command with a different word.
local UpgradeIds = { "all" }
for Id, Config in Upgrades.List do
	if not Config.IsAction then
		table.insert(UpgradeIds, Id)
	end
end

return function(Registry: any)
	local Util = Registry.Cmdr.Util

	Registry:RegisterType("variant", Util.MakeEnumType("Variant", ByValue(Parts.Variants)))
	Registry:RegisterType("component", Util.MakeEnumType("Component", Sorted(ComponentNames)))

	--> Names carry spaces, which the console handles by quoting: spawnnpcs 3 "Tie Guy"
	Registry:RegisterType("employeeType", Util.MakeEnumType("EmployeeType", ByValue(Employees)))

	Registry:RegisterType("upgrade", Util.MakeEnumType("Upgrade", Sorted(UpgradeIds)))
	Registry:RegisterType("gear", Util.MakeEnumType("Gear", Gears.Sorted()))
	Registry:RegisterType("rollTable", Util.MakeEnumType("RollTable", { "variants", "employees" }))
	Registry:RegisterType("demoAction", Util.MakeEnumType("DemoAction", { "build", "clear", "goto" }))
end
