local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)

local RollingService = {}

--> The results are written into the player's own data as well as handed back, because the parts
--> on those pads have to survive the trip: the client says "I picked up pad 3" later, and the
--> only honest answer to what was on pad 3 is the one the server wrote down at the time.
function RollingService:Init()
	--> Count comes from the client so it can be anything, erroring out of the listener
	--> rejects the caller's promise instead of handing back rolls they never unlocked.
	NetworkingServer.Roll.On(function(Player, Count): { Player: any, Results: { [number]: Rolling.Result } }
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local Unlocked = Data.RerollPads()
		assert(Count <= Unlocked, `{Player.Name} asked for {Count} rolls with only {Unlocked} unlocked`)

		local Results = Rolling.Roll(Count, Data.Luck())

		--> A fresh roll replaces whatever was left standing, matching the client throwing the last
		--> roll's parts away. Anything already picked up is in hand and untouched by this.
		--> The keys are collected up front because clearing them mutates what is being walked, the
		--> same reason DeskData.Clear does it that way. Walking it directly hangs the listener, and
		--> a hung listener never replies, so the client's roll promise just never settles.
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
