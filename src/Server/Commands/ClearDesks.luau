local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).server

local Types = Kmdr.types

local Definition = Kmdr.defineCommand({
	name = "cleardesks",
	description = "Clears every desk a player owns, on every floor.",
	group = "admin",
	args = {
		Targets = Types.players("The players to strip back to an empty plot"),
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

		table.insert(Lines, `{Target.Name}: cleared {DeskData.Clear(Data)} desks.`)
	end

	return table.concat(Lines, "\n")
end)
