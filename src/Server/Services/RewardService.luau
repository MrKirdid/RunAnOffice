local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local RevenueService = require(script.Parent.RevenueService)
local RewardConfigs = require(Shared.Configs.Rewards)

--> The free cash on the hud. Everything about it is the server's: the clock is os.time() against
--> the save, and the amount is the player's own rate as RevenueService pays it, so a client can
--> neither claim early nor say how much it is owed.
local RewardService = {
	Name = "RewardService",
}

function RewardService:Claim(Player: Player): number
	local Data = PlayerData[Player]

	if not Data then
		return 0
	end

	local Now = os.time()

	if Now - Data.LastClaim() < RewardConfigs.ClaimInterval then
		return 0
	end

	local Amount = math.floor(RevenueService:GetRate(Player) * RewardConfigs.ClaimSeconds)

	--> nothing earning yet is nothing to pay, and the claim is not used up on it
	if Amount <= 0 then
		return 0
	end

	Data.LastClaim(Now)

	Data.Cash(function(Current: number)
		return Current + Amount
	end)

	Data.TotalCashEarned(function(Current: number)
		return Current + Amount
	end)

	return Amount
end

function RewardService:Init()
	NetworkingServer.Rewards.Claim.On(function(Player): number
		return self:Claim(Player)
	end)
end

return RewardService
