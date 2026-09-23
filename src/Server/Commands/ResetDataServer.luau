local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local PlayerData = require(Shared.PlayerData).server

return function(_Context, Targets: { Player }): string
	--> Every name read before the first wipe: resetData kicks on its way out, and a kicked player
	--> is out of Players by the time the line about them would be written.
	local Names = {}

	for _, Target in Targets do
		Names[Target] = Target.Name
	end

	local Lines = {}

	for _, Target in Targets do
		--> RemoveAsync is a live DataStore call, so it can fail for reasons that have nothing to do
		--> with this command -- a throttle, an outage. Caught so one bad wipe reports itself and
		--> the rest of the list still runs, rather than erroring out halfway through.
		local Ok, Problem = pcall(function()
			PlayerData.Service:resetData(Target)
		end)

		table.insert(Lines, if Ok then `{Names[Target]}: wiped and kicked.` else `{Names[Target]}: {Problem}`)
	end

	if #Lines == 0 then
		return "Nobody matched."
	end

	return table.concat(Lines, "\n")
end
