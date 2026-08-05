--!strict
--[[
	Misc.luau — userInput (KeyCode/UserInputType items), the registry meta
	types command and typeName, url and json.
]]

local HttpService = game:GetService("HttpService")

local Define = require(script.Parent.Parent.Define)
local Types = require(script.Parent.Parent.Types)
local Util = require(script.Parent.Parent.Util)

type ArgContext = Types.ArgContext
type Resolution<T> = Types.Resolution<T>

-- `Define.err`'s payload type only appears in its return type, which the new
-- solver cannot infer from the surrounding context — pin it per payload.
type Err<T> = (message: string, suggestions: { string }?) -> Resolution<T>
local errEnumItem = Define.err :: Err<EnumItem>
local errString = Define.err :: Err<string>
local errAny = Define.err :: Err<any>

-- KeyCode + UserInputType items, indexed once at load (they never change).
local userInputNames: { string } = {}
local userInputByLower: { [string]: EnumItem } = {}

local function addUserInputItem(item: EnumItem)
	local key = string.lower(item.Name)
	if userInputByLower[key] == nil then
		userInputByLower[key] = item
		table.insert(userInputNames, item.Name)
	end
end

for _, item in Enum.KeyCode:GetEnumItems() do
	addUserInputItem(item)
end
for _, item in Enum.UserInputType:GetEnumItems() do
	addUserInputItem(item)
end

local userInputType = Define.defineType({
	name = "userInput",
	resolve = function(text: string, _ctx: ArgContext): Resolution<EnumItem>
		if text == "" then
			return errEnumItem("Enter a key or input type", userInputNames)
		end
		local match = userInputByLower[string.lower(text)]
		if match ~= nil then
			return Define.ok(match)
		end
		return errEnumItem(`'{text}' is not a key or input type`, Util.fuzzyFilter(text, userInputNames))
	end,
})

local commandType = Define.defineType({
	name = "command",
	resolve = function(text: string, ctx: ArgContext): Resolution<string>
		local names = ctx.registry.getNames(true)
		if text == "" then
			return errString("Enter a command name", names)
		end
		local lowered = string.lower(text)
		for _, name in names do
			if string.lower(name) == lowered then
				return Define.ok(name, Util.fuzzyFilter(text, names))
			end
		end
		return errString(`'{text}' is not a command`, Util.fuzzyFilter(text, names))
	end,
})

local typeNameType = Define.defineType({
	name = "typeName",
	resolve = function(text: string, ctx: ArgContext): Resolution<string>
		local names = ctx.registry.getTypeNames()
		if text == "" then
			return errString("Enter a type name", names)
		end
		local lowered = string.lower(text)
		for _, name in names do
			if string.lower(name) == lowered then
				return Define.ok(name, Util.fuzzyFilter(text, names))
			end
		end
		return errString(`'{text}' is not a type name`, Util.fuzzyFilter(text, names))
	end,
})

local urlType = Define.defineType({
	name = "url",
	resolve = function(text: string, _ctx: ArgContext): Resolution<string>
		if text == "" then
			return errString("Enter a URL (https://...)")
		end
		if string.match(text, "^https?://") == nil then
			return errString(`'{text}' is not a URL (must start with http:// or https://)`)
		end
		return Define.ok(text)
	end,
})

local jsonType = Define.defineType({
	name = "json",
	resolve = function(text: string, _ctx: ArgContext): Resolution<any>
		if text == "" then
			return errAny("Enter a JSON value")
		end
		local success, result = pcall(function()
			return HttpService:JSONDecode(text)
		end)
		if not success then
			return errAny(`'{text}' is not valid JSON`)
		end
		return Define.ok(result)
	end,
})

return {
	userInput = userInputType,
	command = commandType,
	typeName = typeNameType,
	url = urlType,
	json = jsonType,
}
