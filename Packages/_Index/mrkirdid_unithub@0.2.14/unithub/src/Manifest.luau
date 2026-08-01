--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MANIFEST_NAME = "__UnithubManifest"

local Manifest = {}

local function clearChildren(instance: Instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function clearAttributes(instance: Instance, names: { string })
	for _, name in ipairs(names) do
		instance:SetAttribute(name, nil)
	end
end

local function findManifest(): Folder?
	local existing = ReplicatedStorage:FindFirstChild(MANIFEST_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	return nil
end

local function normalizeInstances(value: any): { Instance }
	if typeof(value) == "Instance" then
		return { value }
	end

	local result = {}
	if type(value) ~= "table" then
		return result
	end

	for _, item in pairs(value) do
		if typeof(item) == "Instance" then
			table.insert(result, item)
		end
	end

	return result
end

local function writeObjectValues(parent: Instance, name: string, values: { Instance })
	local folder = getOrCreateFolder(parent, name)
	clearChildren(folder)

	for index, value in ipairs(values) do
		local objectValue = Instance.new("ObjectValue")
		objectValue.Name = ("%03d_%s"):format(index, value.Name)
		objectValue.Value = value
		objectValue.Parent = folder
	end
end

local function readObjectValues(parent: Instance?, name: string): { Instance }
	local result = {}
	if not parent then
		return result
	end

	local folder = parent:FindFirstChild(name)
	if not folder then
		return result
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ObjectValue") and child.Value then
			table.insert(result, child.Value)
		end
	end

	return result
end

local function writeStringValues(parent: Instance, name: string, values: { string }?)
	local folder = getOrCreateFolder(parent, name)
	clearChildren(folder)

	if not values then
		return
	end

	for index, value in ipairs(values) do
		if type(value) == "string" and value ~= "" then
			local stringValue = Instance.new("StringValue")
			stringValue.Name = ("%03d"):format(index)
			stringValue.Value = value
			stringValue.Parent = folder
		end
	end
end

local function readStringValues(parent: Instance?, name: string): { string }
	local result = {}
	if not parent then
		return result
	end

	local folder = parent:FindFirstChild(name)
	if not folder then
		return result
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("StringValue") and child.Value ~= "" then
			table.insert(result, child.Value)
		end
	end

	return result
end

function Manifest.write(config: any)
	local manifest = getOrCreateFolder(ReplicatedStorage, MANIFEST_NAME)
	manifest:SetAttribute("Version", 2)
	manifest:SetAttribute("CreatedAt", os.clock())
	manifest:SetAttribute("ServerServicesReady", false)
	manifest:SetAttribute("ServerServicesFailed", false)
	manifest:SetAttribute("ServerServicesReadyAt", nil)
	manifest:SetAttribute("ServerServicesCompletedAt", nil)
	manifest:SetAttribute("ServerServiceFailureCount", 0)
	manifest:SetAttribute("Timeout", config.Timeout or config.timeout or 10)
	manifest:SetAttribute("RequireTimeout", config.RequireTimeout or config.Timeout or config.timeout or 10)
	manifest:SetAttribute("LifecycleTimeout", config.LifecycleTimeout or config.Timeout or config.timeout or 10)
	manifest:SetAttribute("Watch", if config.Watch == nil then true else config.Watch)
	manifest:SetAttribute("StrictDuplicates", if config.StrictDuplicates == nil then true else config.StrictDuplicates)

	local preload = config.Preload
	if preload == nil then
		preload = config.preload
	end

	manifest:SetAttribute("PreloadEnabled", preload ~= nil and preload ~= false)
	manifest:SetAttribute(
		"PreloadAggressive",
		preload == true or (type(preload) == "table" and preload.Aggressive ~= false)
	)

	writeObjectValues(manifest, "Controllers", normalizeInstances(config.Controllers or config.controllers))

	local preloadFolder = getOrCreateFolder(manifest, "Preload")
	clearChildren(preloadFolder)
	clearAttributes(preloadFolder, {
		"ChunkSize",
		"BackgroundChunkSize",
		"YieldBetweenChunks",
		"CriticalTimeout",
		"UIImageWarmupTimeout",
		"WarmupUIImages",
	})

	if type(preload) == "table" then
		for _, key in ipairs({
			"ChunkSize",
			"BackgroundChunkSize",
			"YieldBetweenChunks",
			"CriticalTimeout",
			"UIImageWarmupTimeout",
		}) do
			if type(preload[key]) == "number" then
				preloadFolder:SetAttribute(key, preload[key])
			end
		end

		if type(preload.WarmupUIImages) == "boolean" then
			preloadFolder:SetAttribute("WarmupUIImages", preload.WarmupUIImages)
		end

		writeObjectValues(preloadFolder, "CriticalRoots", normalizeInstances(preload.CriticalRoots))
		writeObjectValues(preloadFolder, "BackgroundRoots", normalizeInstances(preload.BackgroundRoots))
		writeStringValues(preloadFolder, "CriticalTags", preload.CriticalTags)
		writeStringValues(preloadFolder, "BackgroundTags", preload.BackgroundTags)
		writeStringValues(preloadFolder, "IgnoreTags", preload.IgnoreTags)
		writeStringValues(preloadFolder, "ExplicitCriticalAssets", preload.ExplicitCriticalAssets)
		writeStringValues(preloadFolder, "ExplicitBackgroundAssets", preload.ExplicitBackgroundAssets)
	end

	return manifest
end

function Manifest.markServerServicesReady(failureCount: number?)
	local manifest = findManifest()
	if not manifest then
		return
	end

	local failures = failureCount or 0
	local completedAt = os.clock()

	manifest:SetAttribute("ServerServiceFailureCount", failures)
	manifest:SetAttribute("ServerServicesCompletedAt", completedAt)
	manifest:SetAttribute("ServerServicesFailed", failures > 0)
	manifest:SetAttribute("ServerServicesReadyAt", if failures > 0 then nil else completedAt)
	manifest:SetAttribute("ServerServicesReady", failures == 0)
end

function Manifest.waitFor(timeout: number?): Folder?
	local existing = findManifest()
	if existing then
		return existing
	end

	local waited: Instance?
	if timeout == nil then
		waited = ReplicatedStorage:WaitForChild(MANIFEST_NAME, 10)
	elseif timeout > 0 then
		waited = ReplicatedStorage:WaitForChild(MANIFEST_NAME, timeout)
	else
		waited = ReplicatedStorage:WaitForChild(MANIFEST_NAME)
	end

	if waited and waited:IsA("Folder") then
		return waited
	end

	return nil
end

local function getServerServiceFailureMessage(manifest: Folder): string
	local failureCount = manifest:GetAttribute("ServerServiceFailureCount")
	if type(failureCount) == "number" and failureCount > 0 then
		local suffix = if failureCount == 1 then "" else "s"
		return ("Server services failed (%d failure%s)"):format(failureCount, suffix)
	end

	return "Server services failed"
end

function Manifest.waitForServerServicesReady(timeout: number?): (boolean, string?)
	local manifest = Manifest.waitFor(timeout)
	if not manifest then
		return false, "Server manifest was not replicated"
	end

	local startedAt = os.clock()
	local limit = timeout or 10

	while manifest:GetAttribute("ServerServicesReady") ~= true do
		if manifest:GetAttribute("ServerServicesFailed") == true then
			return false, getServerServiceFailureMessage(manifest)
		end

		if limit > 0 and os.clock() - startedAt >= limit then
			return false, "Timed out waiting for server services to finish loading"
		end

		task.wait()
	end

	return true, nil
end

function Manifest.read(timeout: number?): any
	local manifest = Manifest.waitFor(timeout)
	if not manifest then
		return nil
	end

	local preloadFolder = manifest:FindFirstChild("Preload")
	local preloadEnabled = manifest:GetAttribute("PreloadEnabled") == true

	local preloadConfig: any = false
	if preloadEnabled then
		preloadConfig = {
			Aggressive = manifest:GetAttribute("PreloadAggressive") ~= false,
			CriticalRoots = readObjectValues(preloadFolder, "CriticalRoots"),
			BackgroundRoots = readObjectValues(preloadFolder, "BackgroundRoots"),
			CriticalTags = readStringValues(preloadFolder, "CriticalTags"),
			BackgroundTags = readStringValues(preloadFolder, "BackgroundTags"),
			IgnoreTags = readStringValues(preloadFolder, "IgnoreTags"),
			ExplicitCriticalAssets = readStringValues(preloadFolder, "ExplicitCriticalAssets"),
			ExplicitBackgroundAssets = readStringValues(preloadFolder, "ExplicitBackgroundAssets"),
		}

		if preloadFolder then
			for _, key in ipairs({
				"ChunkSize",
				"BackgroundChunkSize",
				"YieldBetweenChunks",
				"CriticalTimeout",
				"UIImageWarmupTimeout",
			}) do
				local value = preloadFolder:GetAttribute(key)
				if type(value) == "number" then
					preloadConfig[key] = value
				end
			end

			local warmup = preloadFolder:GetAttribute("WarmupUIImages")
			if type(warmup) == "boolean" then
				preloadConfig.WarmupUIImages = warmup
			end
		end
	end

	return {
		Controllers = readObjectValues(manifest, "Controllers"),
		Preload = preloadConfig,
		Timeout = manifest:GetAttribute("Timeout"),
		RequireTimeout = manifest:GetAttribute("RequireTimeout"),
		LifecycleTimeout = manifest:GetAttribute("LifecycleTimeout"),
		Watch = manifest:GetAttribute("Watch"),
		StrictDuplicates = manifest:GetAttribute("StrictDuplicates"),
	}
end

return Manifest
