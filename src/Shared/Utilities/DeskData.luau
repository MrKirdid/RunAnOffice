local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskPlacements = require(Shared.Utilities.DeskPlacements)

local DeskData = {}

--> What a slot holds once the part on it has been stolen. Not nil: nil is a slot never rolled, and
--> the gift standing over one of those would hand the victim a free reroll of whatever was taken.
--> An empty string is a slot that was rolled and then emptied -- worth nothing, wearing no gift,
--> and filled again only by a part being placed on it or by the thief being caught.
DeskData.Empty = ""

--> Whether a slot's record is a part that can be built, paid for or stolen, rather than nil or the
--> empty left behind by a theft.
function DeskData.IsPart(Variant: any): boolean
	return type(Variant) == "string" and Variant ~= DeskData.Empty
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

--> Empties every seat the player owns, leaving the desks themselves standing. Returns how many.
function DeskData.ClearSeats(Data: any): number
	local Cleared = 0

	for _, Floor in DeskData.GetFloors(Data) do
		for _, Slot in DeskData.GetSlots(Data, Floor) do
			local Desk = DeskData.Get(Data, Floor, Slot)
			local Components = Desk and Desk()

			if Desk and type(Components) == "table" and Components.Employee then
				local Emptied = table.clone(Components)
				Emptied.Employee = nil

				Desk(Emptied)
				Cleared += 1
			end
		end
	end

	return Cleared
end

--> Lowest desk with nobody sat at it, walking the floors bottom up. Skip holds seats that are
--> spoken for but not filled yet, which is every employee currently walking to one.
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

function DeskData.GetFloors(Data: any): { number }
	local Floors = {}

	for Floor in Data.Floors() do
		table.insert(Floors, tonumber(Floor))
	end

	table.sort(Floors)

	return Floors
end

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

function DeskData.Unlock(Data: any, Floor: number): any
	local FloorKey = MatchKey(Data.Floors(), Floor)

	if FloorKey == nil then
		Data.Floors[Floor]({ Desks = {} })
		FloorKey = Floor
	end

	return Data.Floors[FloorKey]
end

--> The reverse of Unlock: the floor key leaves the save, which replicates as a removal and takes
--> every desk standing on it with it. Returns whether there was one to take.
function DeskData.Lock(Data: any, Floor: number): boolean
	local FloorKey = MatchKey(Data.Floors(), Floor)

	if FloorKey == nil then
		return false
	end

	Data.Floors[FloorKey](nil)

	return true
end

function DeskData.GetNextAvailable(Data: any, Plot: Model): (number?, number?)
	for _, Floor in DeskData.GetFloors(Data) do
		local Taken = DeskData.GetTaken(Data, Floor)

		for Slot = 1, DeskPlacements.GetCount(Plot, Floor) do
			if not Taken[Slot] then
				return Floor, Slot
			end
		end
	end

	return nil, nil
end

function DeskData.Clear(Data: any): number
	local Cleared = 0

	for _, Floor in DeskData.GetFloors(Data) do
		local FloorKey = MatchKey(Data.Floors(), Floor)
		local Desks = Data.Floors[FloorKey].Desks

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
