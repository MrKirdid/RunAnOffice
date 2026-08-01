-- Kore.Proxy — Transparent proxy with queued method calls
-- Used during Init() phase for services not yet initialized.

local Log = require(script.Parent.Log)
local Types = require(script.Parent.Types)

type ProxyResolveFn = Types.ProxyResolveFn

--- Internal queue entry for a deferred method call.
type QueueEntry = {
	method: string,
	args: { [number]: any, n: number },
}

local Proxy = {}

local QUEUE_WARN_THRESHOLD: number = 100

--- Create a named proxy that queues method calls until resolved.
--- Returns the proxy table and a resolve function.
function Proxy.create(name: string): (any, ProxyResolveFn)
	local queue: { QueueEntry } = {}
	local resolved: boolean = false
	local realTarget: any = nil

	local proxy = setmetatable({}, {
		__index = function(_: any, key: string): ((...any) -> ...any)?
			if resolved then
				return realTarget[key]
			end

			-- Return a function that queues the call
			return function(_: any, ...: any)
				if resolved then
					return realTarget[key](realTarget, ...)
				end

				local args = table.pack(...)
				table.insert(queue, { method = key, args = args })

				if #queue > QUEUE_WARN_THRESHOLD then
					Log.Warn("Kore", "Proxy queue for '%s' exceeds %d entries", name, QUEUE_WARN_THRESHOLD)
				end
			end
		end,

		__tostring = function(): string
			return "KoreProxy<" .. name .. ">"
		end,
	})

	local function resolve(target: any): ()
		if resolved then
			return
		end
		resolved = true
		realTarget = target

		-- Flush queued calls
		if #queue > 0 then
			Log.Debug("Kore", "Flushing %d queued calls for '%s'", #queue, name)
		end

		for _, entry in ipairs(queue) do
			local method = target[entry.method]
			if method then
				method(target, table.unpack(entry.args, 1, entry.args.n))
			else
				Log.Warn("Kore", "Proxy flush: method '%s' not found on '%s'", entry.method, name)
			end
		end

		table.clear(queue)
	end

	return proxy, resolve
end

return Proxy :: Types.ProxyModule
