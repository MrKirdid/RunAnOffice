--[[
	Hiring, on a timer, into whatever desk the player owns and nobody is sat at.

	The roll goes through Rolling against Configs/Employees itself rather than a ladder written
	out a second time here, so the odds a player rolls against are the ones the config prints.
	Luck is threaded through because a flat pick would leave the Luck stat with nothing to act on.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Employees = require(Shared.Configs.Employees)
local NameList = require(Shared.Configs.NameList)
local PlayerData = require(Shared.PlayerData).server
local DeskData = require(Shared.Utilities.DeskData)
local Rolling = require(Shared.Utilities.Rolling)

export type Employee = {
	Type: string,
	Name: string,
	Floor: number,
	Slot: number,
}

local SpawnRate = 5

--> Its own stream, so drawing names never advances the one the roll picks off.
local Names = Random.new()

local EmployeeService = {}

--> Flat, unlike everything else that gets picked around here. A name is flavour rather than a
--> reward: there is no rarity behind Emma over Theodore, so there is nothing for luck to say.
local function PickName(): string
	return NameList[Names:NextInteger(1, #NameList)]
end

local function DeskKey(Floor: number, Slot: number): string
	return tostring(Floor) .. "-" .. tostring(Slot)
end

function EmployeeService:RollEmployee(Luck: number?): string
	return Rolling.Pick(Employees, Luck)
end

--> Lowest desk the player owns that has nobody sat at it, or nil once every desk is staffed.
function EmployeeService:GetFreeDesk(Data: any): (number?, number?)
	local Seated = {}

	for _, Employee in Data.Employees() do
		Seated[DeskKey(Employee.Floor, Employee.Slot)] = true
	end

	for _, Floor in DeskData.GetFloors(Data) do
		local Owned = DeskData.GetTaken(Data, Floor)

		local Slots = {}
		for Slot in Owned do
			table.insert(Slots, Slot)
		end
		table.sort(Slots)

		for _, Slot in Slots do
			if not Seated[DeskKey(Floor, Slot)] then
				return Floor, Slot
			end
		end
	end

	return nil, nil
end

function EmployeeService:Hire(Player: Player): Employee?
	local Data = PlayerData[Player]

	if not Data then
		return nil
	end

	local Floor, Slot = self:GetFreeDesk(Data)

	if not Floor or not Slot then
		return nil
	end

	local Employee: Employee = {
		Type = self:RollEmployee(Data.Luck()),
		Name = PickName(),
		Floor = Floor,
		Slot = Slot,
	}

	Data.Employees[HttpService:GenerateGUID(false)](Employee)

	return Employee
end

--> What every desk the player owns is worth put together, so the payout only has to read one
--> number. An empty desk contributes nothing rather than 1x: nobody is sat at it.
function EmployeeService:GetMultiplier(Player: Player): number
	local Data = PlayerData[Player]

	if not Data then
		return 0
	end

	local Total = 0

	for _, Employee in Data.Employees() do
		local Config = Employees[Employee.Type]

		if Config then
			Total += Config.Value
		end
	end

	return Total
end

function EmployeeService:Start()
	task.spawn(function()
		while task.wait(SpawnRate) do
			for _, Player in Players:GetPlayers() do
				self:Hire(Player)
			end
		end
	end)
end

return EmployeeService
