--!strict

local SharedTableRegistry = game:GetService("SharedTableRegistry")

local DISPATCH_TOPIC = "__UnithubDispatch"
local READY_EVENT_NAME = "__Ready"
local RESULT_EVENT_NAME = "__Result"

local actor = script:GetActor()
if not actor then
	warn("[Unithub] Parallel server worker must be parented under an Actor.")
	return
end

local workerIdAttribute = script:GetAttribute("WorkerId")
local workerId = if type(workerIdAttribute) == "number" then workerIdAttribute else 0
local moduleCache: { [ModuleScript]: any } = {}

local function findBindable(name: string): BindableEvent?
	local parent = actor.Parent
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	if child and child:IsA("BindableEvent") then
		return child
	end

	return nil
end

local resultEvent = findBindable(RESULT_EVENT_NAME)
local readyEvent = findBindable(READY_EVENT_NAME)

if not resultEvent or not readyEvent then
	warn("[Unithub] Parallel server worker is missing dispatcher bindables.")
	return
end

local function safeSynchronize()
	pcall(task.synchronize)
end

local function getSharedTable(name: string, initial: any?): any
	assert(type(name) == "string" and name ~= "", "GetSharedTable expects a non-empty name")

	local sharedTable = SharedTableRegistry:GetSharedTable(name)
	if initial ~= nil and SharedTable.size(sharedTable) == 0 then
		local ok, seeded = pcall(function()
			return SharedTable.new(initial)
		end)

		if not ok then
			error(("[Unithub] Could not seed SharedTable %q: %s"):format(name, tostring(seeded)), 2)
		end

		SharedTableRegistry:SetSharedTable(name, seeded)
		sharedTable = seeded
	end

	return sharedTable
end

local function requireJob(moduleScript: ModuleScript): any
	local cached = moduleCache[moduleScript]
	if cached ~= nil then
		return cached
	end

	safeSynchronize()
	local value = require(moduleScript)
	task.desynchronize()

	moduleCache[moduleScript] = value
	return value
end

local function fireResult(taskId: number, ok: boolean, value: any)
	safeSynchronize()

	local fired, err = pcall(function()
		(resultEvent :: BindableEvent):Fire(taskId, ok, value)
	end)

	if not fired then
		pcall(function()
			(resultEvent :: BindableEvent):Fire(
				taskId,
				false,
				("Failed to return parallel result: %s"):format(tostring(err))
			)
		end)
	end
end

actor:BindToMessageParallel(
	DISPATCH_TOPIC,
	function(taskId: number, moduleScript: ModuleScript, methodName: string, payload: any)
		local ok, result = pcall(function()
			if typeof(moduleScript) ~= "Instance" or not moduleScript:IsA("ModuleScript") then
				error("Parallel task module must be a ModuleScript", 2)
			end

			local job = requireJob(moduleScript)
			local method: any = nil

			if type(job) == "function" and methodName == "Run" then
				method = job
			elseif type(job) == "table" then
				method = job[methodName]
			end

			if type(method) ~= "function" then
				error(("Parallel task method %q is missing"):format(methodName), 2)
			end

			return method(payload, {
				TaskId = taskId,
				WorkerId = workerId,
				Actor = actor,
				Synchronize = task.synchronize,
				Desynchronize = task.desynchronize,
				GetSharedTable = getSharedTable,
			})
		end)

		fireResult(taskId, ok, if ok then result else tostring(result))
	end
)

readyEvent:Fire(workerId)
