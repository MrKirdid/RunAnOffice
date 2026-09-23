local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Employees = require(Shared.Configs.Employees)
local PartConfigs = require(Shared.Configs.Parts)
local DeskData = require(Shared.Utilities.DeskData)

local Revenue = {}

--> The three slots a desk pays out of. Anything else on the record, Employee included, is not a part.
local Slots = { "Computer", "Keyboard", "Monitor" }

--> What an employee costs to hire, and how much of that comes back when one is sold. Shared so
--> the card over a walking one and the sell button on a seated one both print the number the
--> server will actually charge or pay. Cubed rather than linear so the top of the table is a
--> real purchase: a 1x hire is pocket change, a 5x hire is a floor-one desk, a 10x hire is a
--> floor-two desk.
local CostPerValue = 100
local CostPower = 3
local SellFraction = 0.5

--> Same reading as the pickup card: what the part is worth crossed with how rare the variant is.
--> An unknown component or variant is worth nothing rather than falling back to some default, so a
--> desk holding a part that no longer exists in the config quietly stops paying for it.
function Revenue.ComponentValue(Component: string, Variant: string): number
	local Base = PartConfigs.BaseValues[Component]
	local Tier = PartConfigs.Variants[Variant]

	return (if Base then Base.Value else 0) * (if Tier then Tier.Value else 0)
end

--> An unknown type still pays, at 1x, the same way HireCost and Describe treat one.
function Revenue.Multiplier(Type: string?): number
	local Config = if Type then Employees[Type] else nil

	return if Config then Config.Value else 1
end

function Revenue.HireCost(Type: string): number
	return math.round(Revenue.Multiplier(Type) ^ CostPower * CostPerValue)
end

--> Floored, so selling and hiring back is never free money on a rounding edge.
function Revenue.SellValue(Type: string): number
	return math.floor(Revenue.HireCost(Type) * SellFraction)
end

--> Cash per second for one desk: its three parts added up, times whoever is sat at it.
--> An empty seat earns nothing at all, so the parts on an unstaffed desk are dead weight until
--> somebody sits down.
function Revenue.DeskRate(Components: any): number
	if type(Components) ~= "table" then
		return 0
	end

	local Employee = Components.Employee

	if type(Employee) ~= "table" then
		return 0
	end

	local Parts = 0

	for _, Slot in Slots do
		local Variant = Components[Slot]

		if type(Variant) == "string" then
			Parts += Revenue.ComponentValue(Slot, Variant)
		end
	end

	return Parts * Revenue.Multiplier(Employee.Type)
end

--> Cash per second across every floor the player owns.
function Revenue.PlotRate(Data: any): number
	local Total = 0

	for _, Floor in DeskData.GetFloors(Data) do
		for _, Slot in DeskData.GetSlots(Data, Floor) do
			local Desk = DeskData.Get(Data, Floor, Slot)

			if Desk then
				Total += Revenue.DeskRate(Desk())
			end
		end
	end

	return Total
end

return Revenue
