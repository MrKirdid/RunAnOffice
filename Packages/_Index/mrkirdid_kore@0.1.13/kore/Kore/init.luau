-- Kore — Professional Roblox Luau game framework
-- Version 0.1.0

local RunService = game:GetService("RunService")

local IS_SERVER: boolean = RunService:IsServer()

local Types = require(script.Types)
local Symbol = require(script.Symbol)
local Log = require(script.Log) :: Types.LogModule
local Proxy = require(script.Proxy) :: Types.ProxyModule
local Loader = require(script.Loader) :: Types.LoaderModule
local Net = require(script.Net) :: Types.NetModule
local Signal = require(script.Signal) :: Types.SignalModule
local Timer = require(script.Timer) :: Types.TimerModule
local Tween = require(script.Tween) :: Types.TweenModule
local Curve = require(script.Curve) :: Types.CurveModule
local Data = require(script.Data) :: Types.DataModule
local Thread = require(script.Thread) :: Types.ThreadModule
local Mock = require(script.Mock) :: Types.MockModule
local Janitor = require(script.Janitor) :: Types.JanitorModule
local Util = require(script.Util) :: Types.UtilModule

local resolve = require(script.PackageResolver)
local Promise = require(resolve("promise") or script.Promise)

-- ──────────────────────────────────────────────────────────────────────
-- State
-- ──────────────────────────────────────────────────────────────────────

type ProxyEntry = {
	proxy: any,
	resolve: Types.ProxyResolveFn,
}

local services: { [string]: Types.ServiceDefinition } = {} -- [name] = service instance
local controllers: { [string]: Types.ControllerDefinition } = {} -- [name] = controller instance
local proxies: { [string]: ProxyEntry } = {} -- [name] = { proxy, resolve }
local clientProxies: { [string]: { [string]: any } } = {} -- [name] = client proxy (client-side)

local started: boolean = false
local configured: boolean = false

local config: Types.KoreConfig & { Log: Types.KoreLogConfig } = {
	Debug = false,
	Destroy = "shutdown",
	Log = {
		DiscordWebhook = nil,
	},
}

-- ──────────────────────────────────────────────────────────────────────
-- Kore API
-- ──────────────────────────────────────────────────────────────────────

local Kore = {}

-- Sentinel value for server-to-client event remotes
Kore.NetEvent = Symbol("NetEvent")

-- Re-exports
Kore.Promise = Promise
Kore.Signal = Signal
Kore.Log = Log
Kore.Timer = Timer
Kore.Symbol = Symbol
Kore.Tween = Tween
Kore.Curve = Curve
Kore.Data = Data
Kore.Thread = Thread
Kore.Mock = Mock
Kore.Janitor = Janitor
Kore.Util = Util
Kore.Net = Net
Kore.Types = require(script.Types)

-- Optional re-exports (may not be available)
pcall(function()
	Kore.Fusion = require(script.Fusion)
end)

-- ──────────────────────────────────────────────────────────────────────
-- Configuration
-- ──────────────────────────────────────────────────────────────────────

--- Configure the Kore framework. Must be called before `Start()`.
function Kore.Configure(userConfig: Types.KoreConfig): ()
	if started then
		error("[Kore] Configure() must be called before Start()", 2)
	end

	if userConfig.Debug ~= nil then
		config.Debug = userConfig.Debug
		if config.Debug then
			Log.EnableDebug()
		end
	end

	if userConfig.Destroy ~= nil then
		config.Destroy = userConfig.Destroy
	end

	if userConfig.Log then
		if userConfig.Log.DiscordWebhook then
			config.Log.DiscordWebhook = userConfig.Log.DiscordWebhook
			Log.Debug("Kore", "Discord webhook configured (not yet implemented)")
		end
	end

	configured = true
end

-- ──────────────────────────────────────────────────────────────────────
-- Registration
-- ──────────────────────────────────────────────────────────────────────

local function createJanitor(): Types.Janitor
	return Janitor.new()
end

local function setupServiceInstance(svc: Types.ServiceDefinition): ()
	svc.Janitor = svc.Janitor or createJanitor()
	svc.Log = Log.Tagged(svc.Name)
end

--- Register a service (server only). The service table must have a `Name` field.
function Kore.AddService(serviceTable: Types.ServiceDefinition): ()
	if not IS_SERVER then
		error("[Kore] AddService() can only be called on the server", 2)
	end

	if not serviceTable.Name then
		error("[Kore] Service is missing a Name field", 2)
	end

	if services[serviceTable.Name] then
		error("[Kore] Duplicate service name: " .. serviceTable.Name, 2)
	end

	setupServiceInstance(serviceTable)
	services[serviceTable.Name] = serviceTable

	Log.Debug("Kore", "Registered service: %s", serviceTable.Name)
end

--- Register a controller (client only). The controller table must have a `Name` field.
function Kore.AddController(controllerTable: Types.ControllerDefinition): ()
	if IS_SERVER then
		error("[Kore] AddController() can only be called on the client", 2)
	end

	if not controllerTable.Name then
		error("[Kore] Controller is missing a Name field", 2)
	end

	if controllers[controllerTable.Name] then
		error("[Kore] Duplicate controller name: " .. controllerTable.Name, 2)
	end

	controllerTable.Janitor = controllerTable.Janitor or createJanitor()
	controllerTable.Log = Log.Tagged(controllerTable.Name)
	controllers[controllerTable.Name] = controllerTable

	Log.Debug("Kore", "Registered controller: %s", controllerTable.Name)
end

--- Create and register a service (server only). Returns the service with injected Janitor/Log.
--- Use `:` method syntax after this call for full self IntelliSense.
function Kore.CreateService<T>(serviceTable: T & { Name: string }): T & Types.ServiceFields
	if not IS_SERVER then
		error("[Kore] CreateService() can only be called on the server", 2)
	end

	local svc = serviceTable :: any
	if not svc.Name then
		error("[Kore] Service is missing a Name field", 2)
	end

	if services[svc.Name] then
		error("[Kore] Duplicate service name: " .. svc.Name, 2)
	end

	setupServiceInstance(svc)
	services[svc.Name] = svc

	Log.Debug("Kore", "Registered service: %s", svc.Name)
	return serviceTable :: any
end

--- Create and register a controller (client only). Returns the controller with injected Janitor/Log.
--- Use `:` method syntax after this call for full self IntelliSense.
function Kore.CreateController<T>(controllerTable: T & { Name: string }): T & Types.ControllerFields
	if IS_SERVER then
		error("[Kore] CreateController() can only be called on the client", 2)
	end

	local ctrl = controllerTable :: any
	if not ctrl.Name then
		error("[Kore] Controller is missing a Name field", 2)
	end

	if controllers[ctrl.Name] then
		error("[Kore] Duplicate controller name: " .. ctrl.Name, 2)
	end

	ctrl.Janitor = ctrl.Janitor or createJanitor()
	ctrl.Log = Log.Tagged(ctrl.Name)
	controllers[ctrl.Name] = ctrl

	Log.Debug("Kore", "Registered controller: %s", ctrl.Name)
	return controllerTable :: any
end

-- ──────────────────────────────────────────────────────────────────────
-- Retrieval
-- ──────────────────────────────────────────────────────────────────────

--- Retrieve a service by name. On the server returns the real service; on the client returns a network proxy.
--- During Init, returns a deferred proxy that resolves after boot.
function Kore.GetService(name: string): Types.ServiceDefinition
	-- Server: return real service or proxy during Init
	if IS_SERVER then
		local svc = services[name]
		if svc then
			return svc
		end

		-- During Init, return a proxy
		if not started then
			if proxies[name] then
				return proxies[name].proxy
			end

			local proxy, resolve = Proxy.create(name)
			proxies[name] = { proxy = proxy, resolve = resolve } :: ProxyEntry
			Log.Debug("Kore", "Created proxy for undeclared GetService('%s') during Init", name)
			return proxy
		end

		error("[Kore] Unknown service: " .. tostring(name), 2)
	end

	-- Client: return client proxy
	if clientProxies[name] then
		return clientProxies[name] :: any
	end

	if not started then
		-- During init, create a proxy
		if proxies[name] then
			return proxies[name].proxy
		end

		local proxy, resolve = Proxy.create(name)
		proxies[name] = { proxy = proxy, resolve = resolve } :: ProxyEntry
		return proxy
	end

	error("[Kore] Unknown service: " .. tostring(name), 2)
end

--- Retrieve a controller by name (client only).
--- During Init, returns a deferred proxy that resolves after boot.
function Kore.GetController(name: string): Types.ControllerDefinition
	if IS_SERVER then
		error("[Kore] GetController() can only be called on the client", 2)
	end

	local ctrl = controllers[name]
	if ctrl then
		return ctrl
	end

	if not started then
		if proxies[name] then
			return proxies[name].proxy
		end

		local proxy, resolve = Proxy.create(name)
		proxies[name] = { proxy = proxy, resolve = resolve } :: ProxyEntry
		return proxy
	end

	error("[Kore] Unknown controller: " .. tostring(name), 2)
end

-- ──────────────────────────────────────────────────────────────────────
-- Boot
-- ──────────────────────────────────────────────────────────────────────

--- Boot the Kore framework. Returns a Promise that resolves when all lifecycle methods complete.
function Kore.Start(): any -- Promise<void>
	if started then
		return Promise.reject("[Kore] Already started")
	end

	return Promise.new(function(resolve, reject)
		local ok, err = pcall(function()
			if IS_SERVER then
				Kore._startServer()
			else
				Kore._startClient()
			end
		end)

		if ok then
			started = true
			resolve()
		else
			reject(err)
		end
	end)
end

function Kore._startServer(): ()
	local startTime: number = os.clock()

	-- Auto-discover services if none registered
	if next(services) == nil then
		local servicesFolder: Instance? = game:GetService("ServerScriptService"):FindFirstChild("Services")
		if servicesFolder then
			local discovered: { Types.NamedModule } = Loader.DiscoverModules(servicesFolder :: Instance)
			for _, svc in ipairs(discovered) do
				if not services[svc.Name] then
					setupServiceInstance(svc :: any)
					services[svc.Name] = svc :: any
				end
			end
		end
	end

	-- Build module list for topo sort
	local moduleList: { Types.NamedModule } = {}
	for _, svc in pairs(services) do
		table.insert(moduleList, svc :: any)
	end

	-- Topological sort
	local sorted: { Types.NamedModule } = Loader.TopologicalSort(moduleList)

	if config.Debug then
		local order: { string } = {}
		for _, svc in ipairs(sorted) do
			table.insert(order, svc.Name)
		end
		Log.Debug("Kore", "Dependency resolution order: %s", table.concat(order, " -> "))
	end

	-- Init phase (synchronous, in dependency order)
	for _, svc in ipairs(sorted) do
		if (svc :: any).Init then
			local initStart: number = os.clock()

			-- Inject declared dependencies
			if svc.Dependencies then
				for _, depName in ipairs(svc.Dependencies) do
					if services[depName] then
						svc[depName] = services[depName]
					end
				end
			end

			local ctx: Types.ContextType = {
				Log = (svc :: any).Log,
				Kore = Kore :: any,
				Config = (svc :: any).Config,
			}

			-- Detect yielding
			local initThread = coroutine.create(function()
				svc:Init(ctx)
			end)

			local success, result = coroutine.resume(initThread)
			if not success then
				error(string.format("[Kore] %s.Init() error: %s", svc.Name, tostring(result)), 0)
			end

			if coroutine.status(initThread) ~= "dead" then
				Log.Warn("Kore", "%s.Init() yielded — this is not allowed and may cause issues", svc.Name)
				-- Wait for it to complete anyway
				task.spawn(initThread)
			end

			if config.Debug then
				Log.Debug("Kore", "%s.Init() completed in %.3fms", svc.Name, (os.clock() - initStart) * 1000)
			end
		end

		-- Resolve any proxies for this service
		if proxies[svc.Name] then
			proxies[svc.Name].resolve(svc)
			Log.Debug("Kore", "Resolved proxy for '%s'", svc.Name)
		end
	end

	-- Setup remotes for all services
	for _, svc in ipairs(sorted) do
		Net.SetupServerRemotes(svc :: any)
	end

	-- Start phase (concurrent, yielding allowed)
	local startPromises: { any } = {}
	for _, svc in ipairs(sorted) do
		if (svc :: any).Start then
			table.insert(
				startPromises,
				Promise.new(function(resolveStart)
					local ctx: Types.ContextType = {
						Log = (svc :: any).Log,
						Kore = Kore :: any,
						Config = (svc :: any).Config,
					}

					local startStartTime: number = os.clock();
					(svc :: any):Start(ctx)

					if config.Debug then
						Log.Debug(
							"Kore",
							"%s.Start() completed in %.3fms",
							svc.Name,
							(os.clock() - startStartTime) * 1000
						)
					end

					resolveStart()
				end)
			)
		end
	end

	if #startPromises > 0 then
		Promise.all(startPromises):await()
	end

	if config.Debug then
		Log.Debug("Kore", "Server started in %.3fms (%d services)", (os.clock() - startTime) * 1000, #sorted)
	end
end

function Kore._startClient(): ()
	local startTime: number = os.clock()

	-- Auto-discover controllers
	if next(controllers) == nil then
		local controllersFolder: Instance? = game:GetService("Players").LocalPlayer
			and game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)

		if controllersFolder then
			local ctrlFolder: Instance? = (controllersFolder :: Instance):FindFirstChild("Controllers")
			if ctrlFolder then
				local discovered: { Types.NamedModule } = Loader.DiscoverModules(ctrlFolder :: Instance)
				for _, ctrl in ipairs(discovered) do
					if not controllers[ctrl.Name] then
						(ctrl :: any).Janitor = (ctrl :: any).Janitor or createJanitor();
						(ctrl :: any).Log = Log.Tagged(ctrl.Name)
						controllers[ctrl.Name] = ctrl
					end
				end
			end
		end
	end

	-- Build client proxies for services (from remotes)
	local remotesFolder: Instance? = game:GetService("ReplicatedStorage"):WaitForChild("KoreRemotes", 30)
	if remotesFolder then
		for _, serviceFolder in ipairs((remotesFolder :: Instance):GetChildren()) do
			clientProxies[serviceFolder.Name] = Net.CreateClientProxy(serviceFolder.Name, Promise) :: any
		end
	end

	-- Resolve service proxies
	for name, proxyData: ProxyEntry in pairs(proxies) do
		if clientProxies[name] then
			proxyData.resolve(clientProxies[name])
		elseif controllers[name] then
			proxyData.resolve(controllers[name])
		end
	end

	-- Build module list for topo sort
	local moduleList: { Types.NamedModule } = {}
	for _, ctrl in pairs(controllers) do
		table.insert(moduleList, ctrl :: any)
	end

	local sorted: { Types.NamedModule } = Loader.TopologicalSort(moduleList)

	if config.Debug then
		local order: { string } = {}
		for _, ctrl in ipairs(sorted) do
			table.insert(order, ctrl.Name)
		end
		Log.Debug("Kore", "Dependency resolution order: %s", table.concat(order, " -> "))
	end

	-- Init phase
	for _, ctrl in ipairs(sorted) do
		if (ctrl :: any).Init then
			local initStart: number = os.clock()

			if ctrl.Dependencies then
				for _, depName in ipairs(ctrl.Dependencies) do
					if controllers[depName] then
						ctrl[depName] = controllers[depName]
					elseif clientProxies[depName] then
						ctrl[depName] = clientProxies[depName]
					end
				end
			end

			local ctx: Types.ContextType = {
				Log = (ctrl :: any).Log,
				Kore = Kore :: any,
				Config = (ctrl :: any).Config,
			}

			local initThread: thread = coroutine.create(function()
				(ctrl :: any):Init(ctx)
			end)

			local success, result = coroutine.resume(initThread)
			if not success then
				error(string.format("[Kore] %s.Init() error: %s", ctrl.Name, tostring(result)), 0)
			end

			if coroutine.status(initThread) ~= "dead" then
				Log.Warn("Kore", "%s.Init() yielded — this is not allowed and may cause issues", ctrl.Name)
				task.spawn(initThread)
			end

			if config.Debug then
				Log.Debug("Kore", "%s.Init() completed in %.3fms", ctrl.Name, (os.clock() - initStart) * 1000)
			end
		end

		if proxies[ctrl.Name] then
			proxies[ctrl.Name].resolve(ctrl)
		end
	end

	-- Start phase
	local startPromises = {}
	-- Start phase
	local startPromises: { any } = {}
	for _, ctrl in ipairs(sorted) do
		if (ctrl :: any).Start then
			table.insert(
				startPromises,
				Promise.new(function(resolveStart)
					local ctx: Types.ContextType = {
						Log = (ctrl :: any).Log,
						Kore = Kore :: any,
						Config = (ctrl :: any).Config,
					}

					local startStartTime: number = os.clock();
					(ctrl :: any):Start(ctx)

					if config.Debug then
						Log.Debug(
							"Kore",
							"%s.Start() completed in %.3fms",
							ctrl.Name,
							(os.clock() - startStartTime) * 1000
						)
					end

					resolveStart()
				end)
			)
		end
	end

	if #startPromises > 0 then
		Promise.all(startPromises):await()
	end

	if config.Debug then
		Log.Debug("Kore", "Client started in %.3fms (%d controllers)", (os.clock() - startTime) * 1000, #sorted)
	end
end

-- ──────────────────────────────────────────────────────────────────────
-- Dynamic Destroy
-- ──────────────────────────────────────────────────────────────────────

--- Dynamically destroy and unregister a service. Requires `Destroy = "dynamic"` config.
function Kore.DestroyService(name: string): ()
	if config.Destroy ~= "dynamic" then
		error("[Kore] DestroyService requires Configure({ Destroy = 'dynamic' })", 2)
	end

	local svc: Types.ServiceDefinition? = services[name]
	if not svc then
		error("[Kore] Unknown service: " .. tostring(name), 2)
	end

	-- 1. Call Destroy() if defined
	if (svc :: Types.ServiceDefinition).Destroy then
		(svc :: Types.ServiceDefinition):Destroy()
	end

	-- 2. Clean janitor
	if (svc :: Types.ServiceDefinition).Janitor then
		(svc :: Types.ServiceDefinition).Janitor:Cleanup()
	end

	-- 3. Remove remotes
	Net.DestroyServiceRemotes(name)

	-- 4. Remove from registry
	services[name] = nil

	Log.Debug("Kore", "Destroyed service: %s", name)
end

--- Dynamically destroy and unregister a controller. Requires `Destroy = "dynamic"` config.
function Kore.DestroyController(name: string): ()
	if config.Destroy ~= "dynamic" then
		error("[Kore] DestroyController requires Configure({ Destroy = 'dynamic' })", 2)
	end

	local ctrl: Types.ControllerDefinition? = controllers[name]
	if not ctrl then
		error("[Kore] Unknown controller: " .. tostring(name), 2)
	end

	if (ctrl :: Types.ControllerDefinition).Destroy then
		(ctrl :: Types.ControllerDefinition):Destroy()
	end

	if (ctrl :: Types.ControllerDefinition).Janitor then
		(ctrl :: Types.ControllerDefinition).Janitor:Cleanup()
	end

	controllers[name] = nil

	Log.Debug("Kore", "Destroyed controller: %s", name)
end

return Kore :: Types.KoreAPI
