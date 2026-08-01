-- Kore.Thread — Weave wrapper for parallel Luau execution
-- Experimental: Weave is currently in beta (0.10.0-beta.1)

local Log = require(script.Parent.Log)
local Types = require(script.Parent.Types)

type ThreadPool = Types.ThreadPool
type ThreadKernel = Types.ThreadKernel

local resolve = require(script.Parent.PackageResolver)
local Promise: any

local Thread = {}

local weave: any
local function getWeave(): any?
	if weave then
		return weave
	end

	local ok, mod = pcall(function()
		local pkg = resolve("weave")
		if pkg then
			return require(pkg)
		end
		error("Weave not found")
	end)

	if ok then
		weave = mod
		return weave
	end

	Log.Warn("Kore.Thread", "Weave not available — Kore.Thread will not function")
	return nil
end

local function getPromise(): any
	if not Promise then
		Promise = require(resolve("promise") or script.Parent.Promise)
	end
	return Promise
end

-- Pool: dispatcher backed by N worker Actors
local Pool = {}
Pool.__index = Pool

--- Create a thread pool with `count` worker Actors using the given script.
function Thread.Pool(count: number, workerScript: ModuleScript): ThreadPool
	local w = getWeave()
	if not w then
		error("[Kore.Thread] Weave is not available", 2)
	end

	local dispatcher = w.dispatcher.new(count, workerScript)

	return setmetatable({
		_dispatcher = dispatcher,
		_count = count,
	}, Pool) :: any
end

--- Dispatch a named task across `count` workers. Returns a Promise resolving with results.
function Pool:Dispatch(taskName: string, count: number): any -- Promise
	local P = getPromise()
	return P.new(function(resolvePromise: (results: any) -> (), reject: (err: any) -> ())
		local ok, results = pcall(function()
			return self._dispatcher:dispatch(taskName, count)
		end)

		if ok then
			resolvePromise(results)
		else
			reject(results)
		end
	end)
end

--- Dispatch a fire-and-forget task.
function Pool:DispatchDetached(taskName: string, count: number): ()
	pcall(function()
		self._dispatcher:dispatchDetached(taskName, count)
	end)
end

--- Destroy the pool and release all worker Actors.
function Pool:Destroy(): ()
	if self._dispatcher and self._dispatcher.destroy then
		self._dispatcher:destroy()
	end
end

-- Kernel: wraps a worker Actor
local Kernel = {}
Kernel.__index = Kernel

--- Create a kernel wrapping a single worker Actor.
function Thread.Kernel(actor: Actor): ThreadKernel
	local w = getWeave()
	if not w then
		error("[Kore.Thread] Weave is not available", 2)
	end

	local kernel = w.kernel.new(actor)

	return setmetatable({
		_kernel = kernel,
	}, Kernel) :: any
end

--- Register a handler for a named task. Chainable.
function Kernel:On(taskName: string, handler: (...any) -> ...any): ThreadKernel
	self._kernel:on(taskName, handler)
	return self :: any
end

--- Register a detached handler for a named task. Chainable.
function Kernel:OnDetached(taskName: string, handler: (...any) -> ...any): ThreadKernel
	self._kernel:onDetached(taskName, handler)
	return self :: any
end

--- Mark this kernel as ready to receive dispatches.
function Kernel:Ready(): ()
	self._kernel:ready()
end

return Thread :: Types.ThreadModule
