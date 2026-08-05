--!strict
--[[
	Kmdr — a strictly-typed, modern command console for Roblox.
	Reimagining of evaera's Cmdr for the new Luau type solver.

	Server bootstrap:
		local Kmdr = require(ReplicatedStorage.Packages.Kmdr)
		local server = Kmdr.server()
		server:addGuard(function(ctx) ... end)   -- required outside Studio
		server.registerDefaults()
		server.registerFolder(ServerScriptService.Commands)

	Client bootstrap:
		local Kmdr = require(ReplicatedStorage.Packages.Kmdr)
		local client = Kmdr.client()
		client.registerDefaults()
]]

local ArgsOfModule = require(script.ArgsOf)
local BuiltInTypes = require(script.BuiltInTypes)
local Client = require(script.Client)
local Define = require(script.Define)
local Dispatcher = require(script.Dispatcher)
local Server = require(script.Server)
local Types = require(script.Types)
local Util = require(script.Util)

-- ── Public type re-exports ─────────────────────────────────────────────
export type Arg<T> = Types.Arg<T>
export type ArgContext = Types.ArgContext
export type ArgsOf<D> = ArgsOfModule.ArgsOf<D>
export type CommandContext = Types.CommandContext
export type CommandDefinition<D> = Types.CommandDefinition<D>
export type Evaluation = Dispatcher.Evaluation
export type Guard = Types.Guard
export type Implementation<D> = Types.Implementation<D>
export type KmdrClient = Client.KmdrClient
export type KmdrServer = Server.KmdrServer
export type OutputLine = Client.OutputLine
export type Realm = Types.Realm
export type ReplyKind = Types.ReplyKind
export type Resolution<T> = Types.Resolution<T>
export type Token = Types.Token
export type TypeHandle<T> = Types.TypeHandle<T>
export type TypeSpec<T> = Types.TypeSpec<T>

export type ClientOptions = {
	--- Keys that toggle the console. Default: { Enum.KeyCode.F2 }.
	read activationKeys: { Enum.KeyCode }?,
	--- Label shown in the prompt, e.g. the place name. Default: "kmdr".
	read placeLabel: string?,
	--- Hide the console when the game window loses focus. Default: false.
	read hideOnFocusLoss: boolean?,
}

local interfaceMounted = false

local Kmdr = {
	--- Creates a command definition (pure data — safe for ReplicatedStorage).
	defineCommand = Define.defineCommand,
	--- Creates an argument type; returns its handle for args records.
	defineType = Define.defineType,
	--- Pairs a definition with a run callback; `args` arrives fully typed.
	implement = Define.implement,
	--- List type from an element type (comma-separated, quote-aware).
	listOf = Define.listOf,
	--- Enum type from string literals.
	enumOf = Define.enumOf,
	--- Resolution helpers for defineType.
	ok = Define.ok,
	err = Define.err,
	--- Built-in type handles: Kmdr.types.player, .integer, .text, …
	types = BuiltInTypes.handles,
	--- Fuzzy matching and small helpers, exposed for custom types.
	util = Util,

	--- The server singleton (server realm only).
	server = Server.get,

	--- The client singleton (client realm only); mounts the interface once.
	client = function(options: ClientOptions?): Client.KmdrClient
		local client = Client.get()
		if not interfaceMounted then
			interfaceMounted = true
			local Interface = require(script.Interface) :: any
			Interface.mount(client, options)
		end
		return client
	end,
}

return Kmdr
