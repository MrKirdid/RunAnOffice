local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GearShopController = require(Shared.Controllers.GearShopController)
local PlotController = require(Shared.Controllers.PlotController)
local TutorialConfigs = require(Shared.Configs.Tutorial)
local UIController = require(Shared.Controllers.UIController)

--> The beam from the player's feet to the gear shop on their own plot, and once the shop is open
--> the arrow over the free gear's button. The shop opens on its own when walked up to. The server
--> waives the price while the save is on this step and puts the gear straight in the backpack.

local ShopPath = { "Fcts", "Shop" }
local ScreenName = "GearShop"
local ShopWait = 15

--> how long the shop gets to pop in after opening before its row is pointed at
local LayoutDelay = 0.35

--> One is the character coming back, the others UIController saying a screen opened or shut.
--> Those are Fastsignal connections, which are not RBXScriptConnections but disconnect like one.
type Connection = RBXScriptConnection | { Disconnect: (self: any) -> () }

--> The shop on the player's plot, as a part the beam can end in: the model's primary part, or
--> any part in it.
local function FindShop(): BasePart?
	local Deadline = os.clock() + ShopWait

	while os.clock() < Deadline do
		--> looked up again each pass: the plot model can land after the number it is filed under
		local _, Plot = PlotController:GetPlot(Players.LocalPlayer)
		local Current: Instance? = Plot

		for _, Step in ShopPath do
			Current = Current and Current:FindFirstChild(Step)
		end

		if Current and Current:IsA("BasePart") then
			return Current
		end

		if Current and Current:IsA("Model") then
			local Part = Current.PrimaryPart or Current:FindFirstChildWhichIsA("BasePart", true)

			if Part then
				return Part
			end
		end

		task.wait(0.25)
	end

	return nil
end

local Stage = {
	Connections = {} :: { Connection },

	--> off once the step is over, so a pointer waiting on the shop to pop in does not land after it
	Active = false,
}

--> Measured once the screen has finished popping in, or the arrow lands where the row was mid-pop.
local function PointAtRow(Tutorial: any)
	Tutorial.Follow:Stop()

	task.delay(LayoutDelay, function()
		local Row = GearShopController.Rows[TutorialConfigs.FreeGear]

		if not Stage.Active or not Row or not UIController:IsOpen(ScreenName) then
			return
		end

		Tutorial.Arrow:Point(Row.Art)
	end)
end

function Stage.Start(Tutorial: any)
	Stage.Active = true

	local Shop = FindShop()

	--> the wait for the shop can outlast the step: a bat taken in the meantime ends it
	if not Stage.Active then
		return
	end

	if not Shop then
		warn("[Tutorial] the plot has no gear shop to point at")
		return
	end

	local function PointAtShop()
		Tutorial.Arrow:Stop()
		Tutorial.Follow:Start(Shop)
	end

	if UIController:IsOpen(ScreenName) then
		PointAtRow(Tutorial)
	else
		PointAtShop()
	end

	table.insert(
		Stage.Connections,
		UIController.Opened:Connect(function(Name: string)
			if Name == ScreenName then
				PointAtRow(Tutorial)
			end
		end)
	)

	table.insert(
		Stage.Connections,
		UIController.Closed:Connect(function(Name: string)
			if Name == ScreenName then
				PointAtShop()
			end
		end)
	)

	--> a respawn takes the beam's near end with the old character, so it is run again to the new one
	table.insert(
		Stage.Connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			if not UIController:IsOpen(ScreenName) then
				PointAtShop()
			end
		end)
	)
end

function Stage.Cleanup(Tutorial: any)
	Stage.Active = false

	for _, Connection in Stage.Connections do
		Connection:Disconnect()
	end

	table.clear(Stage.Connections)

	Tutorial.Arrow:Stop()
	Tutorial.Follow:Stop()
end

return Stage
