--!strict
--[[
	Registry.luau — per-realm store of commands, argument types, guards,
	observers and cross-command stores. Closure-style object: two instances
	exist per game (one server, one client), so per-instance closures are free
	and type beautifully in strict mode.
]]

local Define = require(script.Parent.Define)
local Types = require(script.Parent.Types)

type CommandContext = Types.CommandContext
type CommandDefinition<D> = Types.CommandDefinition<D>
type ErasedTypeSpec = Types.ErasedTypeSpec
type Guard = Types.Guard
type RanObserver = Types.RanObserver
type Realm = Types.Realm
type RemoteArgSpec = Types.RemoteArgSpec
type RemoteCommandMeta = Types.RemoteCommandMeta

--[=[
	Argument spec in the shape the dispatcher consumes — unified between local
	definitions (spec present) and remote metadata (spec looked up by name,
	nil when the client doesn't know the type → raw string passthrough).
]=]
export type EffectiveArgSpec = {
	read key: string,
	read typeName: string,
	read displayName: string,
	read summary: string?,
	read isOptional: boolean,
	read hasDefault: boolean,
	read defaultValue: any,
	read spec: ErasedTypeSpec?,
}

export type CommandEntry = {
	name: string,
	def: CommandDefinition<any>?,
	meta: RemoteCommandMeta,
	fn: ((ctx: CommandContext, args: { [string]: any }) -> string?)?,
	--- True when this entry came from server metadata sync (no local code).
	isRemote: boolean,
	--- True when the *server* holds a callback (client uses this to forward).
	serverHasImpl: boolean,
}

export type Registry = {
	read realm: Realm,
	read registerType: (handle: any) -> (),
	read getTypeSpec: (name: string) -> ErasedTypeSpec?,
	read getTypeNames: () -> { string },
	read register: (defOrImpl: any) -> (),
	read registerFolder: (folder: Instance) -> (),
	read mergeRemote: (metas: { RemoteCommandMeta }) -> (),
	read getEntry: (nameOrAlias: string) -> CommandEntry?,
	read getEntries: () -> { CommandEntry },
	read getNames: (includeAliases: boolean?) -> { string },
	read argSpecsFor: (entry: CommandEntry) -> { EffectiveArgSpec },
	read addGuard: (guard: Guard, priority: number?) -> (),
	read guardCount: () -> number,
	read runGuards: (ctx: CommandContext) -> string?,
	read onRan: (observer: RanObserver) -> () -> (),
	read fireRan: (ctx: CommandContext, response: string?) -> (),
	read getStore: (name: string) -> { [any]: any },
	read onEntryAdded: (callback: (entry: CommandEntry) -> ()) -> (),
	read metas: () -> { RemoteCommandMeta },
}

local Registry = {}

local function metaFromDef(def: CommandDefinition<any>, hasImpl: boolean): RemoteCommandMeta
	local args: { RemoteArgSpec } = {}
	for _, arg in def.orderedArgs do
		table.insert(args, {
			key = arg.key,
			typeName = arg.spec.name,
			summary = arg.summary,
			isOptional = arg.isOptional,
			hasDefault = arg.hasDefault,
		})
	end
	return {
		name = def.name,
		aliases = def.aliases,
		description = def.description,
		group = def.group,
		permission = def.permission,
		hasImpl = hasImpl,
		args = args,
	}
end

function Registry.new(realm: Realm): Registry
	local entries: { [string]: CommandEntry } = {} -- keyed by lowercase name
	local aliasLookup: { [string]: CommandEntry } = {} -- lowercase alias → entry
	local entryList: { CommandEntry } = {}
	local typeSpecs: { [string]: ErasedTypeSpec } = {}

	type PrioritizedGuard = { guard: Guard, priority: number, sequence: number }
	local guards: { PrioritizedGuard } = {}
	local guardSequence = 0

	local ranObservers: { [RanObserver]: boolean } = {}
	local stores: { [string]: { [any]: any } } = {}
	local entryAddedCallbacks: { (entry: CommandEntry) -> () } = {}

	local self: Registry

	local function announceEntry(entry: CommandEntry)
		for _, callback in entryAddedCallbacks do
			task.spawn(callback, entry)
		end
	end

	local function indexEntry(entry: CommandEntry)
		entries[string.lower(entry.name)] = entry
		for _, alias in entry.meta.aliases do
			local key = string.lower(alias)
			if aliasLookup[key] == nil or aliasLookup[key] == entry then
				aliasLookup[key] = entry
			else
				warn(
					`[Kmdr] alias '{alias}' of '{entry.name}' clashes with '{aliasLookup[key].name}'; keeping the first`
				)
			end
		end
	end

	local function upsert(
		def: CommandDefinition<any>?,
		meta: RemoteCommandMeta,
		fn: ((ctx: CommandContext, args: { [string]: any }) -> string?)?,
		isRemote: boolean
	)
		local key = string.lower(meta.name)
		local existing = entries[key]
		if existing == nil then
			local entry: CommandEntry = {
				name = meta.name,
				def = def,
				meta = meta,
				fn = fn,
				isRemote = isRemote,
				serverHasImpl = if realm == "server" then fn ~= nil else isRemote and meta.hasImpl,
			}
			table.insert(entryList, entry)
			indexEntry(entry)
			announceEntry(entry)
			return
		end

		-- Merge: local information always beats remote metadata; a callback is
		-- never displaced by a callback-less registration.
		if fn ~= nil and existing.fn ~= nil and existing.fn ~= fn then
			warn(`[Kmdr] command '{meta.name}' registered twice with different callbacks; replacing`)
		end
		if isRemote then
			existing.serverHasImpl = existing.serverHasImpl or meta.hasImpl
			if existing.def == nil then
				existing.meta = meta
			end
		else
			existing.def = def or existing.def
			existing.fn = fn or existing.fn
			existing.isRemote = false
			if realm == "server" then
				existing.serverHasImpl = existing.fn ~= nil
			end
			if def ~= nil then
				existing.meta = metaFromDef(def, existing.fn ~= nil)
			end
			indexEntry(existing)
		end
		announceEntry(existing)
	end

	local function register(defOrImpl: any)
		assert(
			type(defOrImpl) == "table",
			"register: expected a definition, an implement() bundle, or an array of them"
		)
		if defOrImpl.kind == "commandDefinition" then
			local def = defOrImpl :: CommandDefinition<any>
			upsert(def, metaFromDef(def, false), nil, false)
		elseif defOrImpl.kind == "implementation" then
			local def = defOrImpl.def :: CommandDefinition<any>
			upsert(def, metaFromDef(def, true), defOrImpl.fn, false)
		else
			-- Array of definitions/bundles.
			local count = 0
			for _, item in defOrImpl :: { any } do
				register(item)
				count += 1
			end
			assert(count > 0, "register: table is neither a definition, an implement() bundle, nor a non-empty array")
		end
	end

	local function registerFolder(folder: Instance)
		for _, child in folder:GetDescendants() do
			if child:IsA("ModuleScript") then
				local result = require(child) :: any
				register(result)
			end
		end
	end

	local function registerType(handle: any)
		local spec = Define.specOf(handle)
		assert(spec ~= nil, "registerType: expected a type handle created by defineType/listOf")
		typeSpecs[spec.name] = spec
		local element = spec.listElement
		if element ~= nil and typeSpecs[element.name] == nil then
			typeSpecs[element.name] = element
		end
	end

	local function mergeRemote(metas: { RemoteCommandMeta })
		for _, meta in metas do
			upsert(nil, meta, nil, true)
		end
	end

	local function argSpecsFor(entry: CommandEntry): { EffectiveArgSpec }
		local result: { EffectiveArgSpec } = {}
		local def = entry.def
		if def ~= nil then
			for _, arg in def.orderedArgs do
				table.insert(result, {
					key = arg.key,
					typeName = arg.spec.name,
					displayName = arg.spec.displayName,
					summary = arg.summary,
					isOptional = arg.isOptional,
					hasDefault = arg.hasDefault,
					defaultValue = arg.defaultValue,
					spec = arg.spec,
				})
			end
		else
			for _, arg in entry.meta.args do
				local spec = typeSpecs[arg.typeName]
				table.insert(result, {
					key = arg.key,
					typeName = arg.typeName,
					displayName = if spec ~= nil then spec.displayName else arg.typeName,
					summary = arg.summary,
					isOptional = arg.isOptional,
					hasDefault = arg.hasDefault,
					defaultValue = nil,
					spec = spec,
				})
			end
		end
		return result
	end

	self = {
		realm = realm,
		registerType = registerType,
		getTypeSpec = function(name: string): ErasedTypeSpec?
			return typeSpecs[name]
		end,
		getTypeNames = function(): { string }
			local names: { string } = {}
			for name in typeSpecs do
				table.insert(names, name)
			end
			table.sort(names)
			return names
		end,
		register = register,
		registerFolder = registerFolder,
		mergeRemote = mergeRemote,
		getEntry = function(nameOrAlias: string): CommandEntry?
			local key = string.lower(nameOrAlias)
			return entries[key] or aliasLookup[key]
		end,
		getEntries = function(): { CommandEntry }
			return table.clone(entryList)
		end,
		getNames = function(includeAliases: boolean?): { string }
			local names: { string } = {}
			for _, entry in entryList do
				table.insert(names, entry.name)
				if includeAliases then
					for _, alias in entry.meta.aliases do
						table.insert(names, alias)
					end
				end
			end
			table.sort(names)
			return names
		end,
		argSpecsFor = argSpecsFor,
		addGuard = function(guard: Guard, priority: number?)
			guardSequence += 1
			table.insert(guards, { guard = guard, priority = priority or 0, sequence = guardSequence })
			table.sort(guards, function(a: PrioritizedGuard, b: PrioritizedGuard)
				if a.priority ~= b.priority then
					return a.priority < b.priority
				end
				return a.sequence < b.sequence
			end)
		end,
		guardCount = function(): number
			return #guards
		end,
		runGuards = function(ctx: CommandContext): string?
			for _, item in guards do
				local verdict = item.guard(ctx)
				if verdict ~= nil then
					return verdict
				end
			end
			return nil
		end,
		onRan = function(observer: RanObserver): () -> ()
			ranObservers[observer] = true
			return function()
				ranObservers[observer] = nil
			end
		end,
		fireRan = function(ctx: CommandContext, response: string?)
			for observer in ranObservers do
				task.spawn(observer, ctx, response)
			end
		end,
		getStore = function(name: string): { [any]: any }
			local store = stores[name]
			if store == nil then
				store = {}
				stores[name] = store
			end
			return store
		end,
		onEntryAdded = function(callback: (entry: CommandEntry) -> ())
			table.insert(entryAddedCallbacks, callback)
		end,
		metas = function(): { RemoteCommandMeta }
			local result: { RemoteCommandMeta } = {}
			for _, entry in entryList do
				table.insert(result, entry.meta)
			end
			return result
		end,
	}

	return self
end

return Registry
