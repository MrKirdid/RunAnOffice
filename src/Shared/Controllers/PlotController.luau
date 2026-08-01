local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local TypedPromise = require(Shared.Packages.TypedPromise)
local networkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client

local PlotController = {
	Plots = {} :: { [Player]: number },
}

function PlotController:HandleRollPads()
	local _, Plot = self:GetPlot(Players.LocalPlayer)

	local function UpdatePads(Amount: number)
		for _, Pad: Model in Plot.Pads:GetChildren() do
			local PadIndex = tonumber(Pad.Name)
			if PadIndex <= Amount then
				for _, PadPart: BasePart in Pad:GetDescendants() do
					PadPart.Transparency = 0
				end
			else
				for _, PadPart: BasePart in Pad:GetDescendants() do
					PadPart.Transparency = 1
				end
			end
		end
	end

	UpdatePads(PlayerData.RerollPads())
	PlayerData.RerollPads:Changed(function(NewAmount: number)
		UpdatePads(NewAmount)
	end)
end

function PlotController:Init()
	self.Plots = networkingClient.Plot.GetPlots.Invoke():expect()
	networkingClient.Plot.UpdatePlots.On(function(newPlots)
		self.Plots = newPlots
	end)
	PlotController:HandleRollPads()
end

function PlotController:GetPlot(Player: Player): (number, Model)
	if not self.Plots[Player] then
		TypedPromise.new(function(resolve)
			repeat
				task.wait()
			until self.Plots[Player]
			resolve(self.Plots[Player])
		end):await()
	end

	return self.Plots[Player], workspace.PlotContainer:FindFirstChild(tostring(self.Plots[Player]))
end

return PlotController
