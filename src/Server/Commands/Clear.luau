local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).server

local Types = Kmdr.types

local Definition = Kmdr.defineCommand({
	name = "clear",
	description = "desks strips a plot back to empty. employees empties every seat but leaves the desks "
		.. "standing. data wipes the save outright and kicks them, so they come back on a fresh profile.",
	group = "admin",
	args = {
		Target = ConsoleTypes.Clearable("desks, employees or data"),
		Targets = Types.players("Who to clear"),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	--> resetData kicks on its way out, so the names have to be collected before the call
	if Args.Target == "data" then
		local Names = {}

		for _, Target in Args.Targets do
			table.insert(Names, Target.Name)
		end

		for _, Target in Args.Targets do
			PlayerData.Service:resetData(Target)
		end

		return `Wiped and kicked {table.concat(Names, ", ")}.`
	end

	local Lines = {}

	for _, Target in Args.Targets do
		local Data = PlayerData[Target]

		if not Data then
			table.insert(Lines, `{Target.Name}: no loaded data.`)
			continue
		end

		local Cleared = if Args.Target == "desks" then DeskData.Clear(Data) else DeskData.ClearSeats(Data)

		table.insert(Lines, `{Target.Name}: cleared {Cleared} {Args.Target}.`)
	end

	return table.concat(Lines, "\n")
end)
