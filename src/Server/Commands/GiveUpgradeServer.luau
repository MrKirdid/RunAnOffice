local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local CommandUtil = require(Shared.Console.CommandUtil)
local UpgradeService = require(Server.Services.UpgradeService)
local Upgrades = require(Shared.Configs.Upgrades)

--> Parents before children, so granting the whole tree walks it the way a player would rather than
--> in whatever order the config table happens to hash into.
local function InOrder(): { string }
	local Ordered = {}
	local Placed = {}

	local function Place(Id: string)
		local Config = Upgrades.List[Id]

		if Placed[Id] or not Config or Config.IsAction then
			return
		end

		Placed[Id] = true

		if Config.Parent then
			Place(Config.Parent)
		end

		table.insert(Ordered, Id)
	end

	for Id in Upgrades.List do
		Place(Id)
	end

	return Ordered
end

return function(_Context, Targets: { Player }, Upgrade: string): string
	local Wanted = if Upgrade == "all" then InOrder() else { Upgrade }

	return CommandUtil.ForEach(Targets, function(Target: Player, _Data: any): string
		local Granted = 0

		for _, Id in Wanted do
			if UpgradeService:Grant(Target, Id) then
				Granted += 1
			end
		end

		if Granted == 0 then
			return "already owned everything asked for."
		end

		return `granted {Granted} upgrade` .. (if Granted == 1 then "." else "s.")
	end)
end
