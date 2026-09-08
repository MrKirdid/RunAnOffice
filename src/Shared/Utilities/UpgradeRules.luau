--> The rules the tree is walked by, kept away from both ends that need them: the client draws off
--> these, and the server buys off the same ones, so a node that looks buyable is buyable.
--> Everything here takes the owned set as a plain map of id to true, which is exactly what
--> PlayerData.Upgrades.Owned holds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Upgrades = require(Shared.Configs.Upgrades)

export type Owned = { [string]: boolean }

local UpgradeRules = {}

--> An action node -- the Exit button in the middle -- is never bought, but the ring around it hangs
--> off it, so it counts as owned for anything asking what is reachable.
function UpgradeRules.IsOwned(Owned: Owned, Id: string): boolean
	local Config = Upgrades.List[Id]

	if not Config then
		return false
	end

	if Config.IsAction then
		return true
	end

	return Owned[Id] == true
end

--> Buyable right now: not owned yet, and whatever it hangs off is. The root has no parent, so it
--> is open from the first join.
function UpgradeRules.IsAvailable(Owned: Owned, Id: string): boolean
	local Config = Upgrades.List[Id]

	if not Config or Config.IsAction or UpgradeRules.IsOwned(Owned, Id) then
		return false
	end

	return Config.Parent == nil or UpgradeRules.IsOwned(Owned, Config.Parent)
end

--> What the tree draws: what you have plus what you can buy next, and nothing further out. A node
--> two rings away is not hidden because it is locked, it is hidden because it is not yours to
--> think about yet.
function UpgradeRules.IsVisible(Owned: Owned, Id: string): boolean
	local Config = Upgrades.List[Id]

	if not Config then
		return false
	end

	if Config.IsAction then
		return true
	end

	return UpgradeRules.IsOwned(Owned, Id) or UpgradeRules.IsAvailable(Owned, Id)
end

function UpgradeRules.GetCost(Id: string): number
	local Config = Upgrades.List[Id]

	return if Config and Config.Cost then Config.Cost else 0
end

--> The one check the purchase goes through, on both ends. The reason is for the client to react to
--> -- a locked press is a different noise from one you cannot afford -- and the server drops it.
function UpgradeRules.CanBuy(Owned: Owned, Id: string, Cash: number): (boolean, string?)
	local Config = Upgrades.List[Id]

	if not Config then
		return false, "Unknown"
	end

	if Config.IsAction then
		return false, "Action"
	end

	if UpgradeRules.IsOwned(Owned, Id) then
		return false, "Owned"
	end

	if not UpgradeRules.IsAvailable(Owned, Id) then
		return false, "Locked"
	end

	if Cash < UpgradeRules.GetCost(Id) then
		return false, "Cash"
	end

	return true, nil
end

return UpgradeRules
