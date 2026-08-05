--!strict
--[[
	Types.luau — every public type Kmdr exports.

	Conventions:
	- All public-facing table types use `read` properties: consumers can rely on
	  them, never mutate them.
	- `__value: T` fields are phantom carriers: they never exist at runtime, they
	  only let the ArgsOf type function recover T. Construction sites cast.
	- No setmetatable-based generic aliases and no intersection overloads — both
	  are known new-solver trouble spots.
]]

export type Realm = "server" | "client"

--[=[
	The result of resolving a raw token against an argument type.
	`suggestions` powers autocomplete and is meaningful in both variants:
	a failed resolution can still suggest ("did you mean").
]=]
export type Resolution<T> =
	{
		read ok: true,
		read value: T,
		read suggestions: { string }?,
	}
	| {
		read ok: false,
		read error: string,
		read suggestions: { string }?,
	}

--[=[
	Structural view of the registry available to argument types — enough to
	build meta types (command names, type names) without a module cycle.
]=]
export type RegistryView = {
	read getNames: (includeAliases: boolean?) -> { string },
	read getTypeNames: () -> { string },
}

--[=[
	Context handed to a type's `resolve` and `suggest` calls.
]=]
export type ArgContext = {
	read realm: Realm,
	read executor: Player?,
	read registry: RegistryView,
	--- Raw text of the whole line, for context-sensitive types.
	read rawText: string,
	--- The raw (quotes intact) slice of the token being resolved. List types
	--- comma-split this; plain types can ignore it.
	read rawToken: string,
	--- The name the argument was declared under.
	read argKey: string,
}

--[=[
	A runtime argument type: how one token becomes one value.
	Create with `Kmdr.defineType`; `T` is captured from `resolve`'s return.
]=]
--[=[
	Erased view of a TypeSpec — used wherever the payload type is unknown
	(registries, list elements). A generic type cannot recursively reference
	itself with different parameters, hence the separate alias.
]=]
export type ErasedTypeSpec = {
	read kind: "typeSpec",
	read name: string,
	read displayName: string,
	read resolve: (text: string, ctx: ArgContext) -> Resolution<any>,
	read listElement: ErasedTypeSpec?,
	read greedy: boolean?,
}

export type TypeSpec<T> = {
	read kind: "typeSpec",
	read name: string,
	read displayName: string,
	--- Single code path for validation, autocomplete and parsing.
	read resolve: (text: string, ctx: ArgContext) -> Resolution<T>,
	--- Present on list types (created via `Kmdr.listOf`): the element spec.
	--- The interface uses it to autocomplete the last comma-segment.
	read listElement: ErasedTypeSpec?,
	--- Greedy types (e.g. `t.text`) consume the rest of the line as one value.
	--- Only valid on the final argument.
	read greedy: boolean?,
	read __value: T,
}

--[=[
	A type handle is what lives in `Kmdr.types` and what `defineType` returns:
	calling it (optionally with a summary) produces an `Arg<T>` for an args record.
	The handle can also be used raw in an args record.
]=]
export type TypeHandle<T> = (summary: string?) -> Arg<T>

--[=[
	One declared argument. Record-key = argument name; declaration order is
	recovered from `order` (a module-level counter incremented per construction,
	table constructors evaluate fields in source order).
]=]
export type Arg<T> = {
	read kind: "arg",
	read isOptional: false,
	read spec: TypeSpec<T>,
	read summary: string?,
	read order: number,
	read defaultValue: nil,
	--- Marks the argument optional: run receives `T?`. Optionals must be trailing.
	read optional: (self: Arg<T>) -> OptionalArg<T>,
	--- Provides a default: input may omit the argument, run still receives `T`.
	read default: (self: Arg<T>, value: T) -> DefaultArg<T>,
	read __value: T,
}

export type OptionalArg<T> = {
	read kind: "arg",
	read isOptional: true,
	read spec: TypeSpec<T>,
	read summary: string?,
	read order: number,
	read defaultValue: nil,
	read __value: T,
}

export type DefaultArg<T> = {
	read kind: "arg",
	read isOptional: false,
	read spec: TypeSpec<T>,
	read summary: string?,
	read order: number,
	read defaultValue: T,
	read __value: T,
}

--[=[
	Runtime (erased) view of a declared argument, in declaration order.
]=]
export type OrderedArg = {
	read key: string,
	read spec: ErasedTypeSpec,
	read summary: string?,
	read isOptional: boolean,
	read hasDefault: boolean,
	read defaultValue: any,
}

--[=[
	A command definition: pure data, safe to place in ReplicatedStorage.
	`D` carries the original definition table type for ArgsOf derivation.
]=]
export type CommandDefinition<D> = {
	read kind: "commandDefinition",
	read name: string,
	read aliases: { string },
	read description: string?,
	read group: string?,
	--- Free-form tag surfaced to guards (e.g. "kmdr.admin").
	read permission: string?,
	read orderedArgs: { OrderedArg },
	read __def: D,
}

--[=[
	definition + callback, produced by `Kmdr.implement`. Register on the realm
	the callback belongs to; the definition rides along.
]=]
export type Implementation<D> = {
	read kind: "implementation",
	read def: CommandDefinition<D>,
	read fn: (ctx: CommandContext, args: { [string]: any }) -> string?,
}

export type ReplyKind = "info" | "success" | "warning" | "error" | "echo"

--[=[
	Handed to every run callback and guard.
]=]
export type CommandContext = {
	read realm: Realm,
	--- The player who ran the command. Nil only for programmatic server runs.
	read executor: Player?,
	read rawText: string,
	--- The name or alias the command was invoked with.
	read alias: string,
	read name: string,
	read group: string?,
	read permission: string?,
	--- Untyped view of the parsed arguments (guards, generic tooling).
	read argValues: { [string]: any },
	--- Sends an extra line to the invoking player's console (server: replicated).
	read reply: (self: CommandContext, message: string, kind: ReplyKind?) -> (),
	--- Named persistent table scoped to the registry (cross-command state).
	read getStore: (self: CommandContext, name: string) -> { [any]: any },
}

--[=[
	Guards decide whether a command may run. Return nil to allow, or a message
	to deny. Server guards are authoritative; client guards are fast local UX.
]=]
export type Guard = (ctx: CommandContext) -> string?

--- Post-run observer (logging, analytics). Never blocks.
export type RanObserver = (ctx: CommandContext, response: string?) -> ()

--[=[
	One token of a parsed line, with its exact character span (1-based,
	inclusive) — the interface uses spans for cursor-aware completion,
	signature help and error tinting.
]=]
export type Token = {
	read text: string,
	read rawText: string,
	read startPos: number,
	read endPos: number,
	read quoted: boolean,
	read closed: boolean,
}

--[=[
	Serialized command metadata the server syncs to clients so autocomplete
	knows server-side commands without replicating any code.
]=]
export type RemoteArgSpec = {
	read key: string,
	read typeName: string,
	read summary: string?,
	read isOptional: boolean,
	read hasDefault: boolean,
}

export type RemoteCommandMeta = {
	read name: string,
	read aliases: { string },
	read description: string?,
	read group: string?,
	read permission: string?,
	--- Whether the origin realm has a callback for this command.
	read hasImpl: boolean,
	read args: { RemoteArgSpec },
}

export type ExecResponse = {
	read ok: boolean,
	read message: string?,
}

return nil
