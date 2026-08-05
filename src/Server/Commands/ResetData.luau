local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Kmdr = require(Shared.Packages.Kmdr)
local PlayerData = require(Shared.PlayerData).server

local Types = Kmdr.types

local Definition = Kmdr.defineCommand({
	name = "resetdata",
	aliases = { "wipedata" },
	description = "Wipes a player's save and kicks them, so they come back on a fresh profile.",
	group = "admin",
	args = {
		Targets = Types.players("The players whose save gets wiped"),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	--> resetData kicks on its way out, so the names have to be collected before the call
	local Names = {}
	for _, Target in Args.Targets do
		table.insert(Names, Target.Name)
	end

	for _, Target in Args.Targets do
		PlayerData.Service:resetData(Target)
	end

	return `Wiped and kicked {table.concat(Names, ", ")}.`
end)
