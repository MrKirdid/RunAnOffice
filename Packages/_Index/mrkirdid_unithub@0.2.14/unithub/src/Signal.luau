--!strict

local Dependencies = require(script.Parent.Dependencies)

type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

local FastSignal = Dependencies.require("Signal")

if FastSignal and type(FastSignal.new) == "function" then
	return FastSignal
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_connections = {},
		_destroyed = false,
	}, Signal)
end

function Signal:Connect(callback: (...any) -> ()): Connection
	assert(type(callback) == "function", "Signal callback must be a function")

	local connection = {
		Connected = true,
	}

	connection.Disconnect = function(selfConnection)
		selfConnection.Connected = false
	end

	table.insert(self._connections, {
		callback = callback,
		connection = connection,
	})

	return connection
end

function Signal:Once(callback: (...any) -> ()): Connection
	local connection: Connection?
	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
			connection = nil
		end

		callback(...)
	end)

	return connection :: Connection
end

function Signal:Fire(...: any)
	if self._destroyed then
		return
	end

	for _, node in ipairs(table.clone(self._connections)) do
		if node.connection.Connected then
			task.spawn(node.callback, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	local connection: Connection?

	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
		end

		task.spawn(thread, ...)
	end)

	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, node in ipairs(self._connections) do
		node.connection:Disconnect()
	end

	table.clear(self._connections)
end

function Signal:Destroy()
	if self._destroyed then
		return
	end

	self:DisconnectAll()
	self._destroyed = true
end

return Signal
