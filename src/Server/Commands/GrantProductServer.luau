local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local CommandUtil = require(Shared.Console.CommandUtil)
local MonetizationService = require(Server.Services.MonetizationService)

return function(_Context, Targets: { Player }, Key: string): string
	return CommandUtil.ForEach(Targets, function(Target: Player, Data: any): string
		local Ok, Result = pcall(function()
			return MonetizationService:Grant(Target, Data, Key)
		end)

		if not Ok then
			return `failed: {Result}`
		end

		return if Result then `granted {Key}.` else `nothing called {Key}, or nothing left to grant.`
	end)
end
