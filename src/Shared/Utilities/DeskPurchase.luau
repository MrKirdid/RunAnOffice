local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskData = require(Shared.Utilities.DeskData)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)

--> What each desk costs, by how many are already standing: the first is Prices[1]. One curve for
--> the whole plot rather than one per floor: moving upstairs is something the player is given for
--> filling a floor, not something they are charged twice for.
--> Written out rather than as a formula because the shape is not one curve: the first few are
--> seconds of income apiece so the plot fills fast, then each one is a little longer than the
--> last, and by the top floor a desk is twenty or so minutes of income and never much more.
local Prices = {
	--> floor 1
	250,
	450,
	1_100,
	2_500,
	5_500,
	11_000,
	20_000,
	35_000,
	--> floor 2
	60_000,
	95_000,
	140_000,
	200_000,
	280_000,
	380_000,
	500_000,
	650_000,
	--> floor 3
	850_000,
	1_100_000,
	1_400_000,
	1_800_000,
	2_300_000,
	2_900_000,
	3_600_000,
	4_500_000,
	--> floor 4
	5_600_000,
	7_000_000,
	8_500_000,
	10_500_000,
	13_000_000,
	16_000_000,
	20_000_000,
	25_000_000,
}

--> Past the end of the list, for a plot with more desks than it was priced for.
local Growth = 1.25

--> A price is only ever read in its short form, which keeps one decimal, so anything longer than
--> two figures would be shown rounded down and taken in full. Rounded here instead, once, so the
--> number on the board is the number the server charges.
local function Readable(Value: number): number
	if Value < 1000 then
		return math.round(Value)
	end

	local Scale = 10 ^ (math.floor(math.log10(Value)) - 1)

	return math.round(Value / Scale) * Scale
end

--> The desk a press on the board would buy, and what it costs. Nil means the plot is finished:
--> every floor it was built with is open and every desk on them is standing.
export type Next = {
	Floor: number,
	Slot: number,
	Price: number,

	--> whether the floor it lands on is still locked, so buying this desk opens it as well
	Unlocks: boolean,
}

local DeskPurchase = {}

--> Desks standing across the whole plot, which is the only thing the price is worked out from.
function DeskPurchase.Count(Data: any): number
	local Count = 0

	for _, Floor in DeskData.GetFloors(Data) do
		Count += #DeskData.GetSlots(Data, Floor)
	end

	return Count
end

function DeskPurchase.PriceAt(Owned: number): number
	local Listed = Prices[Owned + 1]

	if Listed then
		return Listed
	end

	return Readable(Prices[#Prices] * Growth ^ (Owned + 1 - #Prices))
end

function DeskPurchase.Price(Data: any): number
	return DeskPurchase.PriceAt(DeskPurchase.Count(Data))
end

--> Read the same way on both sides, so the board prints what the server is about to charge and
--> names the desk the server is about to build.
function DeskPurchase.Next(Data: any, Plot: Model?): Next?
	if not Plot then
		return nil
	end

	local Price = DeskPurchase.Price(Data)
	local Floor, Slot = DeskData.GetNextAvailable(Data, Plot)

	if Floor and Slot then
		return { Floor = Floor, Slot = Slot, Price = Price, Unlocks = false }
	end

	--> Every floor owned is full, so the next desk is the first one upstairs and brings the floor
	--> with it. Taken off the highest floor owned rather than a count, since a command can open
	--> floor 3 without floor 2 and counting would hand back a floor already standing.
	local Owned = DeskData.GetFloors(Data)
	local Above = (Owned[#Owned] or 0) + 1

	--> Past the top of the plot there is nowhere left to put one.
	if DeskPlacements.GetCount(Plot, Above) < 1 then
		return nil
	end

	return { Floor = Above, Slot = 1, Price = Price, Unlocks = true }
end

return DeskPurchase
