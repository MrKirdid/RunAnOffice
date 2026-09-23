local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)
local GearConfigs = require(Shared.Configs.Gears)
local GearService = require(ServerScriptService.Server.Services.GearService)

return function(_Context, Targets: { Player }, Key: string): string
	if not GearConfigs.List[Key] then
		return `no gear called {Key}. Keys: {table.concat(GearConfigs.Sorted(), ", ")}.`
	end

	return CommandUtil.ForEach(Targets, function(Target: Player): string
		if not GearService:Grant(Target, Key) then
			return `already owns {Key}.`
		end

		return `given {Key}` .. (if GearService:Equip(Target, Key, true) then ", equipped." else ", slots full.")
	end)
end
