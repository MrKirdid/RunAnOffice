local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local CommandUtil = require(Shared.Console.CommandUtil)
local DeskData = require(Shared.Utilities.DeskData)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local PlotService = require(Server.Services.PlotService)

return function(_Context, Targets: { Player }, Count: number): string
	local Wanted = math.max(Count, 0)

	return CommandUtil.ForEach(Targets, function(Target: Player, Data: any): string
		local Plot = PlotService:GetPlot(Target)

		if not Plot then
			return "no plot."
		end

		local Unlocked = {}
		for _, Floor in DeskData.GetFloors(Data) do
			Unlocked[Floor] = true
		end

		local Opened = {}

		for Floor = 1, Wanted do
			--> A floor with no placement markers is not a floor the plot has, so it is skipped
			--> rather than unlocked into an empty key nothing can ever fill.
			if Unlocked[Floor] or DeskPlacements.GetCount(Plot, Floor) == 0 then
				continue
			end

			DeskData.Unlock(Data, Floor)
			table.insert(Opened, Floor)
		end

		local Closed = {}

		--> Collected first: locking writes into the same table GetFloors reads.
		for _, Floor in DeskData.GetFloors(Data) do
			if Floor > Wanted then
				table.insert(Closed, Floor)
			end
		end

		for _, Floor in Closed do
			DeskData.Lock(Data, Floor)
		end

		if #Opened == 0 and #Closed == 0 then
			return `already sitting on {Wanted} floors.`
		end

		local Parts = {}

		if #Opened > 0 then
			table.insert(Parts, `opened {table.concat(Opened, ", ")}`)
		end

		if #Closed > 0 then
			table.insert(Parts, `closed {table.concat(Closed, ", ")}`)
		end

		return table.concat(Parts, ", ") .. "."
	end)
end
