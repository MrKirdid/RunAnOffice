local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotController = require(Shared.Controllers.PlotController)

--> The beam from the player's feet to the lock button by the door. The server marks the save the
--> first time the base is locked.

local ButtonName = "LockBase"
local ButtonWait = 15

local function FindButton(): BasePart?
	local _, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local Deadline = os.clock() + ButtonWait

	while os.clock() < Deadline do
		local Button = Plot:FindFirstChild(ButtonName, true)

		if Button and Button:IsA("BasePart") then
			return Button
		end

		task.wait(0.25)
	end

	return nil
end

local Stage = {
	Connections = {} :: { RBXScriptConnection },
}

function Stage.Start(Tutorial: any)
	local Button = FindButton()

	if not Button then
		warn("[Tutorial] the plot has no lock button to point at")
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
