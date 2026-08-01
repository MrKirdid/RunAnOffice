-- Kore.PackageResolver — Resolves Wally packages across ReplicatedStorage and ServerStorage
-- Searches: ReplicatedStorage.Shared.Packages → recursive ReplicatedStorage → ServerStorage (server only)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER: boolean = RunService:IsServer()

local cache: { [string]: Instance } = {}

local function recursiveFind(root: Instance, name: string): Instance?
	local found: Instance? = root:FindFirstChild(name, true)
	if found then
		return found
	end
	return nil
end

--- Resolve a Wally package by name. Returns the ModuleScript Instance, or `nil` if not found.
local function resolve(packageName: string): Instance?
	local lower: string = string.lower(packageName)
	if cache[lower] then
		return cache[lower]
	end

	-- 1. ReplicatedStorage.Shared.Packages (Wally shared packages)
	local shared: Instance? = ReplicatedStorage:FindFirstChild("Shared")
	if shared then
		local packages: Instance? = (shared :: Instance):FindFirstChild("Packages")
		if packages then
			local found: Instance? = (packages :: Instance):FindFirstChild(packageName)
			if found then
				cache[lower] = found :: Instance
				return found
			end
		end
	end

	-- 2. ReplicatedStorage.Packages (legacy/dev layout)
	local repPackages: Instance? = ReplicatedStorage:FindFirstChild("Packages")
	if repPackages then
		local found: Instance? = (repPackages :: Instance):FindFirstChild(packageName)
		if found then
			cache[lower] = found :: Instance
			return found
		end
	end

	-- 3. Recursive search in ReplicatedStorage
	local found: Instance? = recursiveFind(ReplicatedStorage, packageName)
	if found then
		cache[lower] = found :: Instance
		return found
	end

	-- 4. Server-only: check ServerStorage / ServerScriptService
	if IS_SERVER then
		local ServerStorage: ServerStorage = game:GetService("ServerStorage")

		-- ServerStorage.ServerPackages
		local serverPkgs: Instance? = ServerStorage:FindFirstChild("ServerPackages")
		if serverPkgs then
			local serverFound: Instance? = (serverPkgs :: Instance):FindFirstChild(packageName)
			if serverFound then
				cache[lower] = serverFound :: Instance
				return serverFound
			end
		end

		-- Recursive search in ServerStorage
		local serverFound: Instance? = recursiveFind(ServerStorage, packageName)
		if serverFound then
			cache[lower] = serverFound :: Instance
			return serverFound
		end
	end

	return nil
end

return resolve
