local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)
local TutorialConfigs = require(Shared.Configs.Tutorial)
local TutorialService = require(ServerScriptService.Server.Services.TutorialService)

return function(_Context, Targets: { Player }, Stage: number): string
	return CommandUtil.ForEach(Targets, function(Target: Player): string
		local Landed = TutorialService:SetStage(Target, Stage)

		if not Landed then
			return "no loaded data."
		end

		if Landed > #TutorialConfigs.Stages then
			return "tutorial done."
		end

		return `on step {Landed}, {TutorialConfigs.Stages[Landed].Name}.`
	end)
end
