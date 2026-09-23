local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)

local Minimum, Maximum = 1, 17

return function(_Context, Targets: { Player }, Amount: number): string
	if Amount < Minimum or Amount > Maximum then
		return `Pads have to be {Minimum} to {Maximum}, the packet carries no more.`
	end

	return CommandUtil.ForEach(Targets, function(_Target: Player, Data: any): string
		Data.RerollPads(Amount)

		return `{Amount} reroll pads.`
	end)
end
