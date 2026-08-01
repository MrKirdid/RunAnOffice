-- Kore.Signal — Lightweight signal with optional networking
-- Local by default. Opt-in networked via config table.

local RunService = game:GetService("RunService")

local Log = require(script.Parent.Log)
local Types = require(script.Parent.Types)

type SignalConnection = Types.SignalConnection
type SignalConfig = Types.SignalConfig
type RateLimitConfig = Types.RateLimitConfig

local IS_SERVER: boolean = RunService:IsServer()

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

--- Create a new connection handle.
function Connection.new(signal: any, fn: (...any) -> ()): SignalConnection
	return setmetatable({
		_signal = signal,
		_fn = fn,
		_connected = true,
	}, Connection) :: any
end

--- Disconnect this connection from its signal.
function Connection:Disconnect(): ()
	if not self._connected then
		return
	end
	self._connected = false

	local listeners: { SignalConnection } = self._signal._listeners
	for i, conn in ipairs(listeners) do
		if conn == self then
			table.remove(listeners, i)
			break
		end
	end
end

--- Create a new Signal. Pass a config table to enable networking.
function Signal.new(config: SignalConfig?): Types.Signal<...any>
	local self = setmetatable({
		_listeners = {} :: { SignalConnection },
		_netListeners = {} :: { SignalConnection },
		_networked = false,
		_owner = nil :: ("Server" | "Client" | "Both")?,
		_remote = nil :: RemoteEvent?,
		_rateLimit = nil :: RateLimitConfig?,
	}, Signal)

	if config and config.Network then
		self._networked = true
		self._owner = config.Owner or "Server"
		self._rateLimit = config.RateLimit

		-- Create the backing RemoteEvent
		if IS_SERVER then
			local remote: RemoteEvent = Instance.new("RemoteEvent")
			remote.Name = "KoreSignal_" .. tostring(self) .. "_" .. os.clock()
			remote.Parent = game:GetService("ReplicatedStorage")
			self._remote = remote

			if self._owner == "Client" or self._owner == "Both" then
				remote.OnServerEvent:Connect(function(player: Player, ...: any)
					for _, conn in ipairs(self._netListeners) do
						if conn._connected then
							task.spawn(conn._fn, player, ...)
						end
					end
					-- Also fire local listeners
					for _, conn in ipairs(self._listeners) do
						if conn._connected then
							task.spawn(conn._fn, ...)
						end
					end
				end)
			end
		else
			-- Client: find remote
			task.spawn(function()
				-- Networked signals created server-side need discovery
				-- This is handled via the Net system for Client table signals
			end)
		end
	end

	return self :: any
end

--- Connect a callback to the signal. Returns a connection handle.
function Signal:Connect(fn: (...any) -> ()): SignalConnection
	local conn: SignalConnection = Connection.new(self, fn)
	table.insert(self._listeners, conn)
	return conn
end

--- Connect a callback for networked events. Falls back to local Connect for non-networked signals.
function Signal:ConnectNet(fn: (...any) -> ()): SignalConnection
	if not self._networked then
		Log.Warn("Kore.Signal", "ConnectNet called on a non-networked signal")
		return Signal.Connect(self, fn)
	end

	local conn: SignalConnection = Connection.new(self, fn)
	table.insert(self._netListeners, conn)

	-- If client, connect to remote
	if not IS_SERVER and self._remote then
		local remoteConn: RBXScriptConnection = self._remote.OnClientEvent:Connect(function(...: any)
			if conn._connected then
				fn(...)
			end
		end)
		conn._remoteConnection = remoteConn

		local originalDisconnect = conn.Disconnect
		function conn:Disconnect()
			originalDisconnect(self)
			if self._remoteConnection then
				self._remoteConnection:Disconnect()
			end
		end
	end

	return conn
end

--- Fire the signal locally, and replicate if networked.
function Signal:Fire(...: any): ()
	-- Fire local listeners
	for _, conn in ipairs(self._listeners) do
		if conn._connected then
			task.spawn(conn._fn, ...)
		end
	end

	-- If networked, replicate
	if self._networked and self._remote then
		if IS_SERVER and (self._owner == "Server" or self._owner == "Both") then
			self._remote:FireAllClients(...)
		elseif not IS_SERVER and (self._owner == "Client" or self._owner == "Both") then
			self._remote:FireServer(...)
		end
	end
end

--- Fire to a specific client (server only, networked signals only).
function Signal:FireClient(player: Player, ...: any): ()
	if not IS_SERVER then
		Log.Warn("Kore.Signal", "FireClient can only be called from the server")
		return
	end

	if not self._networked or not self._remote then
		Log.Warn("Kore.Signal", "FireClient called on a non-networked signal")
		return
	end

	self._remote:FireClient(player, ...)
end

--- Fire to all clients (server only, networked signals only).
function Signal:FireAllClients(...: any): ()
	if not IS_SERVER then
		Log.Warn("Kore.Signal", "FireAllClients can only be called from the server")
		return
	end

	if not self._networked or not self._remote then
		Log.Warn("Kore.Signal", "FireAllClients called on a non-networked signal")
		return
	end

	self._remote:FireAllClients(...)
end

--- Connect a callback that auto-disconnects after the first fire.
function Signal:Once(fn: (...any) -> ()): SignalConnection
	local conn: SignalConnection
	conn = self:Connect(function(...: any)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

--- Yield the current thread until the signal fires. Returns the fired arguments.
function Signal:Wait(): ...any
	local thread = coroutine.running()
	local conn: SignalConnection
	conn = self:Connect(function(...: any)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

--- Disconnect all connections (local and networked).
function Signal:DisconnectAll(): ()
	for _, conn in ipairs(self._listeners) do
		conn._connected = false
	end
	table.clear(self._listeners)

	for _, conn in ipairs(self._netListeners) do
		conn._connected = false
		if conn._remoteConnection then
			conn._remoteConnection:Disconnect()
		end
	end
	table.clear(self._netListeners)
end

--- Destroy the signal, disconnecting all listeners and cleaning up the remote.
function Signal:Destroy(): ()
	self:DisconnectAll()
	if self._remote then
		self._remote:Destroy()
		self._remote = nil
	end
end

return Signal :: Types.SignalModule
