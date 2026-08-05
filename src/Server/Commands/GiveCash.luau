local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local PlayerData = require(Shared.PlayerData).server

local Types = Kmdr.types

local Definition = Kmdr.defineCommand({
	name = "givecash",
	description = "Adds cash to a player, or takes it away with a negative amount.",
	group = "admin",
	args = {
		Targets = Types.players("The players to pay"),
		Amount = Types.integer("How much cash to add, negative to take it away"),
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

		local New = Data.Cash(function(Current: number)
			return math.max(Current + Args.Amount, 0)
		end)

		table.insert(Lines, `{Target.Name}: {New} cash.`)
	end

	return table.concat(Lines, "\n")
end)
