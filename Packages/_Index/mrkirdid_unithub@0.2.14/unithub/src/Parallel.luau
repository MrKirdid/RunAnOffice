--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SharedTableRegistry = game:GetService("SharedTableRegistry")

local Dependencies = require(script.Parent.Dependencies)
local Types = require(script.Parent.Types)

type ParallelConfig = Types.ParallelConfig
type ParallelDispatchOptions = Types.ParallelDispatchOptions
type ParallelStats = Types.ParallelStats

type WorkerRecord = {
	Id: number,
	Actor: Actor,
	Ready: boolean,
	InFlight: number,
}

type TaskRecord = {
	Id: number,
	Module: ModuleScript,
	Method: string,
	Payload: any,
	Resolve: (any) -> (),
	Reject: (any) -> (),
	Worker: WorkerRecord?,
	Done: boolean,
	Released: boolean,
	TimeoutThread: thread?,
}

local PromiseDependency = Dependencies.require("Promise")
assert(
	PromiseDependency and type(PromiseDependency.new) == "function",
	"[Unithub] Parallel dispatcher requires Promise."
)
local Promise = PromiseDependency :: any

local DEFAULT_NAME = "__UnithubParallel"
local DEFAULT_WORKER_COUNT = 4
local DEFAULT_TIMEOUT = 10
local DEFAULT_MAX_IN_FLIGHT = 1

local DISPATCH_TOPIC = "__UnithubDispatch"
local READY_EVENT_NAME = "__Ready"
local RESULT_EVENT_NAME = "__Result"

local Parallel = {
	DEFAULT_NAME = DEFAULT_NAME,
}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

local function getDefaultParent(): Instance
	if RunService:IsServer() then
		return game:GetService("ServerScriptService")
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		error("[Unithub] Client parallel dispatch requires Players.LocalPlayer.", 3)
	end

	local playerScripts = localPlayer:FindFirstChildOfClass("PlayerScripts")
	if not playerScripts then
		playerScripts = localPlayer:WaitForChild("PlayerScripts", 10)
	end

	if not playerScripts then
		error("[Unithub] Client parallel dispatch could not find PlayerScripts.", 3)
	end

	return playerScripts
end

local function getWorkerTemplate(): LuaSourceContainer
	local templateName = if RunService:IsServer() then "ParallelServerWorker" else "ParallelClientWorker"
	local template = script.Parent:FindFirstChild(templateName)

	if not template or not template:IsA("LuaSourceContainer") then
		error(("[Unithub] Missing parallel worker template %s."):format(templateName), 3)
	end

	return template :: LuaSourceContainer
end

local function normalizePositiveInteger(value: any, fallback: number): number
	if type(value) ~= "number" then
		return fallback
	end

	return math.max(1, math.floor(value))
end

local function normalizeTimeout(value: any, fallback: number): number
	if type(value) ~= "number" then
		return fallback
	end

	return math.max(0, value)
end

local function createRuntimeFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function createBindable(parent: Instance, name: string): BindableEvent
	local bindable = Instance.new("BindableEvent")
	bindable.Name = name
	bindable.Parent = parent
	return bindable
end

local function promiseAll(promises: { any }): any
	if type(Promise.all) == "function" then
		return Promise.all(promises)
	end

	return Promise.new(function(resolve, reject)
		local remaining = #promises
		local results = table.create(remaining)

		if remaining == 0 then
			resolve(results)
			return
		end

		for index, promise in ipairs(promises) do
			promise
				:andThen(function(value)
					results[index] = value
					remaining -= 1

					if remaining == 0 then
						resolve(results)
					end
				end)
				:catch(reject)
		end
	end)
end

function Parallel.getSharedTable(name: string, initial: any?): any
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

function Dispatcher.new(config: ParallelConfig?, defaults: any?): any
	local input = config or {}
	local name = if type(input.Name) == "string" and input.Name ~= "" then input.Name else DEFAULT_NAME
	local parent = if typeof(input.Parent) == "Instance" then input.Parent else getDefaultParent()
	local timeout = normalizeTimeout(input.Timeout, defaults and defaults.Timeout or DEFAULT_TIMEOUT)
	local workerCount = normalizePositiveInteger(input.WorkerCount, DEFAULT_WORKER_COUNT)
	local maxInFlight = normalizePositiveInteger(input.MaxInFlightPerWorker, DEFAULT_MAX_IN_FLIGHT)
	local folder = createRuntimeFolder(parent, name)
	local readyEvent = createBindable(folder, READY_EVENT_NAME)
	local resultEvent = createBindable(folder, RESULT_EVENT_NAME)
	local workerTemplate = getWorkerTemplate()

	local self = setmetatable({
		_name = name,
		_folder = folder,
		_readyEvent = readyEvent,
		_resultEvent = resultEvent,
		_workerTemplate = workerTemplate,
		_timeout = timeout,
		_maxInFlightPerWorker = maxInFlight,
		_workers = {} :: { WorkerRecord },
		_workersById = {} :: { [number]: WorkerRecord },
		_queue = {} :: { TaskRecord },
		_pending = {} :: { [number]: TaskRecord },
		_running = {} :: { [number]: TaskRecord },
		_nextTaskId = 0,
		_inFlight = 0,
		_completed = 0,
		_failed = 0,
		_timedOut = 0,
		_destroyed = false,
		_readyConnection = nil :: RBXScriptConnection?,
		_resultConnection = nil :: RBXScriptConnection?,
	}, Dispatcher)

	self._readyConnection = readyEvent.Event:Connect(function(workerId: number)
		local worker = self._workersById[workerId]
		if not worker then
			return
		end

		worker.Ready = true
		self:_pump()
	end)

	self._resultConnection = resultEvent.Event:Connect(function(taskId: number, ok: boolean, value: any)
		local record = self._pending[taskId]
		if record then
			self:_finishTask(record, ok == true, value, false, true)
			return
		end

		local runningRecord = self._running[taskId]
		if runningRecord then
			self:_releaseTask(runningRecord)
			self:_pump()
		end
	end)

	for workerId = 1, workerCount do
		self:_createWorker(workerId)
	end

	return self
end

function Dispatcher:_createWorker(workerId: number)
	local actor = Instance.new("Actor")
	actor.Name = ("Worker_%02d"):format(workerId)
	actor.Parent = self._folder

	local workerScript = self._workerTemplate:Clone()
	workerScript.Name = "Worker"
	workerScript:SetAttribute("WorkerId", workerId)
	local baseScript = workerScript :: any
	baseScript.Enabled = true
	workerScript.Parent = actor

	local worker: WorkerRecord = {
		Id = workerId,
		Actor = actor,
		Ready = false,
		InFlight = 0,
	}

	table.insert(self._workers, worker)
	self._workersById[workerId] = worker
end

function Dispatcher:_pickWorker(): WorkerRecord?
	local bestWorker: WorkerRecord? = nil

	for _, worker in ipairs(self._workers) do
		if worker.Ready and worker.InFlight < self._maxInFlightPerWorker then
			if not bestWorker or worker.InFlight < bestWorker.InFlight then
				bestWorker = worker
			end
		end
	end

	return bestWorker
end

function Dispatcher:_sendTask(worker: WorkerRecord, record: TaskRecord)
	record.Worker = worker
	worker.InFlight += 1
	self._inFlight += 1
	self._running[record.Id] = record

	local sent, err = pcall(function()
		worker.Actor:SendMessage(DISPATCH_TOPIC, record.Id, record.Module, record.Method, record.Payload)
	end)

	if not sent then
		self:_finishTask(record, false, ("Failed to send task to worker: %s"):format(tostring(err)), false, true)
		return
	end
end

function Dispatcher:_pump()
	if self._destroyed then
		return
	end

	while #self._queue > 0 do
		local worker = self:_pickWorker()
		if not worker then
			return
		end

		local record = table.remove(self._queue, 1)
		if not record.Done then
			self:_sendTask(worker, record)
		end
	end
end

function Dispatcher:_releaseTask(record: TaskRecord)
	if record.Released then
		return
	end

	record.Released = true
	self._running[record.Id] = nil

	if record.Worker then
		record.Worker.InFlight = math.max(0, record.Worker.InFlight - 1)
		self._inFlight = math.max(0, self._inFlight - 1)
	end
end

function Dispatcher:_finishTask(record: TaskRecord, ok: boolean, value: any, timedOut: boolean, releaseWorker: boolean?)
	if record.Done then
		return
	end

	record.Done = true
	self._pending[record.Id] = nil

	if record.TimeoutThread then
		pcall(task.cancel, record.TimeoutThread)
		record.TimeoutThread = nil
	end

	if releaseWorker ~= false then
		self:_releaseTask(record)
	end

	if ok then
		self._completed += 1
		record.Resolve(value)
	else
		self._failed += 1
		if timedOut then
			self._timedOut += 1
		end

		record.Reject(value)
	end

	self:_pump()
end

function Dispatcher:_scheduleTimeout(record: TaskRecord, timeoutSeconds: number)
	if timeoutSeconds <= 0 then
		return
	end

	record.TimeoutThread = task.delay(timeoutSeconds, function()
		if self._pending[record.Id] ~= record then
			return
		end

		self:_finishTask(
			record,
			false,
			("Timed out after %.2f seconds"):format(timeoutSeconds),
			true,
			record.Worker == nil
		)
	end)
end

function Dispatcher:Dispatch(
	moduleScript: ModuleScript,
	methodName: string,
	payload: any?,
	options: ParallelDispatchOptions?
): any
	assert(not self._destroyed, "[Unithub] Parallel dispatcher is destroyed")
	assert(typeof(moduleScript) == "Instance" and moduleScript:IsA("ModuleScript"), "Dispatch expects a ModuleScript")
	assert(type(methodName) == "string" and methodName ~= "", "Dispatch expects a non-empty method name")

	local dispatchOptions = options or {}
	local timeoutSeconds = normalizeTimeout(dispatchOptions.Timeout, self._timeout)

	self._nextTaskId += 1
	local taskId = self._nextTaskId

	return Promise.new(function(resolve, reject, onCancel)
		local record: TaskRecord = {
			Id = taskId,
			Module = moduleScript,
			Method = methodName,
			Payload = payload,
			Resolve = resolve,
			Reject = reject,
			Worker = nil,
			Done = false,
			Released = false,
			TimeoutThread = nil,
		}

		self._pending[taskId] = record
		table.insert(self._queue, record)
		self:_scheduleTimeout(record, timeoutSeconds)

		if type(onCancel) == "function" then
			onCancel(function()
				self:_finishTask(record, false, "Cancelled", false, record.Worker == nil)
			end)
		end

		self:_pump()
	end)
end

function Dispatcher:Run(moduleScript: ModuleScript, payload: any?, options: ParallelDispatchOptions?): any
	return self:Dispatch(moduleScript, "Run", payload, options)
end

function Dispatcher:Map(
	moduleScript: ModuleScript,
	methodName: string,
	payloads: { any },
	options: ParallelDispatchOptions?
): any
	assert(type(payloads) == "table", "Map expects an array of payloads")

	local promises = table.create(#payloads)
	for index, payload in ipairs(payloads) do
		promises[index] = self:Dispatch(moduleScript, methodName, payload, options)
	end

	return promiseAll(promises)
end

function Dispatcher:GetStats(): ParallelStats
	local readyWorkers = 0
	for _, worker in ipairs(self._workers) do
		if worker.Ready then
			readyWorkers += 1
		end
	end

	return {
		Name = self._name,
		WorkerCount = #self._workers,
		ReadyWorkers = readyWorkers,
		Queued = #self._queue,
		InFlight = self._inFlight,
		Completed = self._completed,
		Failed = self._failed,
		TimedOut = self._timedOut,
		Destroyed = self._destroyed,
	}
end

function Dispatcher:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true

	local pending = {}
	for _, record in pairs(self._pending) do
		table.insert(pending, record)
	end

	for _, record in ipairs(pending) do
		self:_finishTask(record, false, "Dispatcher destroyed", false, true)
	end

	if self._readyConnection then
		self._readyConnection:Disconnect()
		self._readyConnection = nil
	end

	if self._resultConnection then
		self._resultConnection:Disconnect()
		self._resultConnection = nil
	end

	self._folder:Destroy()
	table.clear(self._queue)
	table.clear(self._pending)
	table.clear(self._running)
	table.clear(self._workers)
	table.clear(self._workersById)
	self._inFlight = 0
end

function Parallel.createDispatcher(config: ParallelConfig?, defaults: any?): any
	return Dispatcher.new(config, defaults)
end

return Parallel
