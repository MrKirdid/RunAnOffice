local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Assets = ReplicatedStorage.Assets

local PlotTemplate = Assets.Templates.PlotTemplate

local NetworkingServer = require(Shared.Networking.networkingServer)
local GameConfigs = require(Shared.Configs.GameConfigs)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).server
local PlotContainer = require(workspace.PlotContainer)

--> Published on the Player rather than sent over the wire. Attributes replicate to everyone on
--> their own, which is what lets a client hide the floors somebody else has not bought yet.
local FloorsAttribute = "UnlockedFloors"

local PlotService = { Plots = {} :: { [Player]: number } }

--> A list rather than a count, because a command can unlock floor 3 without floor 2 and a count
--> would quietly hand the player the gap as well.
--> Data is looked up here rather than passed in. Holding the table handed over at join means
--> reading a snapshot that stops moving, so the attribute freezes on whatever floors the player
--> owned the moment they joined.
local function PublishFloors(Player: Player)
	local Data = PlayerData[Player]

	if not Data then
		return
	end

	local Text = {}

	for _, Floor in DeskData.GetFloors(Data) do
		table.insert(Text, tostring(Floor))
	end

	local Value = table.concat(Text, ",")

	--> Changed fires for anything under Floors, a desk being built included, so most calls here have
	--> nothing new to say. Writing the attribute anyway would replicate the same string to everyone
	--> every time somebody bought a desk.
	if Player:GetAttribute(FloorsAttribute) ~= Value then
		Player:SetAttribute(FloorsAttribute, Value)
	end
end

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

		--> Spawned because the data is not loaded yet at join, and the plot itself must not wait
		--> on it: the player is standing on the plot either way.
		task.spawn(function()
			local Data = PlayerData.Service:waitForData(Player)

			PublishFloors(Player)

			--> Bound to the root, which fires for anything underneath it, and re-reads the data
			--> every time rather than trusting the value it was handed.
			Data.Changed(function()
				PublishFloors(Player)
			end)
		end)

		self:TeleportPlayerToPlot(Player)

		Player.CharacterAdded:Connect(function()
			self:TeleportPlayerToPlot(Player)
		end)
	end

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
