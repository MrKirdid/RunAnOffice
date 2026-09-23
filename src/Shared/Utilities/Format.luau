--> Cash is read at a glance, mostly by children, so nothing past a thousand ever prints in full:
--> 50412 reads as 50.4K and 412800000 as 412.8M. A number a player cannot say out loud is a number
--> they cannot compare, and comparing prices is the whole game.
local Suffixes = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local Format = {}

--> Floored to one decimal rather than rounded, so a price never prints as less than it costs. A
--> whole tenth drops itself: Luau prints 1.0 as "1", which is the "1K" case.
local function Trim(Value: number): number
	return math.floor(Value * 10) / 10
end

--> Divided down rather than taken off a logarithm, which loses the boundaries: log(1000, 1000) is
--> a hair under 3 in floating point, so the exact powers land one suffix short.
function Format.Short(Value: number): string
	local Scaled = math.abs(Value)

	if Scaled < 1000 then
		return Trim(Scaled) .. ""
	end

	local Index = 0

	while Scaled >= 1000 and Index < #Suffixes do
		Scaled /= 1000
		Index += 1
	end

	return Trim(Scaled) .. Suffixes[Index]
end

--> The minus sits outside the currency, the way money is written everywhere but a spreadsheet.
function Format.Cash(Value: number): string
	return (if Value < 0 then "-$" else "$") .. Format.Short(Value)
end

function Format.Rate(Value: number): string
	return Format.Cash(Value) .. "/s"
end

--> A Robux price, behind the Robux glyph every Roblox font carries in its private range.
function Format.Robux(Value: number): string
	return utf8.char(0xE002) .. Value
end

return Format
