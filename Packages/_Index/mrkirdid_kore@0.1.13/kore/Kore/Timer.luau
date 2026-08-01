-- Kore.Timer — Debounce, Throttle, Delay, Every, and scheduler wrappers

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

type CancelFn = Types.CancelFn

local Timer = {}

--- Returns a debounced version of `fn` that waits `t` seconds after the last call.
function Timer.Debounce(fn: (...any) -> (), t: number): (...any) -> ()
	local scheduled: thread? = nil
	return function(...: any)
		if scheduled then
			task.cancel(scheduled)
		end
		local args = table.pack(...)
		scheduled = task.delay(t, function()
			scheduled = nil
			fn(table.unpack(args, 1, args.n))
		end)
	end
end

--- Returns a throttled version of `fn` that fires at most once per `t` seconds.
function Timer.Throttle(fn: (...any) -> (), t: number): (...any) -> ()
	local lastCall: number = 0
	return function(...: any)
		local now: number = os.clock()
		if now - lastCall >= t then
			lastCall = now
			fn(...)
		end
	end
end

--- Call `fn` after `t` seconds. Returns a cancel function.
function Timer.Delay(t: number, fn: () -> ()): CancelFn
	local cancelled: boolean = false
	task.delay(t, function()
		if not cancelled then
			fn()
		end
	end)
	return function()
		cancelled = true
	end
end

--- Call `fn` every `t` seconds. Returns a cancel function.
function Timer.Every(t: number, fn: () -> ()): CancelFn
	local running: boolean = true
	task.spawn(function()
		while running do
			fn()
			task.wait(t)
		end
	end)
	return function()
		running = false
	end
end

--- Connect to `RunService.Heartbeat`.
function Timer.Heartbeat(fn: (deltaTime: number) -> ()): RBXScriptConnection
	return RunService.Heartbeat:Connect(fn)
end

--- Connect to `RunService.Stepped`.
function Timer.Stepped(fn: (time: number, deltaTime: number) -> ()): RBXScriptConnection
	return RunService.Stepped:Connect(fn)
end

--- Connect to `RunService.RenderStepped` (client only). Returns nil on server.
function Timer.RenderStepped(fn: (deltaTime: number) -> ()): RBXScriptConnection?
	if not RunService:IsClient() then
		warn("[Kore.Timer] RenderStepped is only available on the client")
		return nil
	end
	return RunService.RenderStepped:Connect(fn)
end

return Timer :: Types.TimerModule
