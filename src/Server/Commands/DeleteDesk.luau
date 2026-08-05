local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).server

local Types = Kmdr.types

local Definition = Kmdr.defineCommand({
	name = "deletedesk",
	aliases = { "removedesk" },
	description = "Clears one desk slot in a player's plot, freeing it to be bought again.",
	group = "admin",
	args = {
		Targets = Types.players("The players to take a desk from"),
		Floor = Types.integer("Which floor the desk sits on"),
		Slot = Types.integer("Which desk slot on that floor"),
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

		local Desk = DeskData.Get(Data, Args.Floor, Args.Slot)

		if not Desk then
			table.insert(Lines, `{Target.Name}: floor {Args.Floor} slot {Args.Slot} is already empty.`)
			continue
		end

		--> Clearing the key replicates as a removal, which is what tears down the model
		Desk(nil)

		table.insert(Lines, `{Target.Name}: cleared floor {Args.Floor} slot {Args.Slot}.`)
	end

	return table.concat(Lines, "\n")
end)
