local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Assets = ReplicatedStorage.Assets

-- Assets
local PlotTemplate = Assets.Templates.PlotTemplate

-- Dependencies
local NetworkingServer = require(Shared.Networking.networkingServer)
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

function PlotService:GetPlot(Player: Player): Model?
	local PlotIndex = self.Plots[Player]

	return PlotIndex and workspace.PlotContainer:FindFirstChild(tostring(PlotIndex))
end

function PlotService:TeleportPlayerToPlot(Player: Player)
	local Character = Player.Character or Player.CharacterAdded:Wait()

	local Plot = self:GetPlot(Player)

	if Plot then
		local Pos = Plot.Positions.SpawnPosition.Position
		Character:PivotTo(CFrame.new(Pos + Vector3.new(0, 5, 0)))
	end
end

function PlotService:Init()
	NetworkingServer.Plot.GetPlots.On(function()
		local Plots = self.Plots
		return Plots
	end)

	local function HandlePlayer(Player: Player)
		self:NewPlot(Player)
		NetworkingServer.Plot.UpdatePlots.FireAll(self.Plots)

		self:TeleportPlayerToPlot(Player)

		Player.CharacterAdded:Connect(function()
			self:TeleportPlayerToPlot(Player)
		end)
	end

	--> Players already in the list before this connects would never get a plot, which is
	--> the normal case in a Studio playtest and happens to the first joiner on a live server.
	for _, Player in Players:GetPlayers() do
		task.spawn(HandlePlayer, Player)
	end

	Players.PlayerAdded:Connect(HandlePlayer)

	Players.PlayerRemoving:Connect(function(Player)
		self.Plots[Player] = nil
		NetworkingServer.Plot.UpdatePlots.FireAll(self.Plots)
	end)
end

return PlotService
