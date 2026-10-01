local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local TypedPromise = require(Shared.Packages.TypedPromise)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client

local PadsAttribute = "RollPads"

local PlotController = {
	Plots = {} :: { [Player]: number },
	Queued = false,
}

--> How many pads a plot's owner has: the save for this player, the attribute PlotService
--> publishes for everyone else, and one, a fresh save's count, until it arrives.
local function PadsFor(Player: Player): number
	if Player == Players.LocalPlayer then
		return PlayerData.RerollPads()
	end

	local Amount = Player:GetAttribute(PadsAttribute)

	return if type(Amount) == "number" then Amount else 1
end

--> Shows each plot's bought pads and hides the rest, on every plot and not only this player's.
function PlotController:RefreshPads()
	local Container = workspace:FindFirstChild("PlotContainer")

	if not Container then
		return
	end

	for Player, Index in self.Plots do
		local Plot = Container:FindFirstChild(tostring(Index))
		local Pads = Plot and Plot:FindFirstChild("Pads")

		if not Pads then
			continue
		end

		local Amount = PadsFor(Player)

		for _, Pad in Pads:GetChildren() do
			local Transparency = if (tonumber(Pad.Name) or math.huge) <= Amount then 0 else 1

			for _, Part in Pad:GetDescendants() do
				if Part:IsA("BasePart") then
					Part.Transparency = Transparency
				end
			end
		end
	end
end

function PlotController:_WatchPads(Player: Player)
	Player:GetAttributeChangedSignal(PadsAttribute):Connect(function()
		self:RefreshPads()
	end)
end

function PlotController:Init()
	self.Plots = NetworkingClient.Plot.GetPlots.Invoke():expect()
	NetworkingClient.Plot.UpdatePlots.On(function(NewPlots)
		self.Plots = NewPlots
		self:RefreshPads()
	end)

	--> Changed is a field, not a method: a colon here drops the callback.
	PlayerData.RerollPads.Changed(function()
		self:RefreshPads()
	end)

	for _, Player in Players:GetPlayers() do
		self:_WatchPads(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:_WatchPads(Player)
	end)

	--> the place streams, so a far plot's pads can arrive long after its owner's count did
	workspace:WaitForChild("PlotContainer").DescendantAdded:Connect(function(Added: Instance)
		if self.Queued or not Added:IsA("BasePart") or not Added:FindFirstAncestor("Pads") then
			return
		end

		--> a plot streams in a part at a time, so the parts landing together share one refresh
		self.Queued = true

		task.defer(function()
			self.Queued = false
			self:RefreshPads()
		end)
	end)

	self:RefreshPads()
end

function PlotController:GetPlot(Player: Player): (number, Model)
	if not self.Plots[Player] then
		TypedPromise.new(function(Resolve)
			repeat
				task.wait()
			until self.Plots[Player]
			Resolve(self.Plots[Player])
		end):await()
	end

	return self.Plots[Player], workspace.PlotContainer:FindFirstChild(tostring(self.Plots[Player]))
end

return PlotController
