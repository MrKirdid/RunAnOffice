-- Kore.Net — Automatic remote generation and networking

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Log = require(script.Parent.Log)
local Middleware = require(script.Middleware)
local RateLimitMod = require(script.RateLimit)
local Compression = require(script.Compression)
local Batcher = require(script.Batcher)
local Types = require(script.Parent.Types)

type ServiceDefinition = Types.ServiceDefinition
type ClientTable = Types.ClientTable
type MiddlewareDef = Types.MiddlewareDef
type RateLimitConfig = Types.RateLimitConfig
type CompressionStrategy = Types.CompressionStrategy
type CompressionConfig = Types.CompressionConfig
type ClientEventProxy = Types.ClientEventProxy

local IS_SERVER: boolean = RunService:IsServer()

local Net = {}
Net._remotes = {} :: { [string]: { [string]: Instance } }
Net._remoteFolder = nil :: Folder?

local function getRemoteFolder(): Folder?
	if Net._remoteFolder then
		return Net._remoteFolder
	end

	if IS_SERVER then
		local folder: Folder = Instance.new("Folder")
		folder.Name = "KoreRemotes"
		folder.Parent = game:GetService("ReplicatedStorage")
		Net._remoteFolder = folder
		return folder
	else
		local folder: Instance? = game:GetService("ReplicatedStorage"):WaitForChild("KoreRemotes", 30)
		if not folder then
			Log.Warn("Kore.Net", "KoreRemotes folder not found — server may not have started")
		end
		Net._remoteFolder = folder :: Folder?
		return folder :: Folder?
	end
end

local function getServiceFolder(serviceName: string): Folder?
	local root: Folder? = getRemoteFolder()
	if not root then
		return nil
	end

	if IS_SERVER then
		local folder: Instance? = (root :: Folder):FindFirstChild(serviceName)
		if not folder then
			local newFolder: Folder = Instance.new("Folder")
			newFolder.Name = serviceName
			newFolder.Parent = root
			return newFolder
		end
		return folder :: Folder
	else
		return (root :: Folder):WaitForChild(serviceName, 15) :: Folder?
	end
end

--- SERVER: Create remotes for a service's Client table.
function Net.SetupServerRemotes(service: ServiceDefinition): ()
	if not IS_SERVER then
		return
	end

	local clientTable: ClientTable? = service.Client
	if not clientTable then
		return
	end

	local serviceName: string = service.Name
	local folder: Folder? = getServiceFolder(serviceName)
	Net._remotes[serviceName] = {}

	local middlewareDefs: { [string]: MiddlewareDef } = (clientTable :: ClientTable).Middleware or {} :: any
	local rateLimitDefs: { [string]: RateLimitConfig } = (clientTable :: ClientTable).RateLimit or {} :: any

	for key: string, value: any in pairs(clientTable :: any) do
		if key == "Middleware" or key == "RateLimit" or key == "Batching" then
			continue
		end

		-- Determine type of remote
		local handler: any = value
		local isUnreliable: boolean = false
		local isImmediate: boolean = false

		if type(value) == "table" and value._isSymbol then
			-- Kore.NetEvent sentinel — server-to-client event remote
			local remote: RemoteEvent = Instance.new("RemoteEvent")
			remote.Name = key
			remote.Parent = folder
			Net._remotes[serviceName][key] = remote
			continue
		end

		if type(value) == "table" and value.fn then
			handler = value.fn
			isUnreliable = value.Unreliable == true
			isImmediate = value.Immediate == true
		end

		if type(handler) ~= "function" then
			continue
		end

		local mw: MiddlewareDef? = middlewareDefs[key]
		local rl: RateLimitConfig? = rateLimitDefs[key]

		if isUnreliable then
			local remote: UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
			remote.Name = key
			remote.Parent = folder
			Net._remotes[serviceName][key] = remote

			remote.OnServerEvent:Connect(function(player: Player, ...: any)
				if not RateLimitMod.Check(serviceName .. "." .. key, player, rl) then
					return
				end

				local pass: boolean, a1: any, a2: any, a3: any, a4: any, a5: any, a6: any, a7: any, a8: any =
					Middleware.RunInbound(mw, player, ...)
				if not pass then
					return
				end

				handler(service, player, a1, a2, a3, a4, a5, a6, a7, a8)
			end)
		else
			local remote: RemoteFunction = Instance.new("RemoteFunction")
			remote.Name = key
			remote.Parent = folder
			Net._remotes[serviceName][key] = remote

			remote.OnServerInvoke = function(player: Player, ...: any): any
				if not RateLimitMod.Check(serviceName .. "." .. key, player, rl) then
					return nil
				end

				local pass: boolean, a1: any, a2: any, a3: any, a4: any, a5: any, a6: any, a7: any, a8: any =
					Middleware.RunInbound(mw, player, ...)
				if not pass then
					return nil
				end

				local ok: boolean, result: any = pcall(handler, service, player, a1, a2, a3, a4, a5, a6, a7, a8)
				if not ok then
					Log.ErrorNoThrow(serviceName, "Client method '%s' error: %s", key, tostring(result))
					if RunService:IsStudio() then
						error(string.format("[%s.Client.%s] %s", serviceName, key, tostring(result)))
					end
					return nil
				end

				result = Middleware.RunOutbound(mw, player, result)
				return result
			end
		end
	end

	-- Setup FireClient and FireAllClients helpers on the service
	service.FireClient = function(self: ServiceDefinition, eventName: string, player: Player, ...: any): ()
		local remote: Instance? = Net._remotes[serviceName] and Net._remotes[serviceName][eventName]
		if remote and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent):FireClient(player, ...)
		elseif remote and remote:IsA("UnreliableRemoteEvent") then
			(remote :: UnreliableRemoteEvent):FireClient(player, ...)
		end
	end

	service.FireAllClients = function(self: ServiceDefinition, eventName: string, ...: any): ()
		local remote: Instance? = Net._remotes[serviceName] and Net._remotes[serviceName][eventName]
		if remote and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent):FireAllClients(...)
		elseif remote and remote:IsA("UnreliableRemoteEvent") then
			(remote :: UnreliableRemoteEvent):FireAllClients(...)
		end
	end

	-- Cleanup rate limit data when player leaves
	Players.PlayerRemoving:Connect(function(player: Player)
		RateLimitMod.ClearPlayer(player)
	end)
end

--- CLIENT: Create a client proxy that wraps remote calls in Promises.
function Net.CreateClientProxy(serviceName: string, PromiseLib: any): { [string]: any }?
	if IS_SERVER then
		return nil
	end

	local folder: Folder? = getServiceFolder(serviceName)
	if not folder then
		Log.Warn("Kore.Net", "Service folder for '%s' not found on client", serviceName)
		return nil
	end

	local proxy: { [string]: any } = {}

	for _, remote: Instance in ipairs((folder :: Folder):GetChildren()) do
		local remoteName: string = remote.Name

		if remote:IsA("RemoteFunction") then
			proxy[remoteName] = function(...: any): any
				local args = table.pack(...)
				return PromiseLib.new(function(resolvePromise: (result: any) -> (), reject: (err: any) -> ())
					local ok: boolean, result: any =
						pcall((remote :: RemoteFunction).InvokeServer, remote, table.unpack(args, 1, args.n))
					if ok then
						resolvePromise(result)
					else
						reject(result)
					end
				end)
			end
		elseif remote:IsA("RemoteEvent") then
			-- Expose as a Signal-like object
			local connections: { RBXScriptConnection } = {}
			proxy[remoteName] = {
				Connect = function(_: any, fn: (...any) -> ()): RBXScriptConnection
					local conn: RBXScriptConnection = (remote :: RemoteEvent).OnClientEvent:Connect(fn)
					table.insert(connections, conn)
					return conn
				end,
				Once = function(_: any, fn: (...any) -> ()): RBXScriptConnection
					return (remote :: RemoteEvent).OnClientEvent:Once(fn)
				end,
				Wait = function(_: any): ...any
					return (remote :: RemoteEvent).OnClientEvent:Wait()
				end,
				DisconnectAll = function(_: any): ()
					for _, conn in ipairs(connections) do
						conn:Disconnect()
					end
					table.clear(connections)
				end,
			} :: ClientEventProxy
		elseif remote:IsA("UnreliableRemoteEvent") then
			proxy[remoteName] = function(...: any): ()
				(remote :: UnreliableRemoteEvent):FireServer(...)
			end
		end
	end

	return proxy
end

--- Remove remotes for a destroyed service.
function Net.DestroyServiceRemotes(serviceName: string): ()
	local folder: Folder? = getRemoteFolder()
	if folder then
		local serviceFolder: Instance? = (folder :: Folder):FindFirstChild(serviceName)
		if serviceFolder then
			serviceFolder:Destroy()
		end
	end
	Net._remotes[serviceName] = nil
end

--- Set the compression strategy for networking.
function Net.SetCompression(config: CompressionStrategy | CompressionConfig): ()
	Compression.SetStrategy(config)
end

return Net :: Types.NetModule
