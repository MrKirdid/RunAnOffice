local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)
local GearService = require(ServerScriptService.Server.Services.GearService)

--> An upgrade's effect runs once at purchase and writes into these, and nothing recomputes them
--> from the owned set, so unowning a node means putting back what it nudged. These are the fresh
--> save values from PlayerData's template.
local BaseMultiplier = 1
local BaseDefense = 0
local BasePads = 9
local BaseLuck = 1
local BaseGearSlots = 2

return function(_Context, Targets: { Player }): string
	return CommandUtil.ForEach(Targets, function(Target: Player, Data: any): string
		local Owned = Data.Upgrades.Owned()
		local Count = 0

		for _ in if type(Owned) == "table" then Owned else {} do
			Count += 1
		end

		Data.Upgrades.Owned({})

		Data.Multipliers.Cash(BaseMultiplier)
		Data.Multipliers.EmployeeSpeed(BaseMultiplier)
		Data.Multipliers.RollSpeed(BaseMultiplier)
		Data.Multipliers.WalkSpeed(BaseMultiplier)
		Data.Luck(BaseLuck)
		Data.GearSlots(BaseGearSlots)

		--> the slots going back down takes out whatever no longer fits, so the save never holds more
		--> equipped than it has room for
		Data.EquippedGears({})
		GearService:Apply(Target)

		Data.Defense(BaseDefense)
		Data.RerollPads(BasePads)

		return `unowned {Count}, multipliers, luck, gear slots and pads back to default, gear unequipped.`
	end)
end
