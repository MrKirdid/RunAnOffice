local Server = script.Parent.Parent

local PlotService = require(Server.Services.PlotService)

return function(_Context, Targets: { Player }): string
	local Lines = {}

	for _, Target in Targets do
		--> TeleportPlayerToPlot waits on CharacterAdded when there is nothing to move, which would
		--> hang the command until they respawn. Reported instead.
		if not Target.Character then
			table.insert(Lines, `{Target.Name}: no character.`)
			continue
		end

		if not PlotService:GetPlot(Target) then
			table.insert(Lines, `{Target.Name}: no plot.`)
			continue
		end

		PlotService:TeleportPlayerToPlot(Target)
		table.insert(Lines, `{Target.Name}: sent home.`)
	end

	if #Lines == 0 then
		return "Nobody matched."
	end

	return table.concat(Lines, "\n")
end
