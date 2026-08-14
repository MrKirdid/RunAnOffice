local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Employees = require(Shared.Configs.Employees)
local NameList = require(Shared.Configs.NameList)
local Rolling = require(Shared.Utilities.Rolling)

type Employee = {
	Name: string,
	Type: string,
	UID: number,
}

--> Its own stream, so drawing names never advances the one the roll picks off.
local Names = Random.new()

local EmployeeService = {}

--> Flat, unlike everything else that gets picked around here. A name is flavour rather than a
--> reward: there is no rarity behind Emma over Theodore, so there is nothing for a weight or
--> for luck to say about it.
local function PickName(): string
	return NameList[Names:NextInteger(1, #NameList)]
end

function EmployeeService:NewEmployee(Type: Employee)
	--...
end

--> Weighted off Configs/Employees itself rather than a ladder written out a second time here,
--> so the odds a player rolls against are the ones the config prints. Luck is threaded through
--> because a flat pick would leave the Luck stat with nothing to act on: left out, Rolling
--> falls back to the plain table.
--> Hands back the type name, which is both the key into Employees and what PlayerData stores.
function EmployeeService:RollEmployee(Luck: number?): Employee
	return {
		Name = PickName(),
		Type = Rolling.Pick(Employees, Luck),
		UID = HttpService:GenerateGUID(),
	}
end

function EmployeeService:Start()
	local SpawnRate = 5

	task.spawn(function()
		while true do
			task.wait(SpawnRate)

			local Employee = self:NewEmployee(self:RollEmployee())

			--> TODO: seat NextEmployee, nothing consumes the roll yet
		end
	end)
end

return EmployeeService
