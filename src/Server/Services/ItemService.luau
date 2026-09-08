local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local DeskData = require(Shared.Utilities.DeskData)
local PartConfigs = require(Shared.Configs.Parts)
local Rolling = require(Shared.Utilities.Rolling)
local Store = require(Shared.Utilities.Store)

--> The slot roll is free and fires off a button rather than a prompt, so nothing in the client
--> stops it being held down. The spin the player watches runs about two seconds; this only has to
--> be short enough never to refuse a real click and long enough that a script cannot turn one
--> button into a thousand profile writes a second.
local SlotRollInterval = 0.35

--> An allowance rather than a flat gap between calls: a desk wears three gifts and all three can be
--> opened at once, so three clicks inside a third of a second is somebody opening a desk rather than
--> somebody spamming. What it does not change is the rate over any longer stretch, which is the
--> whole of what the gap was for -- spend the burst and every roll after it waits the interval out.
local SlotRollBurst = 4

--> Not weak keyed: a weak table drops its entries while the player is still in the game, which
--> would quietly hand the exploiter back an unlimited button. Cleared on the way out instead.
local SlotRolls: { [Player]: { Tokens: number, At: number } } = {}

local ItemService = {}

--> What the player has left to spend, topped up by the time since it was last read. Reading is
--> free: it is spending that has to wait for the roll to be going through, so a call refused for
--> some other reason cannot eat the allowance a real one needs.
local function Allowance(Player: Player): { Tokens: number, At: number }
	local Now = os.clock()
	local Bucket = SlotRolls[Player]

	if not Bucket then
		Bucket = { Tokens = SlotRollBurst, At = Now }
		SlotRolls[Player] = Bucket
	end

	Bucket.Tokens = math.min(SlotRollBurst, Bucket.Tokens + (Now - Bucket.At) / SlotRollInterval)
	Bucket.At = Now

	return Bucket
end

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

	--> Rolling one part of one desk in place, off the gift floating where that part will stand. Only
	--> the variant is rolled: which of the three is being opened comes from the slot the player
	--> pressed, and a component the parts table has never heard of is not one of them.
	NetworkingServer.Items.RollSlot.On(function(Player, Target): Rolling.Result
		local Data = PlayerData[Player]
		assert(Data, `No loaded data for {Player.Name}`)

		local Spend = Allowance(Player)

		assert(Spend.Tokens >= 1, `{Player.Name} is rolling slots too fast`)

		assert(
			PartConfigs.BaseValues[Target.Component] ~= nil,
			`{Player.Name} tried to roll "{Target.Component}", which is not a desk part`
		)

		local Desk = DeskData.Get(Data, Target.Floor, Target.Slot)
		assert(Desk, `{Player.Name} has no desk at floor {Target.Floor} slot {Target.Slot}`)

		local Components = Desk()
		assert(type(Components) == "table", `{Player.Name}'s desk at {Target.Floor}/{Target.Slot} is empty`)

		--> Each slot rolls once, off the gift standing over it. Only the client keeps the gift from
		--> coming back, so this is what stops a slot being rolled again until the rarest lands.
		assert(
			Components[Target.Component] == nil,
			`{Player.Name}'s {Target.Component} at {Target.Floor}/{Target.Slot} has already been rolled`
		)

		--> Spent only once the roll is going through, so a refused call cannot be used to eat the
		--> allowance a legitimate one needs. Nothing above here yields, so what was checked is still
		--> what is being taken.
		Spend.Tokens -= 1

		local Variant = Rolling.RollVariant(Store.Luck(Data))

		local Rolled = table.clone(Components)
		Rolled[Target.Component] = Variant

		Desk(Rolled)

		return { Component = Target.Component, Variant = Variant }
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		SlotRolls[Player] = nil
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
