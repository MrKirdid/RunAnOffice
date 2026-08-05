--!strict
--[[
	Define.luau — the pure definition layer: defineType, listOf, defineCommand,
	implement, and the ok/err resolution helpers. No realm, no networking.
]]

local ArgsOf = require(script.Parent.ArgsOf)
local Parser = require(script.Parent.Parser)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)

type Arg<T> = Types.Arg<T>
type ArgContext = Types.ArgContext
type CommandContext = Types.CommandContext
type CommandDefinition<D> = Types.CommandDefinition<D>
type DefaultArg<T> = Types.DefaultArg<T>
type Implementation<D> = Types.Implementation<D>
type OptionalArg<T> = Types.OptionalArg<T>
type OrderedArg = Types.OrderedArg
type Resolution<T> = Types.Resolution<T>
type TypeHandle<T> = Types.TypeHandle<T>
type TypeSpec<T> = Types.TypeSpec<T>

local Define = {}

type ErasedTypeSpec = Types.ErasedTypeSpec

-- Type handles are plain functions; this maps them back to their specs.
local handleToSpec: { [any]: ErasedTypeSpec } = {}

-- Declaration-order counter: record fields evaluate in source order, so the
-- construction order of Arg values reproduces the written argument order.
local orderCounter = 0

local function nextOrder(): number
	orderCounter += 1
	return orderCounter
end

--[=[
	Successful resolution. `suggestions` optionally feeds autocomplete.
]=]
function Define.ok<T>(value: T, suggestions: { string }?): Resolution<T>
	return { ok = true :: true, value = value, suggestions = suggestions }
end

--[=[
	Failed resolution with a user-facing message; `suggestions` enables
	"did you mean" and autocomplete even for invalid prefixes.
]=]
function Define.err<T>(message: string, suggestions: { string }?): Resolution<T>
	return { ok = false :: false, error = message, suggestions = suggestions }
end

local function makeOptionalArg<T>(spec: TypeSpec<T>, summary: string?, order: number): OptionalArg<T>
	return {
		kind = "arg",
		isOptional = true,
		spec = spec,
		summary = summary,
		order = order,
		defaultValue = nil,
	} :: any
end

local function makeDefaultArg<T>(spec: TypeSpec<T>, summary: string?, order: number, value: T): DefaultArg<T>
	return {
		kind = "arg",
		isOptional = false,
		spec = spec,
		summary = summary,
		order = order,
		defaultValue = value,
	} :: any
end

local function makeArg<T>(spec: TypeSpec<T>, summary: string?): Arg<T>
	local order = nextOrder()
	return {
		kind = "arg",
		isOptional = false,
		spec = spec,
		summary = summary,
		order = order,
		defaultValue = nil,
		optional = function(_self: Arg<T>): OptionalArg<T>
			return makeOptionalArg(spec, summary, order)
		end,
		default = function(_self: Arg<T>, value: T): DefaultArg<T>
			return makeDefaultArg(spec, summary, order, value)
		end,
	} :: any
end

export type DefineTypeInput<T> = {
	read name: string,
	read displayName: string?,
	read resolve: (text: string, ctx: ArgContext) -> Resolution<T>,
	--- Greedy types consume the rest of the line (only valid as the last argument).
	read greedy: boolean?,
}

--[=[
	Creates an argument type. `T` is captured from `resolve`'s return type.
	Returns the handle used in args records: `myType("summary")`.
]=]
function Define.defineType<T>(input: DefineTypeInput<T>): TypeHandle<T>
	assert(type(input.name) == "string" and #input.name > 0, "defineType: `name` must be a non-empty string")
	assert(type(input.resolve) == "function", `defineType('{input.name}'): \`resolve\` must be a function`)

	local spec: TypeSpec<T> = {
		kind = "typeSpec",
		name = input.name,
		displayName = input.displayName or input.name,
		resolve = input.resolve,
		listElement = nil,
		greedy = input.greedy,
	} :: any

	local handle = function(summary: string?): Arg<T>
		return makeArg(spec, summary)
	end
	handleToSpec[handle] = spec :: any
	return handle
end

--[=[
	Derives a comma-separated list type from an element type:
	`t.players = Kmdr.listOf(t.player, "players")`. Duplicate values collapse.
]=]
function Define.listOf<T>(element: TypeHandle<T>, name: string?): TypeHandle<{ T }>
	local elementSpec = handleToSpec[element]
	assert(elementSpec ~= nil, "listOf: expected a type handle created by defineType")

	local listName = name or `{elementSpec.name}List`

	local function resolveList(_text: string, ctx: ArgContext): Resolution<{ T }>
		local values: { T } = {}
		local seen: { [any]: boolean } = {}
		local elements = Parser.splitList(ctx.rawToken)
		for _, elementText in elements do
			local resolution = elementSpec.resolve(elementText, ctx)
			if not resolution.ok then
				return { ok = false :: false, error = resolution.error, suggestions = resolution.suggestions }
			end
			if not seen[resolution.value] then
				seen[resolution.value] = true
				table.insert(values, resolution.value)
			end
		end
		return Define.ok(values)
	end

	local spec: TypeSpec<{ T }> = {
		kind = "typeSpec",
		name = listName,
		displayName = `{elementSpec.displayName} list`,
		resolve = resolveList,
		listElement = elementSpec,
	} :: any

	local handle = function(summary: string?): Arg<{ T }>
		return makeArg(spec, summary)
	end
	handleToSpec[handle] = spec :: TypeSpec<any>
	return handle
end

--[=[
	Creates an enum type from a list of string values. When the values are
	literal, `T` is their singleton union (`Type<"fast" | "slow">`).
	Matching is case-insensitive; suggestions are fuzzy.
]=]
function Define.enumOf<T>(name: string, values: { T }): TypeHandle<T>
	local labels: { string } = {}
	local byLower: { [string]: T } = {}
	for _, value in values do
		assert(type(value) == "string", `enumOf('{name}'): values must be strings`)
		table.insert(labels, value :: any)
		byLower[string.lower(value :: any)] = value
	end

	return Define.defineType({
		name = name,
		resolve = function(text: string, _ctx: ArgContext): Resolution<T>
			local match = byLower[string.lower(text)]
			if match ~= nil then
				return Define.ok(match)
			end
			local suggestions = Util.fuzzyFilter(text, labels)
			return Define.err(`'{text}' is not a valid {name}`, suggestions)
		end,
	})
end

--[=[
	Looks up the spec behind a handle (registry, remote-type rebinding).
]=]
function Define.specOf(handle: any): ErasedTypeSpec?
	return handleToSpec[handle]
end

local NAME_PATTERN = "^[%w%-_=!%?%.]+$"

--[=[
	Creates a command definition from a pure-data table. The generic `D`
	carries the literal definition type so ArgsOf can derive the run record.
]=]
function Define.defineCommand<D>(def: D): CommandDefinition<D>
	local raw = def :: any
	assert(type(raw) == "table", "defineCommand expects a definition table")
	assert(
		type(raw.name) == "string" and string.match(raw.name, NAME_PATTERN) ~= nil,
		"defineCommand: `name` must be a string of word characters (no spaces)"
	)

	local aliases: { string } = {}
	if raw.aliases ~= nil then
		assert(type(raw.aliases) == "table", `defineCommand('{raw.name}'): \`aliases\` must be an array of strings`)
		for _, alias in raw.aliases :: { any } do
			assert(
				type(alias) == "string" and string.match(alias, NAME_PATTERN) ~= nil,
				`defineCommand('{raw.name}'): alias must be a string of word characters`
			)
			table.insert(aliases, alias)
		end
	end

	local orderedArgs: { OrderedArg } = {}
	if raw.args ~= nil then
		assert(type(raw.args) == "table", `defineCommand('{raw.name}'): \`args\` must be a record`)
		type PendingArg = {
			key: string,
			arg: {
				kind: string,
				order: number,
				isOptional: boolean,
				defaultValue: any,
				spec: ErasedTypeSpec,
				summary: string?,
			},
		}
		local working: { PendingArg } = {}
		for key, value in raw.args :: { [any]: any } do
			assert(type(key) == "string", `defineCommand('{raw.name}'): argument keys must be strings`)
			if type(value) == "function" then
				error(
					`defineCommand('{raw.name}'): argument '{key}' is a raw type handle — call it: `
						.. `\`{key} = t.{key}(...)\` (declaration order is recovered from the call)`,
					2
				)
			end
			assert(
				type(value) == "table" and value.kind == "arg",
				`defineCommand('{raw.name}'): argument '{key}' must be created from a type handle`
			)
			table.insert(working, { key = key, arg = value } :: PendingArg)
		end
		table.sort(working, function(a: PendingArg, b: PendingArg)
			return a.arg.order < b.arg.order
		end)

		local sawOptional = false
		for _, item in working do
			local arg = item.arg
			local isOptional = arg.isOptional == true
			local hasDefault = arg.defaultValue ~= nil
			if sawOptional and not (isOptional or hasDefault) then
				error(`defineCommand('{raw.name}'): required argument '{item.key}' cannot follow an optional one`, 2)
			end
			if isOptional or hasDefault then
				sawOptional = true
			end
			table.insert(orderedArgs, {
				key = item.key,
				spec = arg.spec,
				summary = arg.summary,
				isOptional = isOptional,
				hasDefault = hasDefault,
				defaultValue = arg.defaultValue,
			})
		end
	end

	return {
		kind = "commandDefinition",
		name = raw.name,
		aliases = aliases,
		description = raw.description,
		group = raw.group,
		permission = raw.permission,
		orderedArgs = orderedArgs,
	} :: any
end

--[=[
	Pairs a definition with a run callback. The callback's `args` parameter is
	typed by the ArgsOf type function — no annotations needed at the call site.
	(The erased signature stored at runtime is `(ctx, { [string]: any })`.)
]=]
function Define.implement<D>(
	def: CommandDefinition<D>,
	fn: (ctx: CommandContext, args: ArgsOf.ArgsOf<D>) -> string?
): Implementation<D>
	assert(
		type(def) == "table" and def.kind == "commandDefinition",
		"implement: first argument must be a command definition"
	)
	assert(type(fn) == "function", `implement('{def.name}'): second argument must be the run callback`)
	return {
		kind = "implementation",
		def = def,
		fn = fn :: any,
	}
end

return Define
