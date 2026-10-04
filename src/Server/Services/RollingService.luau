local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Discoveries = require(Shared.Utilities.Discoveries)
local NetworkingServer = require(Shared.Networking.networkingServer)
local Parts = require(Shared.Configs.Parts)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)
local Store = require(Shared.Utilities.Store)
local TutorialConfigs = require(Shared.Configs.Tutorial)

local Lucky = TutorialConfigs.LuckyRolls

local Spacing = Random.new()

type Boost = { Luck: number, Floor: string }

--> Each lucky roll's floor as a table of its own: every variant at least as rare as the floor, so
--> the one pad it rolls can only come out at that tier or better. Built once, here, rather than per
--> roll: Rolling caches its weights by table.
local function CutDown(Floor: string): { [string]: { Value: number, Rarity: number } }
	local Ceiling = Parts.Variants[Floor].Rarity
	local Entries = {}

	for Name, Entry in Parts.Variants do
		if Entry.Rarity <= Ceiling then
			Entries[Name] = Entry
		end
	end

	return Entries
end

local Floors = {
	[Lucky.Big] = CutDown(Lucky.Big.Floor),
	[Lucky.Small] = CutDown(Lucky.Small.Floor),
}

local RollingService = {}

--> Whether this press is one of the lucky ones, and which. Nothing is scheduled until the tutorial
--> is done; the first press after it books the big one After presses on, and every lucky press
--> books the next small one a random Every presses further.
function RollingService:GetBoost(Data: any, Press: number): Boost?
	if Data.TutorialStage() <= #TutorialConfigs.Stages then
		return nil
	end

	local Next = Data.NextLuckyRoll()

	if Next == 0 then
		Next = Press + Lucky.After - 1
		Data.NextLuckyRoll(Next)
	end

	if Press < Next then
		return nil
	end

	local Given = Data.LuckyRolls()

	Data.LuckyRolls(Given + 1)
	Data.NextLuckyRoll(Press + Spacing:NextInteger(Lucky.Every[1], Lucky.Every[2]))

	return if Given == 0 then Lucky.Big else Lucky.Small
end

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
		--> one of the lucky presses that press's multiplier over the lot
		local Luck = Store.Luck(Data)
		local Boost = self:GetBoost(Data, Press)

		if Boost then
			Luck *= Boost.Luck
		end

		local Results = Rolling.Roll(Count, Luck)

		--> and one pad, wherever it falls, rolled off the cut down table
		if Boost then
			local Slot = Spacing:NextInteger(0, Count - 1)

			Results[Slot].Variant = Rolling.Pick(Floors[Boost], Luck)
		end

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
			Discoveries.Mark(Data, Result.Component, Result.Variant)
		end

		return {
			Player = Player,
			Results = Results,
		}
	end)
end

return RollingService
