local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Employees = require(Shared.Configs.Employees)
local EmployeeService = require(Server.Services.EmployeeService)
local Rolling = require(Shared.Utilities.Rolling)

--> The rarest employee is the one luck moves the most, so its odds are the honest readout of what
--> the number actually bought.
local Rarest = nil :: string?
for Name, Entry in Employees do
	if not Rarest or Entry.Rarity < Employees[Rarest].Rarity then
		Rarest = Name
	end
end

return function(_Context, Amount: number): string
	local Old = EmployeeService:GetSpawnLuck()
	local New = EmployeeService:SetSpawnLuck(Amount)

	--> Luck 0 leaves the rare end with no weight at all, which has no "1 in N" to print
	local Chance = Rolling.Chances(Employees, New)[Rarest]
	local Odds = if Chance > 0 then `1 in {math.floor(1 / Chance + 0.5)}` else "never"

	return `Employee spawn luck {Old} -> {New} ({Rarest} {Odds})`
end
