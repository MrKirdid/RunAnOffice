local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotController = require(Shared.Controllers.PlotController)

--> The beam from the player's feet to the roll button. The server rigs the roll itself and marks
--> the save when it has.

local ButtonPath = { "Buttons", "Roll", "Button" }
local ButtonWait = 15

local function FindButton(): BasePart?
	local _, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local Current: Instance = Plot

	for _, Step in ButtonPath do
		local Next = Current:WaitForChild(Step, ButtonWait)

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
	local Button = FindButton()

	if not Button then
		warn("[Tutorial] the plot has no roll button to point at")
		return
	end

	Tutorial.Follow:Start(Button)

	--> a respawn takes the beam's near end with the old character, so it is run again to the new one
	table.insert(
		Stage.Connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			Tutorial.Follow:Start(Button)
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
