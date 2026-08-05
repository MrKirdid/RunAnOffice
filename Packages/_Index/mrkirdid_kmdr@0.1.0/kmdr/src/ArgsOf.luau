--!strict
--# selene: allow(undefined_variable) -- `types` is the type-function environment global
--[[
	ArgsOf.luau — user-defined type functions.

	`ArgsOf<D>` maps a command definition table type D to the typed record a run
	callback receives: each `args` property's Arg<T> collapses to T (optionals
	to T?). Malformed definitions produce a type error at the definition site.

	The bodies lean on `any` casts: the `types` userdata typing does not refine
	cleanly under the analysis environment. Reduction behavior is unaffected —
	the derivation itself is exercised by test/spec and the dev place.
]]

--[=[
	Derives `{ read <argKey>: T }` from `index<D, "args">`, honoring
	`isOptional: true` (→ `T?`) and raw type handles (functions returning Arg<T>).
]=]
export type function ArgsOf(def)
	assert(def:is("table"), "ArgsOf expects a command definition table type")
	local args = def:readproperty(types.singleton("args"))
	if args == nil then
		-- No args declared: the run callback receives an empty record.
		return types.newtable()
	end
	assert(args:is("table"), "`args` must be a record of Arg values")

	local result = types.newtable()
	for key, prop in args:properties() do
		local raw = (prop.read or prop.write) :: any
		assert(raw ~= nil, "argument property carries no type")

		local argTable: any = raw
		if raw:is("function") then
			local head = raw:returns().head
			assert(head ~= nil and head[1] ~= nil, "type handle returns nothing")
			argTable = head[1]
		end
		assert(argTable:is("table"), `argument '{tostring(key)}' must be an Arg or a type handle`)

		local value = argTable:readproperty(types.singleton("__value"))
		assert(value ~= nil, `argument '{tostring(key)}' is missing its type parameter`)

		local isOpt = argTable:readproperty(types.singleton("isOptional"))
		if isOpt ~= nil and isOpt:is("singleton") and isOpt:value() == true then
			value = types.optional(value)
		end
		result:setreadproperty(key, value)
	end
	return result
end

return nil
