--!strict

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local Types = require(script.Parent.Types)

type PreloadConfig = Types.PreloadConfig
type PreloadResult = Types.PreloadResult
type PreloadProgress = Types.PreloadProgress

local Preloader = {}

local DEFAULT_CONFIG = {
	ChunkSize = 125,
	BackgroundChunkSize = 250,
	YieldBetweenChunks = 0.05,
	CriticalTimeout = 20,
	UIImageWarmupTimeout = 5,
	WarmupUIImages = true,
	Aggressive = true,
	Debug = false,
}

local CONTENT_PROPERTIES_BY_CLASS: { [string]: { string } } = {
	Animation = { "AnimationId" },
	Sound = { "SoundId" },
	ImageLabel = { "Image" },
	ImageButton = { "Image" },
	Decal = { "Texture" },
	Texture = { "Texture" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	SurfaceAppearance = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
	VideoFrame = { "Video" },
}

local UI_IMAGE_CLASSES = {
	ImageLabel = true,
	ImageButton = true,
}

local function now(): number
	return os.clock()
end

local function mergeConfig(config: PreloadConfig?): any
	local merged = table.clone(DEFAULT_CONFIG)

	if type(config) == "table" then
		for key, value in pairs(config :: any) do
			merged[key] = value
		end
	elseif config == true then
		merged.Aggressive = true
	end

	return merged
end

local function fireProgress(config: any, info: PreloadProgress)
	local callback = config.OnProgress
	if type(callback) == "function" then
		task.spawn(callback, info)
	end
end

local function normalizeContentId(value: string): string
	if value:match("^%d+$") then
		return "rbxassetid://" .. value
	end

	return value
end

local function addUnique<T>(list: { T }, seen: { [any]: boolean }, value: T)
	if seen[value :: any] then
		return
	end

	seen[value :: any] = true
	table.insert(list, value)
end

local function addContentId(list: { string }, seen: { [string]: boolean }, value: any)
	if type(value) ~= "string" or value == "" then
		return
	end

	local contentId = normalizeContentId(value)
	if seen[contentId] then
		return
	end

	seen[contentId] = true
	table.insert(list, contentId)
end

local function hasAnyTag(instance: Instance, tags: { string }?): boolean
	if not tags then
		return false
	end

	for _, tag in ipairs(tags) do
		if CollectionService:HasTag(instance, tag) then
			return true
		end
	end

	return false
end

local function safeReadProperty(instance: Instance, propertyName: string): any
	local ok, value = pcall(function()
		return (instance :: any)[propertyName]
	end)

	if ok then
		return value
	end

	return nil
end

local function collectFromTree(
	root: Instance,
	ignoreTags: { string }?,
	instances: { Instance },
	seenInstances: { [Instance]: boolean },
	contentIds: { string },
	seenContentIds: { [string]: boolean },
	uiImageIds: { string },
	seenUiImageIds: { [string]: boolean }
)
	local function visit(instance: Instance)
		if hasAnyTag(instance, ignoreTags) then
			return
		end

		addUnique(instances, seenInstances, instance)

		local properties = CONTENT_PROPERTIES_BY_CLASS[instance.ClassName]
		if properties then
			for _, propertyName in ipairs(properties) do
				local value = safeReadProperty(instance, propertyName)
				addContentId(contentIds, seenContentIds, value)

				if UI_IMAGE_CLASSES[instance.ClassName] and propertyName == "Image" then
					addContentId(uiImageIds, seenUiImageIds, value)
				end
			end
		end

		for _, child in ipairs(instance:GetChildren()) do
			visit(child)
		end
	end

	visit(root)
end

local function collectTaggedRoots(tags: { string }?): { Instance }
	local roots = {}
	local seen: { [Instance]: boolean } = {}

	if not tags then
		return roots
	end

	for _, tag in ipairs(tags) do
		for _, instance in ipairs(CollectionService:GetTagged(tag)) do
			addUnique(roots, seen, instance)
		end
	end

	return roots
end

local function getAggressiveRoots(controllerRoots: { Instance }?): { Instance }
	local roots = {
		ReplicatedFirst,
		ReplicatedStorage,
		StarterGui,
		StarterPlayer,
		workspace,
	}

	if controllerRoots then
		for _, root in ipairs(controllerRoots) do
			table.insert(roots, root)
		end
	end

	return roots
end

local function buildAssetSet(config: any, roots: { Instance }?, tags: { string }?, explicitAssets: { string }?)
	local instances = {}
	local contentIds = {}
	local uiImageIds = {}
	local seenInstances: { [Instance]: boolean } = {}
	local seenContentIds: { [string]: boolean } = {}
	local seenUiImageIds: { [string]: boolean } = {}

	local allRoots = {}
	if roots then
		for _, root in ipairs(roots) do
			if root and root.Parent ~= nil then
				table.insert(allRoots, root)
			end
		end
	end

	for _, taggedRoot in ipairs(collectTaggedRoots(tags)) do
		table.insert(allRoots, taggedRoot)
	end

	for _, root in ipairs(allRoots) do
		collectFromTree(
			root,
			config.IgnoreTags,
			instances,
			seenInstances,
			contentIds,
			seenContentIds,
			uiImageIds,
			seenUiImageIds
		)
	end

	if explicitAssets then
		for _, assetId in ipairs(explicitAssets) do
			addContentId(contentIds, seenContentIds, assetId)
		end
	end

	local combined = {}
	for _, instance in ipairs(instances) do
		table.insert(combined, instance)
	end
	for _, contentId in ipairs(contentIds) do
		table.insert(combined, contentId)
	end

	return combined, uiImageIds
end

local function chunkArray<T>(array: { T }, chunkSize: number): { { T } }
	local chunks = {}
	local index = 1
	local safeChunkSize = math.max(1, chunkSize)

	while index <= #array do
		local chunk = {}
		for i = index, math.min(index + safeChunkSize - 1, #array) do
			table.insert(chunk, array[i])
		end

		table.insert(chunks, chunk)
		index += safeChunkSize
	end

	return chunks
end

local function preloadChunk(
	config: any,
	phase: string,
	chunk: { any },
	result: PreloadResult,
	timeoutSeconds: number?
): boolean
	local done = false
	local ok = true
	local err: any = nil

	task.spawn(function()
		ok, err = pcall(function()
			ContentProvider:PreloadAsync(chunk, function(assetId: string, status: Enum.AssetFetchStatus)
				result.completed += 1

				if status == Enum.AssetFetchStatus.Success then
					result.successes += 1
				else
					result.failures += 1
					result.failedAssets[assetId] = status.Name
				end

				fireProgress(config, {
					phase = phase,
					completed = result.completed,
					total = result.total,
					alpha = if result.total > 0 then math.clamp(result.completed / result.total, 0, 1) else 1,
					assetId = assetId,
					status = status,
					successes = result.successes,
					failures = result.failures,
					message = nil,
				})
			end)
		end)

		done = true
	end)

	local startedAt = now()
	while not done do
		if timeoutSeconds and now() - startedAt >= timeoutSeconds then
			result.timedOut = true
			fireProgress(config, {
				phase = phase,
				completed = result.completed,
				total = result.total,
				alpha = if result.total > 0 then math.clamp(result.completed / result.total, 0, 1) else 1,
				assetId = nil,
				status = nil,
				successes = result.successes,
				failures = result.failures,
				message = "Preload timed out; continuing while Roblox finishes remaining requests in the background.",
			})
			return false
		end

		task.wait()
	end

	if not ok then
		result.failures += #chunk
		result.completed += #chunk
		for _, item in ipairs(chunk) do
			result.failedAssets[tostring(item)] = "PreloadAsyncError: " .. tostring(err)
		end
	end

	return true
end

local function preloadChunked(
	config: any,
	phase: string,
	assets: { any },
	chunkSize: number,
	timeoutSeconds: number?
): PreloadResult
	local startedAt = now()
	local result: PreloadResult = {
		total = #assets,
		completed = 0,
		successes = 0,
		failures = 0,
		failedAssets = {},
		duration = 0,
		timedOut = false,
	}

	if #assets == 0 then
		result.duration = now() - startedAt
		return result
	end

	local deadline = if timeoutSeconds then startedAt + timeoutSeconds else nil

	for _, chunk in ipairs(chunkArray(assets, chunkSize)) do
		local remaining = if deadline then math.max(0, deadline - now()) else nil
		if remaining and remaining <= 0 then
			result.timedOut = true
			break
		end

		local completed = preloadChunk(config, phase, chunk, result, remaining)
		if not completed then
			break
		end

		if config.YieldBetweenChunks and config.YieldBetweenChunks > 0 then
			task.wait(config.YieldBetweenChunks)
		else
			RunService.Heartbeat:Wait()
		end
	end

	result.duration = now() - startedAt
	return result
end

local function createWarmupGui(): ScreenGui?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		playerGui = localPlayer:WaitForChild("PlayerGui", 10) :: PlayerGui?
	end

	if not playerGui then
		return nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "__UnithubImageWarmup"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -100000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.Size = UDim2.fromOffset(1, 1)
	holder.Position = UDim2.fromOffset(0, 0)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.Visible = true
	holder.Parent = gui

	return gui
end

local function warmupUIImageIds(config: any, imageIds: { string }, timeoutSeconds: number): PreloadResult
	local startedAt = now()
	local result: PreloadResult = {
		total = #imageIds,
		completed = 0,
		successes = 0,
		failures = 0,
		failedAssets = {},
		duration = 0,
		timedOut = false,
	}

	if #imageIds == 0 then
		return result
	end

	local gui = createWarmupGui()
	if not gui then
		result.failures = #imageIds
		result.timedOut = true
		result.failedAssets.PlayerGui = "Missing PlayerGui"
		result.duration = now() - startedAt
		return result
	end

	local holder = gui:FindFirstChild("Holder") :: Frame
	local labels = {}

	for index, imageId in ipairs(imageIds) do
		local label = Instance.new("ImageLabel")
		label.Name = "Warmup_" .. index
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Size = UDim2.fromOffset(1, 1)
		label.Position = UDim2.fromOffset(0, 0)
		label.ImageTransparency = 0.01
		label.Image = imageId
		label.Visible = true
		label.Parent = holder
		table.insert(labels, label)
	end

	local loaded: { [ImageLabel]: boolean } = {}
	while now() - startedAt < timeoutSeconds do
		local allDone = true

		for _, label in ipairs(labels) do
			if not loaded[label] then
				if label.IsLoaded then
					loaded[label] = true
					result.completed += 1
					result.successes += 1
					fireProgress(config, {
						phase = "ui-warmup",
						completed = result.completed,
						total = result.total,
						alpha = math.clamp(result.completed / result.total, 0, 1),
						assetId = label.Image,
						status = Enum.AssetFetchStatus.Success,
						successes = result.successes,
						failures = result.failures,
						message = nil,
					})
				else
					allDone = false
				end
			end
		end

		if allDone then
			break
		end

		RunService.RenderStepped:Wait()
	end

	for _, label in ipairs(labels) do
		if not loaded[label] then
			result.completed += 1
			result.failures += 1
			result.failedAssets[label.Image] = "UIImageWarmupTimeout"
		end
	end

	gui:Destroy()
	result.timedOut = result.failures > 0
	result.duration = now() - startedAt
	return result
end

local function mergeResults(primary: PreloadResult, extra: PreloadResult)
	primary.total += extra.total
	primary.completed += extra.completed
	primary.successes += extra.successes
	primary.failures += extra.failures
	primary.duration += extra.duration
	primary.timedOut = primary.timedOut or extra.timedOut

	for assetId, reason in pairs(extra.failedAssets) do
		primary.failedAssets[assetId] = reason
	end
end

function Preloader.run(config: PreloadConfig?, context: { ControllerRoots: { Instance }? }?): PreloadResult
	local merged = mergeConfig(config)
	local criticalRoots = {}

	if merged.Aggressive then
		for _, root in ipairs(getAggressiveRoots(context and context.ControllerRoots or nil)) do
			table.insert(criticalRoots, root)
		end
	end

	if type(merged.CriticalRoots) == "table" then
		for _, root in ipairs(merged.CriticalRoots) do
			table.insert(criticalRoots, root)
		end
	end

	local criticalAssets, uiImageIds =
		buildAssetSet(merged, criticalRoots, merged.CriticalTags, merged.ExplicitCriticalAssets)
	local result = preloadChunked(merged, "critical", criticalAssets, merged.ChunkSize, merged.CriticalTimeout)

	if merged.WarmupUIImages then
		mergeResults(result, warmupUIImageIds(merged, uiImageIds, merged.UIImageWarmupTimeout))
	end

	local backgroundRoots = {}
	if type(merged.BackgroundRoots) == "table" then
		for _, root in ipairs(merged.BackgroundRoots) do
			table.insert(backgroundRoots, root)
		end
	end

	task.spawn(function()
		local backgroundAssets =
			buildAssetSet(merged, backgroundRoots, merged.BackgroundTags, merged.ExplicitBackgroundAssets)
		preloadChunked(merged, "background", backgroundAssets, merged.BackgroundChunkSize, nil)
	end)

	return result
end

return Preloader
