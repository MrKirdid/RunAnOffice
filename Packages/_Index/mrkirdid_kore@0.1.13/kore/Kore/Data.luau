-- Kore.Data — Thin bridge over ProfileStore

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local resolve = require(script.Parent.PackageResolver)
local Log = require(script.Parent.Log)
local Types = require(script.Parent.Types)

type DataConfig = Types.DataConfig
type Profile = Types.Profile

local Data = {}

local profileStore: any = nil
local profiles: { [number]: Profile } = {} -- [player.UserId] = profile
local loadedCallbacks: { [number]: { (profile: Profile) -> () } } = {} -- [player.UserId] = { fn, fn, ... }

local Promise: any
local ProfileStore: any

--- Configure the Data module with a DataStore name and template.
--- Must be called before `Data.Load()`. Server-only.
function Data.Configure(config: DataConfig): ()
	if not RunService:IsServer() then
		Log.Warn("Kore.Data", "Data module is server-only")
		return
	end

	-- Lazy load dependencies
	if not Promise then
		Promise = require(resolve("promise") or script.Parent.Promise)
	end

	if not ProfileStore then
		local ok, mod = pcall(function()
			return require(resolve("profilestore") or error("not found"))
		end)
		if ok then
			ProfileStore = mod
		else
			Log.Warn("Kore.Data", "ProfileStore not found — Kore.Data will not function")
			return
		end
	end

	local storeName: string = config.StoreName or "PlayerData"
	local template: { [string]: any } = config.Template or {}

	profileStore = ProfileStore.New(storeName, template)
end

--- Load (or resume) a player's profile session. Returns a Promise that resolves with the Profile.
function Data.Load(player: Player): any -- Promise<Profile>
	if not Promise then
		Promise = require(resolve("promise") or script.Parent.Promise)
	end

	return Promise.new(function(resolvePromise: (profile: Profile) -> (), reject: (reason: string) -> ())
		if not profileStore then
			reject("Kore.Data: ProfileStore not configured. Call Kore.Data.Configure() first.")
			return
		end

		local key: string = "Player_" .. player.UserId
		local profile: Profile? = profileStore:StartSessionAsync(key, {
			Cancel = function(): boolean
				return player.Parent ~= Players
			end,
		})

		if profile then
			profile:AddUserId(player.UserId)
			profile:Reconcile()

			profile.OnSessionEnd:Connect(function()
				profiles[player.UserId] = nil
				player:Kick("Profile session ended — please rejoin")
			end)

			if player.Parent == Players then
				profiles[player.UserId] = profile

				-- Fire loaded callbacks
				local callbacks: { (profile: Profile) -> () }? = loadedCallbacks[player.UserId]
				if callbacks then
					for _, fn in ipairs(callbacks) do
						task.spawn(fn, profile)
					end
					loadedCallbacks[player.UserId] = nil
				end

				resolvePromise(profile)
			else
				profile:EndSession()
				reject("Player left before profile loaded")
			end
		else
			reject("Failed to load profile for " .. player.Name)
		end
	end)
end

--- Get a player's loaded profile, or nil if not yet loaded.
function Data.Get(player: Player): Profile?
	return profiles[player.UserId]
end

--- Register a callback to run when a player's profile is loaded.
--- If already loaded, the callback fires immediately.
function Data.OnLoaded(player: Player, fn: (profile: Profile) -> ()): ()
	local existing: Profile? = profiles[player.UserId]
	if existing then
		task.spawn(fn, existing)
		return
	end

	if not loadedCallbacks[player.UserId] then
		loadedCallbacks[player.UserId] = {}
	end
	table.insert(loadedCallbacks[player.UserId], fn)
end

--- Force-save a player's profile. Returns a Promise.
function Data.Save(player: Player): any -- Promise<void>
	if not Promise then
		Promise = require(resolve("promise") or script.Parent.Promise)
	end

	return Promise.new(function(resolvePromise: () -> (), reject: (reason: string) -> ())
		local profile: Profile? = profiles[player.UserId]
		if not profile then
			reject("No profile loaded for " .. player.Name)
			return
		end

		profile:Save()
		resolvePromise()
	end)
end

--- Release (end session) a player's profile and clear callbacks.
function Data.Release(player: Player): ()
	local profile: Profile? = profiles[player.UserId]
	if profile then
		profile:EndSession()
		profiles[player.UserId] = nil
	end
	loadedCallbacks[player.UserId] = nil
end

-- Auto-release on player leaving
if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player: Player)
		Data.Release(player)
	end)
end

return Data :: Types.DataModule
