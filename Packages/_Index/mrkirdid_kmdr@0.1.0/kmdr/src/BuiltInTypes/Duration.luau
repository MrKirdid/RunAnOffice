--!strict
--[[
	Duration.luau — compound durations ("1d2h30m15s", any subset, or plain
	seconds like "90") resolved to a number of seconds.
]]

local Define = require(script.Parent.Parent.Define)
local Types = require(script.Parent.Parent.Types)

type ArgContext = Types.ArgContext
type Resolution<T> = Types.Resolution<T>

-- `Define.err`'s payload type only appears in its return type, which the new
-- solver cannot infer from the surrounding context — pin it per payload.
local errDuration = Define.err :: (message: string, suggestions: { string }?) -> Resolution<number>

local UNIT_SECONDS: { [string]: number } = {
	d = 86400,
	h = 3600,
	m = 60,
	s = 1,
}

local function parseDuration(text: string): number?
	if text == "" then
		return nil
	end

	local plain = tonumber(text)
	if plain ~= nil then
		return if plain >= 0 then plain else nil
	end

	-- Valid compound input is nothing but amount+unit pairs.
	local leftover = string.gsub(text, "%d+%.?%d*[dhms]", "")
	if leftover ~= "" then
		return nil
	end

	local total = 0
	for amount, unit in string.gmatch(text, "(%d+%.?%d*)([dhms])") do
		total += (tonumber(amount) :: number) * UNIT_SECONDS[unit :: string]
	end
	return total
end

local durationType = Define.defineType({
	name = "duration",
	resolve = function(text: string, _ctx: ArgContext): Resolution<number>
		local seconds = parseDuration(text)
		if seconds == nil then
			return errDuration(`'{text}' is not a duration (use e.g. 1d2h30m15s, or plain seconds)`)
		end
		return Define.ok(seconds)
	end,
})

return {
	duration = durationType,
	durations = Define.listOf(durationType, "durations"),
}
