local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local DeskData = require(Shared.Utilities.DeskData)
local DeskPurchase = require(Shared.Utilities.DeskPurchase)
local PlayerData = require(Shared.PlayerData).server
local PlotService = require(script.Parent.PlotService)

local PurchaseHandlerService = {}

--> Which desk is bought and what it costs are both worked out here off the save, never sent up:
--> the client only ever says that the board was pressed.
function PurchaseHandlerService:BuyDesk(Player: Player): boolean
	local Data = PlayerData[Player]
	local Plot = PlotService:GetPlot(Player)

	if not Data or not Plot then
		return false
	end

	local Next = DeskPurchase.Next(Data, Plot)

	--> Nothing left on the plot to buy, which is what the board reads as MAX.
	if not Next then
		return false
	end

	if Data.Cash() < Next.Price then
		return false
	end

	--> Every reason to turn it down is out of the way, so the charge and the desk land together.
	--> Nothing between here and the write yields, so a second press cannot read the same balance.
	Data.Cash(function(Current: number)
		return math.max(Current - Next.Price, 0)
	end)

	--> Bought bare: nothing stands on it until the gift over each slot is opened, which is what
	--> rolls that part. An empty record is still a standing desk everywhere else the data is read.
	--> Unlock is what opens the floor when the desk is the first one on it, so filling a floor and
	--> buying one more is the whole of moving upstairs. The floor is looked up through DeskData,
	--> since a saved floor's key comes back as a string and indexing it by number would miss.
	DeskData.Unlock(Data, Next.Floor).Desks[Next.Slot]({})

	return true
end

function PurchaseHandlerService:Start()
	NetworkingServer.Purchases.BuyDesk.On(function(Player: Player): boolean
		return self:BuyDesk(Player)
	end)
end

return PurchaseHandlerService
