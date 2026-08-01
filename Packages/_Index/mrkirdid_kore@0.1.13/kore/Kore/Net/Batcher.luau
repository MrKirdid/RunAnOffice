-- Kore.Net.Batcher — Frame-based remote call batching

local RunService = game:GetService("RunService")
local Log = require(script.Parent.Parent.Log)
local Types = require(script.Parent.Parent.Types)

local Batcher = {}
Batcher.__index = Batcher

--- Create a new Batcher that flushes queued calls each Heartbeat frame.
--- @param sendCallback — called with the full batch array on flush.
function Batcher.new(sendCallback: (batch: { Types.BatchEntry }) -> ()): Types.Batcher
	local self = setmetatable({
		_queue = {} :: { Types.BatchEntry },
		_sendCallback = sendCallback,
		_connection = nil :: RBXScriptConnection?,
		_active = false,
	}, Batcher)
	return self :: any
end

--- Queue a remote call to be sent in the next Heartbeat batch.
function Batcher.Queue(self: Types.Batcher, remoteName: string, ...: any): ()
	if not self._active then
		self._active = true
		self._connection = RunService.Heartbeat:Once(function()
			self:_flush()
		end) :: any
	end

	table.insert(self._queue, {
		name = remoteName,
		args = table.pack(...),
	})
end

function Batcher._flush(self: Types.Batcher): ()
	local batch: { Types.BatchEntry } = self._queue
	self._queue = {}
	self._active = false
	self._connection = nil

	if #batch > 0 then
		Log.Debug("Kore.Net", "Flushing batch of %d calls", #batch)
		self._sendCallback(batch)
	end
end

--- Destroy the batcher, disconnecting any pending Heartbeat flush.
function Batcher.Destroy(self: Types.Batcher): ()
	if self._connection then
		(self._connection :: RBXScriptConnection):Disconnect()
		self._connection = nil
	end
	table.clear(self._queue)
	self._active = false
end

return Batcher
