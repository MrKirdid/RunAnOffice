local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local CommandUtil = require(Shared.Console.CommandUtil)
local DeskData = require(Shared.Utilities.DeskData)
local PlotService = require(Server.Services.PlotService)
local Rolling = require(Shared.Utilities.Rolling)

local Maximum = 50

return function(_Context, Targets: { Player }, Amount: number, Variant: string?): string
	if Amount < 1 or Amount > Maximum then
		return `Amount has to be between 1 and {Maximum}.`
	end

	return CommandUtil.ForEach(Targets, function(Target: Player, Data: any): string
		local Plot = PlotService:GetPlot(Target)

		if not Plot then
			return "no plot."
		end

		local Placed = 0

		for _ = 1, Amount do
			local Floor, Slot = DeskData.GetNextAvailable(Data, Plot)

			if not Floor or not Slot then
				break
			end

			local Desk = if Variant
				then { Computer = Variant, Keyboard = Variant, Monitor = Variant }
				else Rolling.RollDesk(Data.Luck())

			--> Writing the key replicates, which is what tells the client to spawn and roll it
			DeskData.Unlock(Data, Floor).Desks[Slot](Desk)
			Placed += 1
		end

		if Placed == 0 then
			return "every unlocked floor is full. Open one with 'floors'."
		end

		if Placed < Amount then
			return `placed {Placed}, then ran out of free slots.`
		end

		return `placed {Placed} desks.`
	end)
end
