local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)

return function(_Context, Targets: { Player }, Amount: number): string
	return CommandUtil.ForEach(Targets, function(_Target: Player, Data: any): string
		local New = Data.Cash(function(Current: number)
			return math.max(Current + Amount, 0)
		end)

		return `${New}.`
	end)
end
