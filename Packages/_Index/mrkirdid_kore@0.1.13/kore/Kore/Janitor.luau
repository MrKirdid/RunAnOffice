-- Kore.Janitor — Re-export of howmanysmall/janitor

local resolve = require(script.Parent.PackageResolver)
local Types = require(script.Parent.Types)

type Janitor = Types.Janitor
type JanitorTask = Types.JanitorTask

local ok, Janitor = pcall(function()
	return require(resolve("janitor") or error("not found"))
end)

if ok then
	return Janitor
end

-- Minimal fallback if janitor package is not available
local JanitorFallback = {}
JanitorFallback.__index = JanitorFallback

--- Create a new Janitor for deterministic cleanup.
function JanitorFallback.new(): Types.Janitor
	return setmetatable({
		_tasks = {} :: { [any]: JanitorTask },
	}, JanitorFallback) :: any
end

--- Add a task to be cleaned up. Returns the task for chaining.
function JanitorFallback:Add<T>(taskObj: T, methodName: string?, index: any?): T
	local entry: JanitorTask = { task = taskObj, method = methodName or "Destroy" }
	if index then
		self._tasks[index] = entry
	else
		table.insert(self._tasks, entry)
	end
	return taskObj
end

--- Remove a task by its index key.
function JanitorFallback:Remove(index: any): ()
	self._tasks[index] = nil
end

--- Clean up all tracked tasks in reverse order.
function JanitorFallback:Cleanup(): ()
	for i = #self._tasks, 1, -1 do
		local entry: JanitorTask? = self._tasks[i]
		if entry then
			local taskObj: any = entry.task
			if type(taskObj) == "function" then
				(taskObj :: () -> ())()
			elseif typeof(taskObj) == "RBXScriptConnection" then
				(taskObj :: RBXScriptConnection):Disconnect()
			elseif type(taskObj) == "table" and type(taskObj[entry.method]) == "function" then
				taskObj[entry.method](taskObj)
			elseif typeof(taskObj) == "Instance" then
				(taskObj :: Instance):Destroy()
			end
		end
	end
	table.clear(self._tasks)
end

--- Alias for Cleanup. Destroys the janitor by cleaning all tasks.
function JanitorFallback:Destroy(): ()
	self:Cleanup()
end

return JanitorFallback :: Types.JanitorModule
