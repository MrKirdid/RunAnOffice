local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)
local Store = require(Shared.Utilities.Store)

local RollingService = {}

function RollingService:Init()
	NetworkingServer.Roll.On(function(Player, Count): { Player: any, Results: { [number]: Rolling.Result } }
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local Unlocked = Data.RerollPads()
		assert(Count <= Unlocked, `{Player.Name} asked for {Count} rolls with only {Unlocked} unlocked`)

		--> the tree's luck with everything bought on top: Lucky Roller, and the server's boost
		local Results = Rolling.Roll(Count, Store.Luck(Data))

		local Stale = {}

		for Slot in Data.Pads() do
			table.insert(Stale, Slot)
		end

		for _, Slot in Stale do
			Data.Pads[Slot](nil)
		end

		for Slot, Result in Results do
			Data.Pads[Slot](Result)
		end

		return {
			Player = Player,
			Results = Results,
		}
	end)
end

return RollingService
