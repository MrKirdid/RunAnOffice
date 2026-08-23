local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local DeskData = require(Shared.Utilities.DeskData)
local PartConfigs = require(Shared.Configs.Parts)
local Rolling = require(Shared.Utilities.Rolling)

local ItemService = {}

--> A save round trip turns numeric keys into strings, so slots need matching both ways.
local function MatchKey(Raw: { [any]: any }?, Wanted: number): any?
	if not Raw then
		return nil
	end

	if Raw[Wanted] ~= nil then
		return Wanted
	end

	for Key in Raw do
		if tonumber(Key) == Wanted then
			return Key
		end
	end

	return nil
end

local function Known(Item: any): boolean
	return type(Item) == "table"
		and type(Item.Component) == "string"
		and type(Item.Variant) == "string"
		and PartConfigs.BaseValues[Item.Component] ~= nil
		and PartConfigs.Variants[Item.Variant] ~= nil
end

function ItemService:Init()
	NetworkingServer.Items.PickUp.On(function(Player, Slot): Rolling.Result
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local PadKey = MatchKey(Data.Pads(), Slot)
		assert(PadKey ~= nil, `{Player.Name} tried to pick up empty pad {Slot}`)

		local Item = Data.Pads[PadKey]()
		assert(Known(Item), `{Player.Name} tried to pick up a part that is not a part`)

		Data.Pads[PadKey](nil)

		Data.Holding({ Component = Item.Component, Variant = Item.Variant })

		return { Component = Item.Component, Variant = Item.Variant }
	end)

	NetworkingServer.Items.Replace.On(function(Player, Target): Rolling.Result
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local Item = Data.Holding()
		assert(Known(Item), `{Player.Name} tried to place with empty hands`)

		local Desk = DeskData.Get(Data, Target.Floor, Target.Slot)
		assert(Desk, `{Player.Name} has no desk at floor {Target.Floor} slot {Target.Slot}`)

		local Components = Desk()
		assert(type(Components) == "table", `{Player.Name}'s desk at {Target.Floor}/{Target.Slot} is empty`)

		local Swapped = table.clone(Components)
		Swapped[Item.Component] = Item.Variant

		Desk(Swapped)
		Data.Holding({})

		return { Component = Item.Component, Variant = Item.Variant }
	end)

	--> Cancelling a pickup. The pad slot was already emptied when it was picked up, so letting go of
	--> it drops the part for good rather than putting it back.
	NetworkingServer.Items.Drop.On(function(Player): boolean
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		if not Known(Data.Holding()) then
			return false
		end

		Data.Holding({})

		return true
	end)
end

return ItemService
