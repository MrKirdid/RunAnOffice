local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)
local PlotService = require(script.Parent.PlotService)

local PurchaseHandlerService = {}

function PurchaseHandlerService:GetNextAvailableDesk(Player: Player): (number?, number?)
	local Plot = PlotService:GetPlot(Player)

	if not Plot then
		return nil, nil
	end

	return DeskData.GetNextAvailable(PlayerData[Player], Plot)
end

function PurchaseHandlerService:Start()
	NetworkingServer.Purchases.BuyDesk.On(function(Player: Player)
		local Floor, Slot = self:GetNextAvailableDesk(Player)
		if not Floor or not Slot then
			warn("No available desk for player", Player.Name)
			return
		end

		local Data = PlayerData[Player]

		Data.Floors[Floor].Desks[Slot](Rolling.RollDesk(Data.Luck()))
	end)
end

return PurchaseHandlerService
