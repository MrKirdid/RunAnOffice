local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)

local RollingService = {}

function RollingService:Init()
	--> Count comes from the client so it can be anything, erroring out of the listener
	--> rejects the caller's promise instead of handing back rolls they never unlocked.
	NetworkingServer.Roll.On(function(Player, Count): { Player: any, Results: { [number]: Rolling.Desk } }
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local Unlocked = Data.RerollPads()
		assert(Count <= Unlocked, `{Player.Name} asked for {Count} rolls with only {Unlocked} unlocked`)

		return {
			Player = Player,
			Results = Rolling.Roll(Count, Data.Luck()),
		}
	end)
end

return RollingService
