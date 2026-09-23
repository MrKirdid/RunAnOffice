--> Every player-facing command reads the same way: walk the targets, skip anyone whose save has
--> not loaded yet, and hand back one line each. Kept out of Commands/ because Cmdr registers every
--> ModuleScript in that folder as a command definition.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Admins = require(Shared.Configs.Admins)
local PlayerData = require(Shared.PlayerData).server

local CommandUtil = {}

--> Read on both realms so the console can grey itself out on a client that will only be refused,
--> but the server's own BeforeRun hook is the check that counts.
function CommandUtil.IsAdmin(Player: Player): boolean
	if RunService:IsStudio() or not Admins.RestrictInGame then
		return true
	end

	if Admins.UserIds[Player.UserId] then
		return true
	end

	return game.CreatorType == Enum.CreatorType.User and Player.UserId == game.CreatorId
end

--> Handle returns the tail of the line, so a command only writes the part that is about it.
function CommandUtil.ForEach(Targets: { Player }, Handle: (Player, any) -> string): string
	local Lines = {}

	for _, Target in Targets do
		local Data = PlayerData[Target]

		if not Data then
			table.insert(Lines, `{Target.Name}: no loaded data.`)
			continue
		end

		table.insert(Lines, `{Target.Name}: {Handle(Target, Data)}`)
	end

	if #Lines == 0 then
		return "Nobody matched."
	end

	return table.concat(Lines, "\n")
end

--> string.format is out of house style, so the readout tables pad by hand.
function CommandUtil.Pad(Text: string, Width: number): string
	local Gap = Width - #Text

	return if Gap > 0 then Text .. string.rep(" ", Gap) else Text
end

return CommandUtil
