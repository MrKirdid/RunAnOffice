local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)
local DeskData = require(Shared.Utilities.DeskData)

return function(_Context, Targets: { Player }): string
	return CommandUtil.ForEach(Targets, function(_Target: Player, Data: any): string
		return `cleared {DeskData.Clear(Data)} desks.`
	end)
end
