local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local EmployeeConfigs = require(Shared.Configs.Employees)
local PartConfigs = require(Shared.Configs.Parts)
local Rolling = require(Shared.Utilities.Rolling)

--> The two kinds of thing that go through the hands and the inventory: a desk part, as Component
--> and Variant, and an employee, as Name and Type. One record is one or the other, never both,
--> and anything else -- an empty table, a part whose variant has left the config -- is nothing.
export type Part = { Component: string, Variant: string }
export type Employee = { Name: string, Type: string }
export type Entry = { Component: string?, Variant: string?, Name: string?, Type: string? }

--> Odds at no luck, which is what a thing's rarity is: it does not get rarer for having been
--> rolled by somebody unlucky.
local PartOdds = Rolling.Chances(PartConfigs.Variants, 1)
local EmployeeOdds = Rolling.Chances(EmployeeConfigs, 1)

--> What an employee is carried as. Component names are the three desk slots, so this can never
--> be mistaken for one.
local EmployeeCarry = "Employee"

local Items = {}

--> How many things the inventory holds. Well past what anyone stashes by hand; the cap is there so
--> a script cannot grow a save without bound.
Items.MaxInventory = 100

function Items.IsPart(Entry: any): boolean
	return type(Entry) == "table"
		and type(Entry.Component) == "string"
		and type(Entry.Variant) == "string"
		and PartConfigs.BaseValues[Entry.Component] ~= nil
		and PartConfigs.Variants[Entry.Variant] ~= nil
end

function Items.IsEmployee(Entry: any): boolean
	return type(Entry) == "table"
		and type(Entry.Name) == "string"
		and type(Entry.Type) == "string"
		and EmployeeConfigs[Entry.Type] ~= nil
end

--> Whether there is anything in a record at all, of either kind.
function Items.IsHeld(Entry: any): boolean
	return Items.IsPart(Entry) or Items.IsEmployee(Entry)
end

--> "1 in N" for either kind, off the plain tables. Anything the tables have never heard of is
--> rarer than everything, rather than commoner.
function Items.Odds(Entry: Entry): number
	local Chance = if Items.IsPart(Entry)
		then PartOdds[Entry.Variant :: string]
		elseif Items.IsEmployee(Entry) then EmployeeOdds[Entry.Type :: string]
		else nil

	return if Chance and Chance > 0 then 1 / Chance else math.huge
end

--> What the thing is worth on a desk: a part's base crossed with its variant, an employee's
--> multiplier. The same reading the cards over both use.
function Items.Value(Entry: Entry): number
	if Items.IsPart(Entry) then
		local Base = PartConfigs.BaseValues[Entry.Component :: string]
		local Tier = PartConfigs.Variants[Entry.Variant :: string]

		return Base.Value * Tier.Value
	end

	if Items.IsEmployee(Entry) then
		return EmployeeConfigs[Entry.Type :: string].Value
	end

	return 0
end

--> What one thing is called on a card: "Kitty Keyboard", or the employee's own name.
function Items.Title(Entry: Entry): string
	if Items.IsPart(Entry) then
		return `{Entry.Variant} {Entry.Component}`
	end

	return Entry.Name or ""
end

--> What two records have to share to be the same thing, for stacking. An employee's name is
--> part of it: two Tie Guys with different names are two people.
function Items.Key(Entry: Entry): string
	if Items.IsPart(Entry) then
		return `Part|{Entry.Component}|{Entry.Variant}`
	end

	return `{EmployeeCarry}|{Entry.Type}|{Entry.Name}`
end

--> Best first: the rarer thing, then the more valuable one, then by name so the order is stable.
function Items.Compare(Left: Entry, Right: Entry): boolean
	local LeftOdds, RightOdds = Items.Odds(Left), Items.Odds(Right)

	if LeftOdds ~= RightOdds then
		return LeftOdds > RightOdds
	end

	local LeftValue, RightValue = Items.Value(Left), Items.Value(Right)

	if LeftValue ~= RightValue then
		return LeftValue > RightValue
	end

	return Items.Title(Left) < Items.Title(Right)
end

--> A copy holding only what the thing is, with nothing else that was on the record -- the stolen
--> tags, in particular -- carried across.
function Items.Strip(Entry: Entry): Entry
	if Items.IsPart(Entry) then
		return { Component = Entry.Component, Variant = Entry.Variant }
	end

	return { Name = Entry.Name, Type = Entry.Type }
end

--> What is published on the Player for every client to draw in the arms: "Component|Variant"
--> for a part, "Employee|Type" for an employee. Nil for empty hands, so the attribute comes off.
function Items.Carry(Entry: any): string?
	if Items.IsPart(Entry) then
		return Entry.Component .. "|" .. Entry.Variant
	end

	if Items.IsEmployee(Entry) then
		return EmployeeCarry .. "|" .. Entry.Type
	end

	return nil
end

--> The reverse of Carry. An employee comes back with no name: the arms do not need one.
function Items.ReadCarry(Raw: any): Entry?
	if type(Raw) ~= "string" then
		return nil
	end

	local Head, Tail = string.match(Raw, "^([^|]+)|(.+)$")

	if not Head or not Tail then
		return nil
	end

	if Head == EmployeeCarry then
		return { Name = "", Type = Tail }
	end

	return { Component = Head, Variant = Tail }
end

return Items
