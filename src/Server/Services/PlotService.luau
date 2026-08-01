local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Assets = ReplicatedStorage.Assets

-- Assets
local PlotTemplate = Assets.Templates.PlotTemplate

-- Dependencies
local networkingServer = require(Shared.Networking.networkingServer)
local GameConfigs = require(Shared.Configs.GameConfigs)
local PlotContainer = require(workspace.PlotContainer)

-- Service
local PlotService = { Plots = {} :: { [Player]: number } }

function PlotService:NewPlot(Player: Player)
	local Taken = {}
	for _, Plot in self.Plots do
		Taken[Plot] = true
	end

	for Index = 1, GameConfigs.PlotAmount do
		if not Taken[Index] then
			self.Plots[Player] = Index
			break
		end
	end

	local PlotIndex = self.Plots[Player]
	local PlotLocation = PlotContainer[PlotIndex]

	local Plot = PlotTemplate:Clone()
	Plot.Parent = workspace.PlotContainer
	Plot.Name = PlotIndex

	Plot:PivotTo(PlotLocation)

	return Plot
end

function PlotService:TeleportPlayerToPlot(Player: Player)
	local Character = Player.Character or Player.CharacterAdded:Wait()

	local PlotIndex = self.Plots[Player]
	local Plot = workspace.PlotContainer:FindFirstChild(tostring(PlotIndex))

	if Plot then
		local Pos = Plot.Positions.SpawnPosition.Position
		Character:PivotTo(CFrame.new(Pos + Vector3.new(0, 5, 0)))
	end
end

function PlotService:Init()
	networkingServer.Plot.GetPlots.On(function()
		local Plots = self.Plots
		return Plots
	end)

	Players.PlayerAdded:Connect(function(player)
		self:NewPlot(player)
		networkingServer.Plot.UpdatePlots.FireAll(self.Plots)

		self:TeleportPlayerToPlot(player)

		player.CharacterAdded:Connect(function()
			self:TeleportPlayerToPlot(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.Plots[player] = nil
		networkingServer.Plot.UpdatePlots.FireAll(self.Plots)
	end)
end

return PlotService
