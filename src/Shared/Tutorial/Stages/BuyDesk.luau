local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotController = require(Shared.Controllers.PlotController)

--> The beam from the player's feet to the buy board. The server sees the desk stand.

local BoardPath = { "Boards", "BuyDesk", "Main" }
local BoardWait = 15

--> The board is on the plot the player is stood on, so it is found rather than remembered.
local function FindBoard(): BasePart?
	local _, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local Current: Instance = Plot

	for _, Step in BoardPath do
		local Next = Current:WaitForChild(Step, BoardWait)

		if not Next then
			return nil
		end

		Current = Next
	end

	return if Current:IsA("BasePart") then Current else nil
end

local Stage = {
	Connections = {} :: { RBXScriptConnection },
}

function Stage.Start(Tutorial: any)
	local Board = FindBoard()

	if not Board then
		warn("[Tutorial] the plot has no buy board to point at")
		return
	end

	Tutorial.Follow:Start(Board)

	--> a respawn takes the beam's near end with the old character, so it is run again to the new one
	table.insert(
		Stage.Connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			Tutorial.Follow:Start(Board)
		end)
	)
end

function Stage.Cleanup(Tutorial: any)
	for _, Connection in Stage.Connections do
		Connection:Disconnect()
	end

	table.clear(Stage.Connections)

	Tutorial.Follow:Stop()
end

return Stage
