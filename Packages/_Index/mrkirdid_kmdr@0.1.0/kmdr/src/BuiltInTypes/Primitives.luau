--!strict
--[[
	Primitives.luau — string, text, number, integer and boolean built-ins,
	plus their comma-separated list variants.
]]

local Define = require(script.Parent.Parent.Define)
local Types = require(script.Parent.Parent.Types)
local Util = require(script.Parent.Parent.Util)

type ArgContext = Types.ArgContext
type Resolution<T> = Types.Resolution<T>

-- `Define.err`'s payload type only appears in its return type, which the new
-- solver cannot infer from the surrounding context — pin it per payload.
type Err<T> = (message: string, suggestions: { string }?) -> Resolution<T>
local errNumber = Define.err :: Err<number>
local errBoolean = Define.err :: Err<boolean>

local BOOLEAN_SUGGESTIONS = { "true", "false" }
local TRUE_WORDS: { [string]: boolean } = { ["true"] = true, yes = true, on = true, y = true, ["1"] = true }
local FALSE_WORDS: { [string]: boolean } = { ["false"] = true, no = true, off = true, n = true, ["0"] = true }

local stringType = Define.defineType({
	name = "string",
	resolve = function(text: string, _ctx: ArgContext): Resolution<string>
		return Define.ok(text)
	end,
})

-- Greedy: receives the raw rest of the line as one value.
local textType = Define.defineType({
	name = "text",
	resolve = function(text: string, _ctx: ArgContext): Resolution<string>
		return Define.ok(text)
	end,
	greedy = true,
})

local numberType = Define.defineType({
	name = "number",
	resolve = function(text: string, _ctx: ArgContext): Resolution<number>
		local value = tonumber(text)
		if value == nil then
			return errNumber(`'{text}' is not a number`)
		end
		return Define.ok(value)
	end,
})

local integerType = Define.defineType({
	name = "integer",
	resolve = function(text: string, _ctx: ArgContext): Resolution<number>
		local value = tonumber(text)
		if value == nil then
			return errNumber(`'{text}' is not a number`)
		end
		if value ~= math.floor(value) then
			return errNumber(`'{text}' is not an integer`)
		end
		return Define.ok(value)
	end,
})

local booleanType = Define.defineType({
	name = "boolean",
	resolve = function(text: string, _ctx: ArgContext): Resolution<boolean>
		local lowered = string.lower(text)
		if TRUE_WORDS[lowered] then
			return Define.ok(true)
		end
		if FALSE_WORDS[lowered] then
			return Define.ok(false)
		end
		if text == "" then
			return errBoolean("Enter true or false", BOOLEAN_SUGGESTIONS)
		end
		return errBoolean(`'{text}' is not a boolean`, Util.fuzzyFilter(text, BOOLEAN_SUGGESTIONS))
	end,
})

return {
	string = stringType,
	strings = Define.listOf(stringType, "strings"),
	text = textType,
	number = numberType,
	numbers = Define.listOf(numberType, "numbers"),
	integer = integerType,
	integers = Define.listOf(integerType, "integers"),
	boolean = booleanType,
	booleans = Define.listOf(booleanType, "booleans"),
}
