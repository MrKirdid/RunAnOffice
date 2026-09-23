local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local UpgradeDefinitions = require(Shared.Configs.UpgradeDefinitions)
local UpgradeRules = require(Shared.Utilities.UpgradeRules)
local PlayerData = require(Shared.PlayerData).server
local TutorialConfigs = require(Shared.Configs.Tutorial)

local UpgradeService = {}

--> The tutorial's upgrade is on the house. Only while the save is on that step and only for a
--> node the player has otherwise earned: the price is waived, the rules are not.
function UpgradeService:IsFree(Data: any): boolean
	return TutorialConfigs.IsOn(Data, "Upgrades")
end

function UpgradeService:GetOwned(Player: Player): UpgradeRules.Owned
	local Data = PlayerData[Player]
	local Owned = Data and Data.Upgrades.Owned()

	return if type(Owned) == "table" then Owned else {}
end

function UpgradeService:IsOwned(Player: Player, Id: string): boolean
	return UpgradeRules.IsOwned(self:GetOwned(Player), Id)
end

--> Everything an upgrade does happens here and nowhere else: the node is written into the save and
--> the effect runs once. Nothing replays effects on join -- the save holds what they did -- so this
--> is the only moment an upgrade is ever applied. No price and no gate, so the console can hand a
--> node over for testing; Buy is the paid path in front of it.
function UpgradeService:Grant(Player: Player, Id: string): boolean
	local Data = PlayerData[Player]

	if not Data or UpgradeRules.IsOwned(self:GetOwned(Player), Id) then
		return false
	end

	--> Marked owned before the effect runs, so an effect that throws still leaves the node bought
	--> rather than letting it be paid for and applied twice.
	Data.Upgrades.Owned[Id](true)

	local Definition = UpgradeDefinitions[Id]

	if Definition then
		local Success, Error = pcall(Definition.OnPurchase, {
			Player = Player,
			Data = Data,
			Id = Id,
		})

		if not Success then
			warn(`[Upgrades] "{Id}" was bought but its effect errored: {Error}`)
		end
	else
		--> A node in the tree with nothing wired to it yet. It is still bought and still saved, so
		--> filling the definition in later does not need the purchase repeating.
		warn(`[Upgrades] "{Id}" has no effect in Configs.UpgradeDefinitions`)
	end

	return true
end

--> The paid path the tree presses: the rules are checked, the price comes off, and the grant above
--> does the rest.
function UpgradeService:Buy(Player: Player, Id: string): boolean
	local Data = PlayerData[Player]

	if not Data then
		return false
	end

	local Free = self:IsFree(Data)
	local Allowed = UpgradeRules.CanBuy(self:GetOwned(Player), Id, if Free then math.huge else Data.Cash())

	if not Allowed then
		--> Not a warning: a stale tree on a slow client presses a node somebody else's purchase
		--> already took, and that is a refusal rather than a fault.
		return false
	end

	local Cost = if Free then 0 else UpgradeRules.GetCost(Id)

	if Cost > 0 then
		Data.Cash(function(Current: number)
			return Current - Cost
		end)
	end

	return self:Grant(Player, Id)
end

function UpgradeService:Init()
	NetworkingServer.Upgrades.Buy.On(function(Player: Player, Id: string)
		return self:Buy(Player, Id)
	end)
end

return UpgradeService
