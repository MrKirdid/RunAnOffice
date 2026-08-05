--> Argument types for this game's own nouns. Both realms register these: the server so it
--> can resolve them when a command runs, the client so it can validate and autocomplete
--> them while you type. Only command metadata crosses the wire, never the type code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Kmdr = require(Shared.Packages.Kmdr)
local Offsets = require(Shared.Configs.Offsets)
local Parts = require(Shared.Configs.Parts)

--> Cheapest first, so the suggestions read as the rarity ladder instead of alphabet soup
local VariantNames = {}
for Name in Parts.Variants do
	table.insert(VariantNames, Name)
end

table.sort(VariantNames, function(Left: string, Right: string)
	return Parts.Variants[Left].Value < Parts.Variants[Right].Value
end)

--> The offsets decide what a desk actually holds, so they are the list worth matching
local ComponentNames = {}
for Component in Offsets.Desk do
	table.insert(ComponentNames, Component)
end

table.sort(ComponentNames)

return {
	Variant = Kmdr.enumOf("variant", VariantNames),
	Component = Kmdr.enumOf("component", ComponentNames),
}
