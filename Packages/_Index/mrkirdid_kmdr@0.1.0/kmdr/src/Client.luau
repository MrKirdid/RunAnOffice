--!strict
--[[
	Client.luau — the client engine: client registry, alias expansion, history,
	the output line stream, and the client half of networking (exec invoke +
	metadata sync). Deliberately interface-free — the Fusion interface mounts
	on top and subscribes to the line stream.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local BuiltInTypes = require(script.Parent.BuiltInTypes)
local Dispatcher = require(script.Parent.Dispatcher)
local Parser = require(script.Parent.Parser)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Types)

type ExecResponse = Types.ExecResponse
type Guard = Types.Guard
type RanObserver = Types.RanObserver
type RemoteCommandMeta = Types.RemoteCommandMeta
type ReplyKind = Types.ReplyKind

local HISTORY_LIMIT = 100
local LINE_BUFFER_LIMIT = 300
local ALIAS_DEPTH_LIMIT = 8
local REMOTE_WAIT_TIMEOUT = 10

export type OutputLine = {
	read text: string,
	read kind: ReplyKind,
}

export type KmdrClient = {
	read registry: Registry.Registry,
	read register: (defOrImpl: any) -> (),
	read registerFolder: (folder: Instance) -> (),
	read registerType: (handle: any) -> (),
	read registerDefaults: () -> (),
	read addGuard: (guard: Guard, priority: number?) -> (),
	read onRan: (observer: RanObserver) -> () -> (),
	read getStore: (name: string) -> { [any]: any },
	--- Runs a line as the local player. Asynchronous; results arrive as lines.
	read run: (text: string) -> (),
	--- Live evaluation for the interface (validation, signature help).
	read evaluate: (text: string) -> Dispatcher.Evaluation,
	--- Subscribes to output lines; the recent buffer is replayed immediately.
	read onLine: (callback: (line: OutputLine) -> ()) -> () -> (),
	read emit: (text: string, kind: ReplyKind?) -> (),
	--- Clears the output log (and the replay buffer).
	read clear: () -> (),
	read onClear: (callback: () -> ()) -> () -> (),
	read getHistory: () -> { string },
	read addAlias: (name: string, expansion: string) -> (),
	read removeAlias: (name: string) -> boolean,
	read getAliases: () -> { [string]: string },
	--- True once the server metadata sync has arrived.
	read isSynced: () -> boolean,
}

local Client = {}

local singleton: KmdrClient? = nil

local function create(): KmdrClient
	assert(RunService:IsClient(), "Kmdr.client() may only be called from a client")

	local registry = Registry.new("client")
	for _, handle in BuiltInTypes.all do
		registry.registerType(handle)
	end

	local root = script.Parent

	-- ── Output stream ──────────────────────────────────────────────────
	local lineBuffer: { OutputLine } = {}
	local lineSubscribers: { [(line: OutputLine) -> ()]: boolean } = {}

	local function emit(text: string, kind: ReplyKind?)
		local line: OutputLine = { text = text, kind = kind or "info" }
		table.insert(lineBuffer, line)
		if #lineBuffer > LINE_BUFFER_LIMIT then
			table.remove(lineBuffer, 1)
		end
		for subscriber in lineSubscribers do
			task.spawn(subscriber, line)
		end
	end

	-- ── Networking (tolerates a server that never initializes Kmdr) ────
	local execRemote: RemoteFunction? = nil
	local synced = false

	task.spawn(function()
		local exec = root:WaitForChild("Exec", REMOTE_WAIT_TIMEOUT)
		local event = root:WaitForChild("Event", REMOTE_WAIT_TIMEOUT)
		if exec == nil or event == nil then
			warn("[Kmdr] server never initialized Kmdr — running client-only")
			return
		end
		execRemote = exec :: RemoteFunction
		local eventRemote = event :: RemoteEvent

		eventRemote.OnClientEvent:Connect(function(message: unknown, payload: unknown)
			if message == "sync" and type(payload) == "table" then
				synced = true
				registry.mergeRemote(payload :: { RemoteCommandMeta })
			elseif message == "reply" and type(payload) == "table" then
				local reply = payload :: { message: string?, kind: string? }
				if type(reply.message) == "string" then
					emit(reply.message, (reply.kind :: ReplyKind?) or "info")
				end
			end
		end)
		eventRemote:FireServer("requestSync")
	end)

	-- ── History ────────────────────────────────────────────────────────
	local history: { string } = {}

	local function pushHistory(text: string)
		-- Collapse consecutive duplicates, fish-style.
		if history[#history] == text then
			return
		end
		table.insert(history, text)
		if #history > HISTORY_LIMIT then
			table.remove(history, 1)
		end
	end

	-- ── Aliases ────────────────────────────────────────────────────────
	local aliases: { [string]: string } = {}

	local function expandOnce(text: string): (string, boolean)
		local tokens = Parser.tokenize(text)
		local first = tokens[1]
		if first == nil then
			return text, false
		end
		local expansion = aliases[string.lower(first.text)]
		if expansion == nil then
			return text, false
		end

		local argTokens: { Types.Token } = {}
		for index = 2, #tokens do
			table.insert(argTokens, tokens[index])
		end

		local used: { [number]: boolean } = {}
		local result = string.gsub(expansion, "%$(%d)", function(digit: string): string
			local index = tonumber(digit) :: number
			used[index] = true
			local token = argTokens[index]
			return if token ~= nil then token.rawText else ""
		end)
		if string.find(result, "%$%*") ~= nil then
			local rest: { string } = {}
			for index, token in argTokens do
				if not used[index] then
					table.insert(rest, token.rawText)
				end
			end
			result = string.gsub(result, "%$%*", table.concat(rest, " "))
			used = nil :: any -- everything consumed
		else
			-- Append arguments the expansion didn't reference.
			local extra: { string } = {}
			for index, token in argTokens do
				if not used[index] then
					table.insert(extra, token.rawText)
				end
			end
			if #extra > 0 then
				result = `{result} {table.concat(extra, " ")}`
			end
		end
		return result, true
	end

	local function expandAliases(text: string): (string?, string?)
		local current = text
		for _ = 1, ALIAS_DEPTH_LIMIT do
			local expanded, changed = expandOnce(current)
			if not changed then
				return current, nil
			end
			current = expanded
		end
		return nil, "Alias expansion is too deep (recursive alias?)"
	end

	-- ── Execution ──────────────────────────────────────────────────────
	local base: Dispatcher.EvalBase = {
		realm = "client" :: "client",
		executor = Players.LocalPlayer,
	}

	local function invokeServer(text: string): ExecResponse
		local remote = execRemote
		if remote == nil then
			return { ok = false, message = "The server is not running Kmdr" }
		end
		local okCall, result = pcall(function()
			return remote:InvokeServer(text)
		end)
		if not okCall or type(result) ~= "table" then
			return { ok = false, message = "The server failed to respond" }
		end
		return result :: ExecResponse
	end

	local function runNow(text: string)
		local expanded, expandError = expandAliases(text)
		if expanded == nil then
			emit(expandError :: string, "error")
			return
		end

		local evaluation = Dispatcher.evaluate(registry, expanded, base)
		if evaluation.entry == nil then
			if evaluation.commandError ~= nil then
				emit(evaluation.commandError, "error")
			end
			return
		end
		if evaluation.firstError ~= nil then
			emit(evaluation.firstError, "error")
			return
		end

		local ctx = Dispatcher.makeContext(registry, evaluation, base, emit)

		local verdict = registry.runGuards(ctx)
		if verdict ~= nil then
			emit(verdict, "error")
			registry.fireRan(ctx, verdict)
			return
		end

		local entry = evaluation.entry :: Registry.CommandEntry
		local fn = entry.fn
		if fn ~= nil then
			local okCall, response = pcall(fn, ctx, evaluation.argValues)
			if not okCall then
				warn(`[Kmdr] command '{entry.name}' errored: {response}`)
				emit(`Command '{entry.name}' failed — see the log`, "error")
				registry.fireRan(ctx, nil)
				return
			end
			if response ~= nil then
				emit(response, "success")
				registry.fireRan(ctx, response)
				return
			end
			if not entry.serverHasImpl then
				registry.fireRan(ctx, nil)
				return
			end
		elseif not (entry.serverHasImpl or entry.isRemote) then
			emit(`Command '{entry.name}' has no implementation on this client`, "error")
			return
		end

		local result = invokeServer(expanded)
		if result.message ~= nil then
			emit(result.message, if result.ok then "success" else "error")
		end
		registry.fireRan(ctx, result.message)
	end

	local function run(text: string)
		local trimmed = string.match(text, "^%s*(.-)%s*$") :: string
		if #trimmed == 0 then
			return
		end
		pushHistory(trimmed)
		emit(trimmed, "echo")
		task.spawn(runNow, trimmed)
	end

	local clearSubscribers: { [() -> ()]: boolean } = {}

	local client: KmdrClient
	client = {
		registry = registry,
		register = registry.register,
		registerFolder = registry.registerFolder,
		registerType = registry.registerType,
		registerDefaults = function()
			local builtIns = require(script.Parent.BuiltInCommands) :: any
			registry.register(builtIns.makeClient(client))
		end,
		addGuard = registry.addGuard,
		onRan = registry.onRan,
		getStore = registry.getStore,
		run = run,
		evaluate = function(text: string): Dispatcher.Evaluation
			return Dispatcher.evaluate(registry, text, base)
		end,
		onLine = function(callback: (line: OutputLine) -> ()): () -> ()
			lineSubscribers[callback] = true
			for _, line in table.clone(lineBuffer) do
				task.spawn(callback, line)
			end
			return function()
				lineSubscribers[callback] = nil
			end
		end,
		emit = emit,
		clear = function()
			table.clear(lineBuffer)
			for subscriber in clearSubscribers do
				task.spawn(subscriber)
			end
		end,
		onClear = function(callback: () -> ()): () -> ()
			clearSubscribers[callback] = true
			return function()
				clearSubscribers[callback] = nil
			end
		end,
		getHistory = function(): { string }
			return table.clone(history)
		end,
		addAlias = function(name: string, expansion: string)
			aliases[string.lower(name)] = expansion
		end,
		removeAlias = function(name: string): boolean
			local key = string.lower(name)
			if aliases[key] == nil then
				return false
			end
			aliases[key] = nil
			return true
		end,
		getAliases = function(): { [string]: string }
			return table.clone(aliases)
		end,
		isSynced = function(): boolean
			return synced
		end,
	}
	return client
end

--[=[
	Returns the client singleton, creating it on first call.
]=]
function Client.get(): KmdrClient
	if singleton == nil then
		singleton = create()
	end
	return singleton :: KmdrClient
end

return Client
