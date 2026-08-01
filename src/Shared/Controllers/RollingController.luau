local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local networkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)

local RollingService = {}

function RollingService:Roll()
	local Data = networkingClient.Roll.Invoke():expect()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	return Data
end

function RollingService:_roll_vizual()
	
end

function RollingService:Start()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	Plot.Buttons.Roll.Button.ProximityPrompt.Triggered:Connect(function()
		local Data = self:Roll()
		print(Data.Results[1])
	end)
end

return RollingService
