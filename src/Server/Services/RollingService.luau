local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)
local Store = require(Shared.Utilities.Store)
local TutorialConfigs = require(Shared.Configs.Tutorial)

local RollingService = {}

function RollingService:Init()
	NetworkingServer.Roll.On(function(Player, Count): { Player: any, Results: { [number]: Rolling.Result } }
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local Unlocked = Data.RerollPads()
		assert(Count <= Unlocked, `{Player.Name} asked for {Count} rolls with only {Unlocked} unlocked`)

		--> Counted before the roll, so the lucky presses the config names are read off the press
		--> that is happening. On the server off its own tally, so each comes round once.
		local Press = Data.Rolls() + 1
		Data.Rolls(Press)

		--> the tree's luck with everything bought on top: Lucky Roller, the server's boost, and on
		--> one of the lucky presses the tutorial's multiplier over the lot
		local Luck = Store.Luck(Data)

		if TutorialConfigs.LuckyPresses[Press] then
			Luck *= TutorialConfigs.LuckyMultiplier
		end

		local Results = Rolling.Roll(Count, Luck)

		--> The tutorial's roll is rigged, once: the first pad gets a part a clear step up from the
		--> desk, so the swap it teaches is worth doing. Rigged here, on the server, and the flag is
		--> what the step reads, so it cannot be had twice or claimed without rolling.
		if TutorialConfigs.IsOn(Data, "Roll") and not Data.TutorialRolled() and Results[0] then
			Results[0].Variant = TutorialConfigs.FirstRollVariant
			Data.TutorialRolled(true)
		end

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
