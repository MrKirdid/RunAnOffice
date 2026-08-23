local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Kmdr = require(Shared.Packages.Kmdr)
local EmployeeService = require(Server.Services.EmployeeService)
local Employees = require(Shared.Configs.Employees)
local Rolling = require(Shared.Utilities.Rolling)

local Types = Kmdr.types

--> The rarest employee is the one luck moves the most, so its odds are the honest readout of what
--> the number actually bought.
local Rarest = nil :: string?
for Name, Entry in Employees do
	if not Rarest or Entry.Rarity < Employees[Rarest].Rarity then
		Rarest = Name
	end
end

local Definition = Kmdr.defineCommand({
	name = "serverluck",
	description = "Sets the luck every employee spawn rolls at, for the whole server rather than one "
		.. "player. 1 is the plain table, 2 doubles the rarest odds, 0 kills them. Not saved, so it "
		.. "resets when the server does. Only employee spawns read it today.",
	group = "admin",
	args = {
		Amount = Types.number("The multiplier to set it to"),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	local Old = EmployeeService:GetSpawnLuck()
	local New = EmployeeService:SetSpawnLuck(Args.Amount)

	--> Luck 0 leaves the rare end with no weight at all, which has no "1 in N" to print
	local Chance = Rolling.Chances(Employees, New)[Rarest]
	local Odds = if Chance > 0 then `1 in {math.floor(1 / Chance + 0.5)}` else "never"

	return `Employee spawn luck {Old} -> {New} ({Rarest} {Odds})`
end)
