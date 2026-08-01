--!strict

local RunService = game:GetService("RunService")

local Manifest = require(script.Manifest)
local Parallel = require(script.Parallel)
local Preloader = require(script.Preloader)
local Signal = require(script.Signal)
local Types = require(script.Types)

type RuntimeKind = Types.RuntimeKind
type LifecycleState = Types.LifecycleState
type FolderOptions = Types.FolderOptions
type InitConfig = Types.InitConfig
type ParallelConfig = Types.ParallelConfig
type ParallelDispatchOptions = Types.ParallelDispatchOptions
type ParallelDispatcher = Types.ParallelDispatcher
type UnitRecordStatus = Types.UnitRecordStatus
type Hub = Types.Hub

type UnitRecord = {
	Name: string,
	Kind: RuntimeKind,
	Module: ModuleScript?,
	Source: Instance?,
	Value: any?,
	Proxy: any,
	State: LifecycleState,
	Error: string?,
	TimedOut: boolean,
	Duration: number?,
	Priority: number,
	Excluded: boolean,
	Advancing: boolean,
	StepId: number,
}

local DEFAULT_TIMEOUT = 10

local SERVER_KIND: RuntimeKind = "Service"
local CLIENT_KIND: RuntimeKind = "Controller"

local Unithub: any = {}
Unithub.__index = Unithub

Unithub.ServiceAdded = Signal.new()
Unithub.ControllerAdded = Signal.new()
Unithub.LifecycleChanged = Signal.new()
Unithub.ServiceFailed = Signal.new()
Unithub.ControllerFailed = Signal.new()
Unithub.PreloadProgress = Signal.new()
Unithub.PreloadFinished = Signal.new()
Unithub.Started = Signal.new()

Unithub.UnitProcedureTimeout = DEFAULT_TIMEOUT
Unithub.Units = {}

Unithub._records = {} :: { UnitRecord }
Unithub._recordsByModule = {} :: { [ModuleScript]: UnitRecord }
Unithub._recordsByKindAndName = {
	Service = {} :: { [string]: UnitRecord },
	Controller = {} :: { [string]: UnitRecord },
}
Unithub._failures = {} :: { UnitRecord }
Unithub._folderConnections = {} :: { RBXScriptConnection }
Unithub._dispatchers = {} :: { [string]: ParallelDispatcher }
Unithub._phase = "Idle"
Unithub._config = nil :: any
Unithub._started = false
Unithub._debug = false

local function currentRuntimeKind(): RuntimeKind
	return if RunService:IsServer() then SERVER_KIND else CLIENT_KIND
end

local function oppositeRuntimeKind(): RuntimeKind
	return if RunService:IsServer() then CLIENT_KIND else SERVER_KIND
end

local function getStateRank(state: string): number
	local ranks = {
		Idle = 0,
		Discovered = 1,
		Required = 2,
		Initialized = 3,
		Started = 4,
	}

	return ranks[state] or 0
end

local function normalizeList(value: any): { any }
	if value == nil then
		return {}
	end

	if typeof(value) == "Instance" then
		return { value }
	end

	local result = {}
	if type(value) == "table" then
		for _, item in pairs(value) do
			table.insert(result, item)
		end
	end

	return result
end

local function normalizeInstanceList(value: any): { Instance }
	local result = {}
	for _, item in ipairs(normalizeList(value)) do
		if typeof(item) == "Instance" then
			table.insert(result, item)
		end
	end

	return result
end

local function normalizeConfig(config: InitConfig?): any
	local normalized: any = {}
	local input: any = config or {}

	normalized.Services = normalizeInstanceList(input.Services or input.services)
	normalized.Controllers = normalizeInstanceList(input.Controllers or input.controllers)
	normalized.Preload = if input.Preload ~= nil then input.Preload else input.preload
	normalized.ExcludedUnits = normalizeList(input.ExcludedUnits or input.excludedUnits)
	normalized.ExcludedServices = normalizeList(input.ExcludedServices or input.excludedServices)
	normalized.ExcludedControllers = normalizeList(input.ExcludedControllers or input.excludedControllers)
	normalized.Timeout = input.Timeout or input.timeout or DEFAULT_TIMEOUT
	normalized.RequireTimeout = input.RequireTimeout or normalized.Timeout
	normalized.LifecycleTimeout = input.LifecycleTimeout or normalized.Timeout
	normalized.Watch = if input.Watch == nil then true else input.Watch
	normalized.Debug = input.Debug == true
	normalized.StrictDuplicates = if input.StrictDuplicates == nil then true else input.StrictDuplicates

	return normalized
end

Unithub._config = normalizeConfig(nil)

local function userProvided(input: any, key: string): boolean
	if key == "Services" then
		return input.Services ~= nil or input.services ~= nil
	elseif key == "Controllers" then
		return input.Controllers ~= nil or input.controllers ~= nil
	elseif key == "Preload" then
		return input.Preload ~= nil or input.preload ~= nil
	elseif key == "Timeout" then
		return input.Timeout ~= nil or input.timeout ~= nil
	end

	return input[key] ~= nil
end

local function waitForGameLoadedOnClient()
	if RunService:IsServer() or game:IsLoaded() then
		return
	end

	game.Loaded:Wait()
end

local function getServerReadyTimeout(config: any): number
	local defaultTimeout = if type(config.Timeout) == "number" then config.Timeout else DEFAULT_TIMEOUT
	local requireTimeout = if type(config.RequireTimeout) == "number" then config.RequireTimeout else defaultTimeout
	local lifecycleTimeout = if type(config.LifecycleTimeout) == "number"
		then config.LifecycleTimeout
		else defaultTimeout

	if requireTimeout <= 0 or lifecycleTimeout <= 0 then
		return 0
	end

	return requireTimeout + lifecycleTimeout * 2 + 1
end

local function isExcluded(moduleScript: ModuleScript, name: string, kind: RuntimeKind, config: any): boolean
	local exclusions = table.clone(config.ExcludedUnits or {})

	if kind == SERVER_KIND then
		for _, item in ipairs(config.ExcludedServices or {}) do
			table.insert(exclusions, item)
		end
	else
		for _, item in ipairs(config.ExcludedControllers or {}) do
			table.insert(exclusions, item)
		end
	end

	for _, exclusion in ipairs(exclusions) do
		if typeof(exclusion) == "Instance" then
			if exclusion == moduleScript or moduleScript:IsDescendantOf(exclusion) then
				return true
			end
		elseif type(exclusion) == "string" then
			if exclusion == name or exclusion == moduleScript.Name or exclusion == moduleScript:GetFullName() then
				return true
			end
		end
	end

	return false
end

local function shouldLoadModule(instance: Instance): boolean
	return instance:IsA("ModuleScript") and instance.Parent ~= nil and instance.Parent:IsA("Folder")
end

local function makeStatus(record: UnitRecord): UnitRecordStatus
	return {
		Name = record.Name,
		Kind = record.Kind,
		State = record.State,
		Module = record.Module,
		Source = record.Source,
		Error = record.Error,
		TimedOut = record.TimedOut,
		Duration = record.Duration,
		Priority = record.Priority,
	}
end

local function createProxy(record: UnitRecord)
	return setmetatable({}, {
		__index = function(_, key)
			if key == "__record" then
				return record
			elseif key == "Name" then
				return record.Name
			elseif key == "State" then
				return record.State
			elseif key == "Module" then
				return record.Module
			elseif key == "Status" then
				return makeStatus(record)
			end

			local value = record.Value
			if value == nil then
				error(
					("[Unithub] %s %s is %s and is not ready yet. Use WaitFor%s if you need to yield."):format(
						record.Kind,
						record.Name,
						record.State,
						record.Kind
					),
					2
				)
			end

			local member = value[key]
			if type(member) == "function" then
				return function(_, ...)
					return member(value, ...)
				end
			end

			if member ~= nil then
				return member
			end

			return nil
		end,

		__newindex = function(_, key, value)
			if record.Value == nil then
				error(
					("[Unithub] Cannot write %s on %s %s before it is required."):format(
						tostring(key),
						record.Kind,
						record.Name
					),
					2
				)
			end

			record.Value[key] = value
		end,

		__tostring = function()
			return ("UnithubProxy(%s:%s:%s)"):format(record.Kind, record.Name, record.State)
		end,
	})
end

function Unithub:_debugPrint(...: any)
	if self._debug then
		print("[Unithub]", ...)
	end
end

function Unithub:_setState(record: UnitRecord, state: LifecycleState, err: string?, timedOut: boolean?)
	record.State = state
	record.Error = err
	record.TimedOut = timedOut == true

	self.LifecycleChanged:Fire(makeStatus(record))

	if state == "Failed" then
		table.insert(self._failures, record)
		local signal = if record.Kind == SERVER_KIND then self.ServiceFailed else self.ControllerFailed
		signal:Fire(makeStatus(record))
		warn(("[Unithub] %s %s failed: %s"):format(record.Kind, record.Name, err or "unknown error"))
	end
end

function Unithub:_registerName(record: UnitRecord, name: string): boolean
	local byName = self._recordsByKindAndName[record.Kind]
	local existing = byName[name]

	if existing and existing ~= record then
		if self._config.StrictDuplicates ~= false then
			self:_setState(
				record,
				"Failed",
				("Duplicate %s name %q from %s"):format(
					record.Kind,
					name,
					record.Module and record.Module:GetFullName() or "unknown"
				),
				false
			)
			return false
		end
	end

	if record.Name ~= name then
		byName[record.Name] = nil
		record.Name = name
	end

	byName[name] = record
	return true
end

local function runWithTimeout(timeoutSeconds: number, callback: () -> any): (boolean, any, boolean, number)
	local startedAt = os.clock()
	local done = false
	local ok = false
	local result: any = nil

	task.spawn(function()
		ok, result = pcall(callback)
		done = true
	end)

	while not done do
		if timeoutSeconds > 0 and os.clock() - startedAt >= timeoutSeconds then
			return false, ("Timed out after %.2f seconds"):format(timeoutSeconds), true, os.clock() - startedAt
		end

		task.wait()
	end

	return ok, result, false, os.clock() - startedAt
end

function Unithub:_requireRecord(record: UnitRecord): boolean
	if record.State ~= "Discovered" then
		return record.State ~= "Failed" and record.State ~= "Skipped"
	end

	if record.Excluded then
		self:_setState(record, "Skipped", nil, false)
		return false
	end

	local moduleScript = record.Module
	if not moduleScript then
		self:_setState(record, "Failed", "Missing ModuleScript", false)
		return false
	end

	local stepId = record.StepId + 1
	record.StepId = stepId

	local ok, value, timedOut, duration = runWithTimeout(self._config.RequireTimeout, function()
		return require(moduleScript)
	end)

	if record.StepId ~= stepId then
		return false
	end

	record.Duration = duration
	if not ok then
		self:_setState(record, "Failed", tostring(value), timedOut)
		return false
	end

	if type(value) ~= "table" then
		self:_setState(record, "Failed", ("Module must return a table, got %s"):format(typeof(value)), false)
		return false
	end

	record.Value = value
	local finalName = if type(value.Name) == "string" and value.Name ~= "" then value.Name else moduleScript.Name
	record.Priority = if type(value.Priority) == "number" then value.Priority else record.Priority
	record.Excluded = record.Excluded
		or value.Enabled == false
		or isExcluded(moduleScript, finalName, record.Kind, self._config)

	if record.Excluded then
		self:_setState(record, "Skipped", nil, false)
		return false
	end

	if not self:_registerName(record, finalName) then
		return false
	end

	self:_setState(record, "Required", nil, false)
	return true
end

function Unithub:_runLifecycle(record: UnitRecord, state: LifecycleState, methodNames: { string }): boolean
	if record.State == "Failed" or record.State == "Skipped" then
		return false
	end

	if state == "Initializing" and record.State ~= "Required" then
		return record.State == "Initialized" or record.State == "Started"
	elseif state == "Starting" and record.State ~= "Initialized" then
		return record.State == "Started"
	end

	local value = record.Value
	if value == nil then
		return false
	end

	local method: ((any, any) -> any)? = nil
	local methodName = ""
	for _, candidate in ipairs(methodNames) do
		local candidateValue = value[candidate]
		if type(candidateValue) == "function" then
			method = candidateValue
			methodName = candidate
			break
		end
	end

	local nextState: LifecycleState = if state == "Initializing" then "Initialized" else "Started"
	if not method then
		self:_setState(record, nextState, nil, false)
		return true
	end

	self:_setState(record, state, nil, false)

	local stepId = record.StepId + 1
	record.StepId = stepId

	local ok, err, timedOut, duration = runWithTimeout(self._config.LifecycleTimeout, function()
		return method(value, self)
	end)

	if record.StepId ~= stepId then
		return false
	end

	record.Duration = duration
	if not ok then
		self:_setState(
			record,
			"Failed",
			("%s failed during %s: %s"):format(record.Name, methodName, tostring(err)),
			timedOut
		)
		return false
	end

	self:_setState(record, nextState, nil, false)
	return true
end

function Unithub:_advanceRecord(record: UnitRecord)
	if record.Advancing then
		return
	end

	record.Advancing = true

	task.spawn(function()
		if getStateRank(self._phase) >= getStateRank("Required") then
			self:_requireRecord(record)
		end

		if getStateRank(self._phase) >= getStateRank("Initialized") then
			self:_runLifecycle(record, "Initializing", { "Init", "Prepare" })
		end

		if getStateRank(self._phase) >= getStateRank("Started") then
			self:_runLifecycle(record, "Starting", { "Start", "Activate" })
		end

		record.Advancing = false
	end)
end

function Unithub:_registerModule(moduleScript: ModuleScript, kind: RuntimeKind, source: Instance?): UnitRecord?
	local existing = self._recordsByModule[moduleScript]
	if existing then
		return existing
	end

	local name = moduleScript.Name
	local existingByName = self._recordsByKindAndName[kind][name]
	local record: UnitRecord = {
		Name = name,
		Kind = kind,
		Module = moduleScript,
		Source = source,
		Value = nil,
		Proxy = nil,
		State = "Discovered",
		Error = nil,
		TimedOut = false,
		Duration = nil,
		Priority = 0,
		Excluded = isExcluded(moduleScript, name, kind, self._config),
		Advancing = false,
		StepId = 0,
	}

	record.Proxy = createProxy(record)

	table.insert(self._records, record)
	self._recordsByModule[moduleScript] = record

	if existingByName and self._config.StrictDuplicates ~= false then
		self:_setState(
			record,
			"Failed",
			("Duplicate %s module name %q from %s"):format(kind, name, moduleScript:GetFullName()),
			false
		)
	else
		self._recordsByKindAndName[kind][name] = record
	end

	if kind == SERVER_KIND then
		table.insert(self.Units, record.Proxy)
		self.ServiceAdded:Fire(makeStatus(record), record.Proxy)
	else
		self.ControllerAdded:Fire(makeStatus(record), record.Proxy)
	end

	self.LifecycleChanged:Fire(makeStatus(record))

	if self._phase ~= "Idle" and self._phase ~= "Discovered" then
		self:_advanceRecord(record)
	end

	return record
end

function Unithub:_scanFolder(folder: Instance, kind: RuntimeKind)
	for _, descendant in ipairs(folder:GetDescendants()) do
		if shouldLoadModule(descendant) then
			self:_registerModule(descendant :: ModuleScript, kind, folder)
		end
	end
end

function Unithub:_watchFolder(folder: Instance, kind: RuntimeKind)
	local connection = folder.DescendantAdded:Connect(function(descendant)
		if shouldLoadModule(descendant) then
			self:_registerModule(descendant :: ModuleScript, kind, folder)
		elseif descendant:IsA("Folder") then
			task.defer(function()
				if descendant.Parent ~= nil then
					self:_scanFolder(descendant, kind)
				end
			end)
		end
	end)

	table.insert(self._folderConnections, connection)
end

function Unithub:AddFolder(folder: Instance, options: FolderOptions?): any
	assert(typeof(folder) == "Instance", "AddFolder expects an Instance")

	local resolvedOptions = options or {}
	local kind = resolvedOptions.Kind or currentRuntimeKind()
	self:_scanFolder(folder, kind)

	if resolvedOptions.Watch ~= false and self._config.Watch ~= false then
		self:_watchFolder(folder, kind)
	end

	return self
end

function Unithub:AddServiceFolder(folder: Instance, options: FolderOptions?): any
	local resolved = table.clone(options or {})
	resolved.Kind = SERVER_KIND
	return self:AddFolder(folder, resolved)
end

function Unithub:AddControllerFolder(folder: Instance, options: FolderOptions?): any
	local resolved = table.clone(options or {})
	resolved.Kind = CLIENT_KIND
	return self:AddFolder(folder, resolved)
end

function Unithub:AddUnit(moduleScript: ModuleScript, kind: RuntimeKind?): any
	assert(typeof(moduleScript) == "Instance" and moduleScript:IsA("ModuleScript"), "AddUnit expects a ModuleScript")
	local record = self:_registerModule(moduleScript, kind or currentRuntimeKind(), moduleScript.Parent)
	if record then
		self:_advanceRecord(record)
		return record.Proxy
	end

	return nil
end

function Unithub:_findRecord(kind: RuntimeKind?, nameOrModule: string | ModuleScript): UnitRecord?
	if typeof(nameOrModule) == "Instance" then
		if nameOrModule:IsA("ModuleScript") then
			return self._recordsByModule[nameOrModule]
		end

		return nil
	end

	if type(nameOrModule) ~= "string" then
		return nil
	end

	if kind then
		return self._recordsByKindAndName[kind][nameOrModule]
	end

	return self._recordsByKindAndName[currentRuntimeKind()][nameOrModule]
		or self._recordsByKindAndName[oppositeRuntimeKind()][nameOrModule]
end

function Unithub:_get(kind: RuntimeKind?, nameOrModule: string | ModuleScript): any
	local record = self:_findRecord(kind, nameOrModule)
	if not record then
		error(("[Unithub] Could not find %s %s"):format(kind or "unit", tostring(nameOrModule)), 2)
	end

	return record.Proxy
end

function Unithub:Get(nameOrModule: string | ModuleScript): any
	return self:_get(nil, nameOrModule)
end

function Unithub:GetService(nameOrModule: string | ModuleScript): any
	return self:_get(SERVER_KIND, nameOrModule)
end

function Unithub:GetController(nameOrModule: string | ModuleScript): any
	return self:_get(CLIENT_KIND, nameOrModule)
end

function Unithub:_waitFor(kind: RuntimeKind, nameOrModule: string | ModuleScript, timeout: number?): any?
	local startedAt = os.clock()
	local limit = timeout or self._config.Timeout or DEFAULT_TIMEOUT

	while true do
		local record = self:_findRecord(kind, nameOrModule)
		if record and (record.State == "Started" or record.State == "Initialized" or record.State == "Required") then
			return record.Proxy
		elseif record and (record.State == "Failed" or record.State == "Skipped") then
			return nil
		end

		if limit > 0 and os.clock() - startedAt >= limit then
			return nil
		end

		task.wait()
	end
end

function Unithub:WaitForService(nameOrModule: string | ModuleScript, timeout: number?): any?
	return self:_waitFor(SERVER_KIND, nameOrModule, timeout)
end

function Unithub:WaitForController(nameOrModule: string | ModuleScript, timeout: number?): any?
	return self:_waitFor(CLIENT_KIND, nameOrModule, timeout)
end

function Unithub:CheckService(nameOrModule: string | ModuleScript): boolean
	local record = self:_findRecord(SERVER_KIND, nameOrModule)
	return record ~= nil and record.State == "Started"
end

function Unithub:CheckController(nameOrModule: string | ModuleScript): boolean
	local record = self:_findRecord(CLIENT_KIND, nameOrModule)
	return record ~= nil and record.State == "Started"
end

function Unithub:GetStatus(nameOrModule: string | ModuleScript): UnitRecordStatus?
	local record = self:_findRecord(nil, nameOrModule)
	if not record then
		return nil
	end

	return makeStatus(record)
end

function Unithub:GetFailures(): { UnitRecordStatus }
	local failures = {}

	for _, record in ipairs(self._failures) do
		table.insert(failures, makeStatus(record))
	end

	return failures
end

function Unithub:CreateDispatcher(config: ParallelConfig?): ParallelDispatcher
	local input = config or {}
	local name = if type(input.Name) == "string" and input.Name ~= "" then input.Name else Parallel.DEFAULT_NAME
	local existing = self._dispatchers[name]
	if existing then
		if not existing:GetStats().Destroyed then
			return existing
		end

		self._dispatchers[name] = nil
	end

	local dispatcher = Parallel.createDispatcher(input, {
		Timeout = self._config.Timeout or DEFAULT_TIMEOUT,
	}) :: ParallelDispatcher

	self._dispatchers[name] = dispatcher
	return dispatcher
end

function Unithub:GetDispatcher(name: string?): ParallelDispatcher
	local dispatcherName = if type(name) == "string" and name ~= "" then name else Parallel.DEFAULT_NAME
	local existing = self._dispatchers[dispatcherName]
	if existing then
		if not existing:GetStats().Destroyed then
			return existing
		end

		self._dispatchers[dispatcherName] = nil
	end

	return self:CreateDispatcher({
		Name = dispatcherName,
	})
end

function Unithub:RunParallel(moduleScript: ModuleScript, payload: any?, options: ParallelDispatchOptions?): any
	return self:GetDispatcher():Run(moduleScript, payload, options)
end

function Unithub:DispatchParallel(
	moduleScript: ModuleScript,
	methodName: string,
	payload: any?,
	options: ParallelDispatchOptions?
): any
	return self:GetDispatcher():Dispatch(moduleScript, methodName, payload, options)
end

function Unithub:MapParallel(
	moduleScript: ModuleScript,
	methodName: string,
	payloads: { any },
	options: ParallelDispatchOptions?
): any
	return self:GetDispatcher():Map(moduleScript, methodName, payloads, options)
end

function Unithub:GetSharedTable(name: string, initial: any?): any
	return Parallel.getSharedTable(name, initial)
end

local function sortRecords(records: { UnitRecord })
	table.sort(records, function(left, right)
		if left.Priority == right.Priority then
			return left.Name < right.Name
		end

		return left.Priority < right.Priority
	end)
end

function Unithub:_runPhase(targetPhase: string, runner: (UnitRecord) -> boolean)
	self._phase = targetPhase

	local records = table.clone(self._records)
	sortRecords(records)

	local completed = 0
	local total = #records

	for _, record in ipairs(records) do
		task.spawn(function()
			runner(record)
			completed += 1
		end)
	end

	while completed < total do
		task.wait()
	end
end

function Unithub:_engageCurrentRuntime()
	self:_runPhase("Required", function(record)
		if record.Kind == currentRuntimeKind() then
			return self:_requireRecord(record)
		end

		return false
	end)

	self:_runPhase("Initialized", function(record)
		if record.Kind == currentRuntimeKind() then
			return self:_runLifecycle(record, "Initializing", { "Init", "Prepare" })
		end

		return false
	end)

	self:_runPhase("Started", function(record)
		if record.Kind == currentRuntimeKind() then
			return self:_runLifecycle(record, "Starting", { "Start", "Activate" })
		end

		return false
	end)
end

function Unithub:_runPreload(preloadConfig: any, controllerRoots: { Instance })
	if RunService:IsServer() or preloadConfig == false or preloadConfig == nil then
		return
	end

	local config = if preloadConfig == true then { Aggressive = true } else table.clone(preloadConfig)
	config.OnProgress = function(info)
		self.PreloadProgress:Fire(info)
		if type(preloadConfig) == "table" and type(preloadConfig.OnProgress) == "function" then
			preloadConfig.OnProgress(info)
		end
	end

	local result = Preloader.run(config, {
		ControllerRoots = controllerRoots,
	})

	self.PreloadFinished:Fire(result)
end

function Unithub:Init(config: InitConfig?): any
	if self._started then
		return self
	end

	waitForGameLoadedOnClient()

	local input: any = config or {}
	local normalized = normalizeConfig(config)
	self._config = normalized
	self._debug = normalized.Debug
	self.UnitProcedureTimeout = normalized.LifecycleTimeout
	self._phase = "Discovered"

	if RunService:IsServer() then
		Manifest.write(normalized)

		for _, folder in ipairs(normalized.Services) do
			self:AddServiceFolder(folder)
		end
	else
		local manifestConfig = Manifest.read(normalized.Timeout)
		if manifestConfig then
			for key, value in pairs(manifestConfig) do
				if not userProvided(input, key) then
					normalized[key] = value
				end
			end

			self._config = normalized
		end

		local serverServicesReady, readinessError =
			Manifest.waitForServerServicesReady(getServerReadyTimeout(normalized))
		if not serverServicesReady then
			error(
				("[Unithub] %s before starting controllers."):format(readinessError or "Server services were not ready"),
				2
			)
		end

		for _, folder in ipairs(normalized.Controllers) do
			self:AddControllerFolder(folder)
		end

		self:_runPreload(normalized.Preload, normalized.Controllers)
	end

	self:_engageCurrentRuntime()

	if RunService:IsServer() then
		Manifest.markServerServicesReady(#self:GetFailures())
	end

	self._started = true
	self.Started:Fire({
		Kind = currentRuntimeKind(),
		Failures = self:GetFailures(),
	})

	return self
end

function Unithub:Start(): any
	self:_engageCurrentRuntime()
	return self
end

function Unithub:Destroy()
	for _, dispatcher in pairs(self._dispatchers) do
		dispatcher:Destroy()
	end
	table.clear(self._dispatchers)

	for _, connection in ipairs(self._folderConnections) do
		connection:Disconnect()
	end
	table.clear(self._folderConnections)

	for _, record in ipairs(self._records) do
		if record.Value and type(record.Value.Destroy) == "function" then
			local ok, err = pcall(record.Value.Destroy, record.Value)
			if not ok then
				warn(("[Unithub] %s %s failed during Destroy: %s"):format(record.Kind, record.Name, tostring(err)))
			end
		end

		self:_setState(record, "Destroyed", nil, false)
	end

	self._started = false
	self._phase = "Idle"
end

Unithub.init = Unithub.Init
Unithub.start = Unithub.Start
Unithub.destroy = Unithub.Destroy
Unithub.addFolder = Unithub.AddFolder
Unithub.addServiceFolder = Unithub.AddServiceFolder
Unithub.addControllerFolder = Unithub.AddControllerFolder
Unithub.addUnit = Unithub.AddUnit
Unithub.get = Unithub.Get
Unithub.getService = Unithub.GetService
Unithub.getController = Unithub.GetController
Unithub.waitForService = Unithub.WaitForService
Unithub.waitForController = Unithub.WaitForController
Unithub.checkService = Unithub.CheckService
Unithub.checkController = Unithub.CheckController
Unithub.getStatus = Unithub.GetStatus
Unithub.getFailures = Unithub.GetFailures
Unithub.createDispatcher = Unithub.CreateDispatcher
Unithub.getDispatcher = Unithub.GetDispatcher
Unithub.runParallel = Unithub.RunParallel
Unithub.dispatchParallel = Unithub.DispatchParallel
Unithub.mapParallel = Unithub.MapParallel
Unithub.getSharedTable = Unithub.GetSharedTable
Unithub.GetUnit = Unithub.Get
Unithub.getUnit = Unithub.Get
Unithub.Add = Unithub.AddUnit
Unithub.add = Unithub.AddUnit
Unithub.CheckService = Unithub.CheckService
Unithub.CheckController = Unithub.CheckController
Unithub.EngageUnits = Unithub.Start
Unithub.Activate = Unithub.Start
Unithub.Prepare = Unithub.Init

setmetatable(Unithub, {
	__call = function(self, config: InitConfig?)
		return self:Init(config)
	end,
})

return Unithub :: Hub
