--[[
	Desk ownership lives at Floors[Floor].Desks[Slot] in player data, and both sides read it:
	the server to decide what it is selling, the client to decide what to build. This is the
	data half of a desk, DeskPlacements is the world half.

	Every key goes through MatchKey because a save round trip turns the numeric keys into
	strings, so a session that started from a fresh template and one that started from a
	rejoin do not agree on how to index the same slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskPlacements = require(Shared.Utilities.DeskPlacements)

local DeskData = {}

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

--> Unlocked floor numbers in order, so callers walk a plot bottom up.
function DeskData.GetFloors(Data: any): { number }
	local Floors = {}

	for Floor in Data.Floors() do
		table.insert(Floors, tonumber(Floor))
	end

	table.sort(Floors)

	return Floors
end

--> Slots on a floor that already hold a desk.
function DeskData.GetTaken(Data: any, Floor: number): { [number]: boolean }
	local Taken = {}
	local FloorKey = MatchKey(Data.Floors(), Floor)

	if FloorKey == nil then
		return Taken
	end

	for Slot in Data.Floors[FloorKey].Desks() do
		Taken[tonumber(Slot)] = true
	end

	return Taken
end

--> Slots on a floor that hold a desk, lowest first.
function DeskData.GetSlots(Data: any, Floor: number): { number }
	local Slots = {}
	local FloorKey = MatchKey(Data.Floors(), Floor)

	if FloorKey == nil then
		return Slots
	end

	for Slot in Data.Floors[FloorKey].Desks() do
		table.insert(Slots, tonumber(Slot))
	end

	table.sort(Slots)

	return Slots
end

--> Lowest desk with nobody in the chair. Skip covers seats spoken for but not filled yet, which
--> is every employee currently walking to one.
function DeskData.GetFreeSeat(Data: any, Skip: { [string]: boolean }?): (number?, number?)
	for _, Floor in DeskData.GetFloors(Data) do
		for _, Slot in DeskData.GetSlots(Data, Floor) do
			local Desk = DeskData.Get(Data, Floor, Slot)
			local Components = Desk and Desk()

			local Free = type(Components) == "table"
				and Components.Employee == nil
				and not (Skip and Skip[`{Floor}-{Slot}`])

			if Free then
				return Floor, Slot
			end
		end
	end

	return nil, nil
end

--> The handle for a slot that holds a desk, or nil when the slot is empty. Call it to read
--> the desk, call it with nil to clear the slot.
function DeskData.Get(Data: any, Floor: number, Slot: number): any?
	local FloorKey = MatchKey(Data.Floors(), Floor)

	if FloorKey == nil then
		return nil
	end

	local FloorData = Data.Floors[FloorKey]
	local SlotKey = MatchKey(FloorData.Desks(), Slot)

	if SlotKey == nil then
		return nil
	end

	return FloorData.Desks[SlotKey]
end

--> Floors only appear in data once the player unlocks them, so anything handing out a desk
--> on a floor they have not reached has to create the entry first or the write lands nowhere.
function DeskData.Unlock(Data: any, Floor: number): any
	local FloorKey = MatchKey(Data.Floors(), Floor)

	if FloorKey == nil then
		Data.Floors[Floor]({ Desks = {} })
		FloorKey = Floor
	end

	return Data.Floors[FloorKey]
end

--> Lowest floor and slot the player has unlocked but not filled, or nil once the plot is full.
function DeskData.GetNextAvailable(Data: any, Plot: Model): (number?, number?)
	for _, Floor in DeskData.GetFloors(Data) do
		local Taken = DeskData.GetTaken(Data, Floor)

		--> Slot count comes from that floor's markers, so it tracks the plot layout
		for Slot = 1, DeskPlacements.GetCount(Plot, Floor) do
			if not Taken[Slot] then
				return Floor, Slot
			end
		end
	end

	return nil, nil
end

--> Clears every desk the player owns, one slot at a time so each removal replicates as its
--> own key and the client tears down the matching model. Returns how many went.
function DeskData.Clear(Data: any): number
	local Cleared = 0

	for _, Floor in DeskData.GetFloors(Data) do
		local FloorKey = MatchKey(Data.Floors(), Floor)
		local Desks = Data.Floors[FloorKey].Desks

		--> The keys are collected up front because clearing them mutates what is being walked
		local Slots = {}
		for Slot in Desks() do
			table.insert(Slots, Slot)
		end

		for _, Slot in Slots do
			Desks[Slot](nil)
			Cleared += 1
		end
	end

	return Cleared
end

return DeskData
