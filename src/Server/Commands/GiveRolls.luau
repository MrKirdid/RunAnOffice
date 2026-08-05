local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local PlayerData = require(Shared.PlayerData).server

local Types = Kmdr.types

--> The roll packet is a u8(1..17) both ways, so anything outside that fails validation on
--> send rather than politely doing nothing.
local Minimum, Maximum = 1, 17

local Definition = Kmdr.defineCommand({
	name = "giverolls",
	aliases = { "givepads" },
	description = "Sets how many reroll pads a player has unlocked.",
	group = "admin",
	args = {
		Targets = Types.players("The players to unlock pads for"),
		Amount = Types.integer(`How many pads they end up with, {Minimum} to {Maximum}`),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	if Args.Amount < Minimum or Args.Amount > Maximum then
		return `Pad count has to be between {Minimum} and {Maximum}, the roll packet carries no more.`
	end

	local Lines = {}

	for _, Target in Args.Targets do
		local Data = PlayerData[Target]

		if not Data then
			table.insert(Lines, `{Target.Name}: no loaded data.`)
			continue
		end

		Data.RerollPads(Args.Amount)
		table.insert(Lines, `{Target.Name}: {Args.Amount} pads.`)
	end

	return table.concat(Lines, "\n")
end)
