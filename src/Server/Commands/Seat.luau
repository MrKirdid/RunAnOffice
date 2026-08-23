local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local EmployeeService = require(Server.Services.EmployeeService)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).server

local Types = Kmdr.types

local Definition = Kmdr.defineCommand({
	name = "seat",
	description = "Sits an employee straight down at the lowest free desk, skipping the walk across the "
		.. "map. The fast way to check seating, the desk offset and the typing animation.",
	group = "admin",
	args = {
		Targets = Types.players("Whose desk to sit one at"),
		Type = ConsoleTypes.EmployeeType("Which one. Rolled off the table when left out"):optional(),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	local Lines = {}

	for _, Target in Args.Targets do
		local Data = PlayerData[Target]

		if not Data then
			table.insert(Lines, `{Target.Name}: no loaded data.`)
			continue
		end

		local Floor, Slot = DeskData.GetFreeSeat(Data)

		if not Floor or not Slot then
			table.insert(Lines, `{Target.Name}: no free desk. Buy one, or 'desk give' them one first.`)
			continue
		end

		local Employee = EmployeeService:RollEmployee(nil, Args.Type)
		local Seated = EmployeeService:SeatAt(Data, Floor, Slot, Employee.Name, Employee.Type)

		if not Seated then
			table.insert(Lines, `{Target.Name}: floor {Floor} slot {Slot} would not take one.`)
			continue
		end

		table.insert(Lines, `{Target.Name}: {EmployeeService:Describe(Employee)} @ floor {Floor} slot {Slot}`)
	end

	return table.concat(Lines, "\n")
end)
