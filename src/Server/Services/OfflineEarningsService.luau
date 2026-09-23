local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local PlayerData = require(Shared.PlayerData).server
local RevenueService = require(script.Parent.RevenueService)

--> The office keeps earning while the player is away: on the way back in, every second since they
--> were last seen is paid at the rate the plot makes alone, up to three days of it. The clock is
--> the server's own, stamped into the save, so nothing the client says is involved.

--> the longest absence that is paid for, in seconds
local MaxAway = 3 * 24 * 60 * 60

--> How often the stamp is refreshed while the player is in, so a server that goes down without
--> saying goodbye loses at most this much of the absence that follows.
local StampInterval = 60

--> What was paid and for how long, published on the Player for the welcome back on the client.
local EarnedAttribute = "OfflineEarned"
local AwayAttribute = "OfflineSeconds"

local OfflineEarningsService = {
	Name = "OfflineEarningsService",

	--> players whose absence has been paid, the only ones the minute stamp touches: stamping one
	--> before the payout has read the old stamp would pay them for nothing
	Settled = {} :: { [Player]: boolean },
}

function OfflineEarningsService:_Pay(Player: Player, Data: any)
	local Last = Data.LastSeen()
	local Now = os.time()

	Data.LastSeen(Now)
	self.Settled[Player] = true

	if type(Last) ~= "number" or Last <= 0 then
		return
	end

	local Away = math.clamp(Now - Last, 0, MaxAway)
	local Amount = math.floor(RevenueService:GetSoloRate(Data) * Away)

	if Amount <= 0 then
		return
	end

	Data.Cash(function(Current: number)
		return Current + Amount
	end)

	Data.TotalCashEarned(function(Current: number)
		return Current + Amount
	end)

	Player:SetAttribute(AwayAttribute, Away)
	Player:SetAttribute(EarnedAttribute, Amount)
end

function OfflineEarningsService:_HandlePlayer(Player: Player)
	task.spawn(function()
		local Data = PlayerData.Service:waitForData(Player)

		if not Player.Parent then
			return
		end

		self:_Pay(Player, Data)
	end)
end

function OfflineEarningsService:Init()
	--> Written into the raw save just before the session ends and it is saved for the last time.
	--> The replicated value is past caring by then; there is nobody left to send it to.
	PlayerData.Service:addPlayerRemovingCallback(function(_Player: Player, Raw: any)
		Raw.LastSeen = os.time()
	end)

	for _, Player in Players:GetPlayers() do
		self:_HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:_HandlePlayer(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self.Settled[Player] = nil
	end)
end

function OfflineEarningsService:Start()
	task.spawn(function()
		while true do
			task.wait(StampInterval)

			local Now = os.time()

			for Player in self.Settled do
				local Data = PlayerData[Player]

				if Data then
					Data.LastSeen(Now)
				end
			end
		end
	end)
end

return OfflineEarningsService
