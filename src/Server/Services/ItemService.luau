--[[
	Moving a rolled part from a pad, into the player's hands, and onto a desk.

	Every step is a move and never a copy, through a single Holding slot, so there is no sequence
	of calls that ends with the same part in two places. The client never names a part: it names a
	pad to take from and a desk to put down on, and the server looks up what that actually means.
	Spamming either call is harmless because the first one empties the slot the rest would read.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local DeskData = require(Shared.Utilities.DeskData)
local PartConfigs = require(Shared.Configs.Parts)
local Rolling = require(Shared.Utilities.Rolling)

local ItemService = {}

--> A save round trip turns numeric keys into strings, so a slot written this session and one read
--> back from a save do not index the same way. Same problem DeskData solves for desks.
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

--> Anything that came out of data is checked against the configs before it is handed on. A part
--> naming a component or variant that no longer exists would otherwise reach the client and
--> error there, out of reach of the assert that should have caught it.
local function Known(Item: any): boolean
	return type(Item) == "table"
		and type(Item.Component) == "string"
		and type(Item.Variant) == "string"
		and PartConfigs.BaseValues[Item.Component] ~= nil
		and PartConfigs.Variants[Item.Variant] ~= nil
end

function ItemService:Init()
	--> Taking the part off a pad. The slot is the only thing the client gets a say in, and the
	--> pad is cleared in the same breath so a second call finds nothing there.
	NetworkingServer.Items.PickUp.On(function(Player, Slot): Rolling.Result
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local PadKey = MatchKey(Data.Pads(), Slot)
		assert(PadKey ~= nil, `{Player.Name} tried to pick up empty pad {Slot}`)

		local Item = Data.Pads[PadKey]()
		assert(Known(Item), `{Player.Name} tried to pick up a part that is not a part`)

		--> Cleared before it is handed over, so the same pad cannot answer twice
		Data.Pads[PadKey](nil)

		--> Whatever was already in hand is dropped on the floor and forgotten, matching what the
		--> client does when a second part is picked up
		Data.Holding({ Component = Item.Component, Variant = Item.Variant })

		return { Component = Item.Component, Variant = Item.Variant }
	end)

	--> Putting it down on a desk. Which of the three components it lands in is decided by what the
	--> player is holding, so the client cannot aim a keyboard at a monitor slot.
	NetworkingServer.Items.Replace.On(function(Player, Target): Rolling.Result
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local Item = Data.Holding()
		assert(Known(Item), `{Player.Name} tried to place with empty hands`)

		local Desk = DeskData.Get(Data, Target.Floor, Target.Slot)
		assert(Desk, `{Player.Name} has no desk at floor {Target.Floor} slot {Target.Slot}`)

		local Components = Desk()
		assert(type(Components) == "table", `{Player.Name}'s desk at {Target.Floor}/{Target.Slot} is empty`)

		--> The old part is gone, not returned to hand and not put back on a pad
		local Swapped = table.clone(Components)
		Swapped[Item.Component] = Item.Variant

		Desk(Swapped)
		Data.Holding({})

		return { Component = Item.Component, Variant = Item.Variant }
	end)
end

return ItemService
