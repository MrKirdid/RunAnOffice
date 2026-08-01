-- Kore.Mock — Test isolation for services and controllers
-- Allows instantiation without Kore.Start()

local Log = require(script.Parent.Log)
local Signal = require(script.Parent.Signal)
local Types = require(script.Parent.Types)

type ContextType = Types.ContextType
type ServiceDefinition = Types.ServiceDefinition
type ControllerDefinition = Types.ControllerDefinition
type TaggedLogger = Types.TaggedLogger
type Janitor = Types.Janitor

--- Internal mock janitor type for test isolation.
type MockJanitor = {
	Add: <T>(self: MockJanitor, task: T, method: string?) -> T,
	Cleanup: (self: MockJanitor) -> (),
	Destroy: (self: MockJanitor) -> (),
}

--- A mock handle wrapping a service for test isolation.
type ServiceMockHandle = {
	_service: ServiceDefinition,
	_ctx: ContextType,
	Init: (self: ServiceMockHandle) -> (),
	Start: (self: ServiceMockHandle) -> (),
	Inject: (self: ServiceMockHandle, name: string, implementation: any) -> (),
	Get: (self: ServiceMockHandle) -> ServiceDefinition,
	Destroy: (self: ServiceMockHandle) -> (),
}

--- A mock handle wrapping a controller for test isolation.
type ControllerMockHandle = {
	_controller: ControllerDefinition,
	_ctx: ContextType,
	Init: (self: ControllerMockHandle) -> (),
	Start: (self: ControllerMockHandle) -> (),
	Inject: (self: ControllerMockHandle, name: string, implementation: any) -> (),
	Get: (self: ControllerMockHandle) -> ControllerDefinition,
	Destroy: (self: ControllerMockHandle) -> (),
}

--- Internal: task entry for mock janitor.
type MockJanitorEntry = {
	task: any,
	method: string?,
}

local Mock = {}

local function createJanitor(): MockJanitor
	local tasks: { MockJanitorEntry } = {}

	return {
		Add = function<T>(self: MockJanitor, taskObj: T, method: string?): T
			table.insert(tasks, { task = taskObj, method = method })
			return taskObj
		end,

		Cleanup = function(self: MockJanitor): ()
			for i = #tasks, 1, -1 do
				local entry: MockJanitorEntry = tasks[i]
				if type(entry.task) == "function" then
					(entry.task :: () -> ())()
				elseif entry.method and type(entry.task[entry.method]) == "function" then
					entry.task[entry.method](entry.task)
				end
			end
			table.clear(tasks)
		end,

		Destroy = function(self: MockJanitor): ()
			self:Cleanup()
		end,
	}
end

local function createMockContext(name: string, config: { [string]: any }?): ContextType
	return {
		Log = Log.Tagged(name),
		Kore = {
			GetService = function(svcName: string): any
				return {} -- stub
			end,
			GetController = function(ctrlName: string): any
				return {} -- stub
			end,
		} :: any,
		Config = config or {},
	}
end

--- Create a mock wrapper for a service definition.
--- Allows calling Init/Start in isolation and injecting fake dependencies.
function Mock.Service(definition: ServiceDefinition): ServiceMockHandle
	local service: ServiceDefinition = {} :: any

	-- Copy definition
	for k, v in pairs(definition :: any) do
		(service :: any)[k] = v
	end

	service.Janitor = createJanitor() :: any
	service.Log = Log.Tagged(service.Name or "MockService")

	local injected: { [string]: any } = {}
	local ctx: ContextType = createMockContext(service.Name or "MockService", service.Config)

	-- Override Kore.GetService to use injected services
	(ctx.Kore :: any).GetService = function(name: string): any
		if injected[name] then
			return injected[name]
		end
		return {} -- stub
	end

	local mockHandle: ServiceMockHandle = {
		_service = service,
		_ctx = ctx,
	} :: any

	function mockHandle:Init(): ()
		if service.Init then
			service:Init(ctx)
		end
	end

	function mockHandle:Start(): ()
		if service.Start then
			service:Start(ctx)
		end
	end

	function mockHandle:Inject(name: string, implementation: any): ()
		injected[name] = implementation
	end

	function mockHandle:Get(): ServiceDefinition
		return service
	end

	function mockHandle:Destroy(): ()
		if service.Destroy then
			service:Destroy()
		end
		service.Janitor:Cleanup()
	end

	return mockHandle
end

--- Create a mock wrapper for a controller definition.
--- Allows calling Init/Start in isolation and injecting fake dependencies.
function Mock.Controller(definition: ControllerDefinition): ControllerMockHandle
	local controller: ControllerDefinition = {} :: any

	for k, v in pairs(definition :: any) do
		(controller :: any)[k] = v
	end

	controller.Janitor = createJanitor() :: any
	controller.Log = Log.Tagged(controller.Name or "MockController")

	local injected: { [string]: any } = {}
	local ctx: ContextType = createMockContext(controller.Name or "MockController", controller.Config)

	(ctx.Kore :: any).GetController = function(name: string): any
		if injected[name] then
			return injected[name]
		end
		return {}
	end

	local mockHandle: ControllerMockHandle = {
		_controller = controller,
		_ctx = ctx,
	} :: any

	function mockHandle:Init(): ()
		if controller.Init then
			controller:Init(ctx)
		end
	end

	function mockHandle:Start(): ()
		if controller.Start then
			controller:Start(ctx)
		end
	end

	function mockHandle:Inject(name: string, implementation: any): ()
		injected[name] = implementation
	end

	function mockHandle:Get(): ControllerDefinition
		return controller
	end

	function mockHandle:Destroy(): ()
		if controller.Destroy then
			controller:Destroy()
		end
		controller.Janitor:Cleanup()
	end

	return mockHandle
end

return Mock :: Types.MockModule
