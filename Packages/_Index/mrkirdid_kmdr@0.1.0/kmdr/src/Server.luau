--!strict
--[[
	Server.luau — the server singleton: owns the server registry, the two
	remotes, per-player rate limiting, the security default, and the command
	metadata sync that lets clients autocomplete server commands without any
	code replication.

	Remotes live under the Kmdr package module itself (it replicates as part
	of the shared package): Exec (RemoteFunction), Event (RemoteEvent).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BuiltInTypes = require(script.Parent.BuiltInTypes)
local Dispatcher = require(script.Parent.Dispatcher)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Types)

type CommandContext = Types.CommandContext
type ExecResponse = Types.ExecResponse
type Guard = Types.Guard
type RanObserver = Types.RanObserver
type ReplyKind = Types.ReplyKind

local MAX_TEXT_LENGTH = 10_000
local RATE_LIMIT_WINDOW = 10 -- seconds
local RATE_LIMIT_COUNT = 30 -- invocations per window

export type KmdrServer = {
	read registry: Registry.Registry,
	read register: (defOrImpl: any) -> (),
	read registerFolder: (folder: Instance) -> (),
	read registerType: (handle: any) -> (),
	read registerDefaults: () -> (),
	read addGuard: (guard: Guard, priority: number?) -> (),
	read onRan: (observer: RanObserver) -> () -> (),
	read getStore: (name: string) -> { [any]: any },
	--- Programmatic execution (executor nil = server console; replies print).
	read run: (text: string, executor: Player?) -> string?,
	--- Sends a console line to one player (nil = all players).
	read message: (player: Player?, text: string, kind: ReplyKind?) -> (),
}

local Server = {}

local singleton: KmdrServer? = nil
local warnedNoGuards = false

local function create(): KmdrServer
	assert(RunService:IsServer(), "Kmdr.server() may only be called from the server")

	local registry = Registry.new("server")
	for _, handle in BuiltInTypes.all do
		registry.registerType(handle)
	end

	local root = script.Parent

	local execRemote = Instance.new("RemoteFunction")
	execRemote.Name = "Exec"
	execRemote.Parent = root

	local eventRemote = Instance.new("RemoteEvent")
	eventRemote.Name = "Event"
	eventRemote.Parent = root

	-- ── Metadata sync ──────────────────────────────────────────────────
	local syncScheduled = false
	local function scheduleSync()
		if syncScheduled then
			return
		end
		syncScheduled = true
		task.defer(function()
			syncScheduled = false
			eventRemote:FireAllClients("sync", registry.metas())
		end)
	end

	registry.onEntryAdded(scheduleSync)

	eventRemote.OnServerEvent:Connect(function(player: Player, message: unknown)
		if message == "requestSync" then
			eventRemote:FireClient(player, "sync", registry.metas())
		end
	end)

	-- ── Execution ──────────────────────────────────────────────────────
	local function executeFor(executor: Player?, text: string): ExecResponse
		local base: Dispatcher.EvalBase = { realm = "server" :: "server", executor = executor }

		local evaluation = Dispatcher.evaluate(registry, text, base)
		if evaluation.entry == nil then
			return { ok = false, message = evaluation.commandError or "Empty command" }
		end
		if evaluation.firstError ~= nil then
			return { ok = false, message = evaluation.firstError }
		end

		local ctx = Dispatcher.makeContext(registry, evaluation, base, function(message, kind)
			if executor ~= nil then
				eventRemote:FireClient(executor, "reply", { message = message, kind = kind })
			else
				print(`[Kmdr] {message}`)
			end
		end)

		-- Secure by default: no guards means no server execution outside Studio.
		if registry.guardCount() == 0 then
			if RunService:IsStudio() then
				if not warnedNoGuards then
					warnedNoGuards = true
					warn(
						"[Kmdr] No server guards are registered — every command would be blocked in a live game. "
							.. "Add one with server:addGuard(function(ctx) ... end). Allowing in Studio only."
					)
				end
			else
				return { ok = false, message = "Command blocked: this game has not configured Kmdr guards." }
			end
		else
			local verdict = registry.runGuards(ctx)
			if verdict ~= nil then
				registry.fireRan(ctx, verdict)
				return { ok = false, message = verdict }
			end
		end

		local entry = evaluation.entry :: Registry.CommandEntry
		local fn = entry.fn
		if fn == nil then
			return { ok = false, message = `Command '{entry.name}' has no server implementation` }
		end

		local okCall, response = pcall(fn, ctx, evaluation.argValues)
		if not okCall then
			warn(`[Kmdr] command '{entry.name}' errored: {response}`)
			registry.fireRan(ctx, nil)
			return { ok = false, message = `Command '{entry.name}' failed — see the server log` }
		end

		registry.fireRan(ctx, response)
		return { ok = true, message = response }
	end

	-- ── Remote handling: validation + rate limiting ────────────────────
	type RateState = { windowStart: number, count: number }
	local rateStates: { [Player]: RateState } = {}
	Players.PlayerRemoving:Connect(function(player)
		rateStates[player] = nil
	end)

	execRemote.OnServerInvoke = function(player: Player, text: unknown): ExecResponse
		if type(text) ~= "string" or #text == 0 or #text > MAX_TEXT_LENGTH then
			return { ok = false, message = "Invalid command payload" }
		end

		local now = os.clock()
		local state = rateStates[player]
		if state == nil or now - state.windowStart > RATE_LIMIT_WINDOW then
			state = { windowStart = now, count = 0 }
			rateStates[player] = state
		end
		state.count += 1
		if state.count > RATE_LIMIT_COUNT then
			return { ok = false, message = "You are sending commands too quickly" }
		end

		return executeFor(player, text)
	end

	local server: KmdrServer
	server = {
		registry = registry,
		register = registry.register,
		registerFolder = registry.registerFolder,
		registerType = registry.registerType,
		registerDefaults = function()
			local builtIns = require(script.Parent.BuiltInCommands) :: any
			registry.register(builtIns.makeServer(server))
		end,
		addGuard = registry.addGuard,
		onRan = registry.onRan,
		getStore = registry.getStore,
		run = function(text: string, executor: Player?): string?
			local response = executeFor(executor, text)
			return response.message
		end,
		message = function(player: Player?, text: string, kind: ReplyKind?)
			local payload = { message = text, kind = (kind or "info") :: ReplyKind }
			if player ~= nil then
				eventRemote:FireClient(player, "reply", payload)
			else
				eventRemote:FireAllClients("reply", payload)
			end
		end,
	}
	return server
end

--[=[
	Returns the server singleton, creating it on first call.
]=]
function Server.get(): KmdrServer
	if singleton == nil then
		singleton = create()
	end
	return singleton :: KmdrServer
end

return Server
