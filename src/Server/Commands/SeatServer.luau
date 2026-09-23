local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local CommandUtil = require(Shared.Console.CommandUtil)
local DeskData = require(Shared.Utilities.DeskData)
local EmployeeService = require(Server.Services.EmployeeService)

local Maximum = 50

return function(_Context, Targets: { Player }, Amount: number, Type: string?): string
	if Amount < 1 or Amount > Maximum then
		return `Amount has to be between 1 and {Maximum}.`
	end

	return CommandUtil.ForEach(Targets, function(_Target: Player, Data: any): string
		local Seated = 0

		for _ = 1, Amount do
			local Floor, Slot = DeskData.GetFreeSeat(Data)

			if not Floor or not Slot then
				break
			end

			local Employee = EmployeeService:RollEmployee(nil, Type)

			if not EmployeeService:SeatAt(Data, Floor, Slot, Employee.Name, Employee.Type) then
				break
			end

			Seated += 1
		end

		if Seated == 0 then
			return "no free desk. Give them one with 'givedesk' first."
		end

		if Seated < Amount then
			return `seated {Seated}, then ran out of free desks.`
		end

		return `seated {Seated}.`
	end)
end
