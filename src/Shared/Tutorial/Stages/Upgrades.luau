local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local UIController = require(Shared.Controllers.UIController)
local UpgradeRules = require(Shared.Utilities.UpgradeRules)
local UpgradeTreeController = require(Shared.Controllers.UpgradeTreeController)
local Upgrades = require(Shared.Configs.Upgrades)

--> The arrow on the screen over the Upgrades button on the hud, and once the tree is open over the
--> first node that can be bought. The server sees the upgrade land in the save, and waives its price while
--> the save is on this step.

local HudName = "HudGUI"
local ButtonPath = "Root.MenuBar.UpgradesButton"
local ScreenName = "Upgrades"

--> how long the tree gets to lay itself out after opening before a node is pointed at
local LayoutDelay = 0.35

local function Resolve(Root: Instance, Path: string): Instance?
	local Current: Instance? = Root

	for _, Step in string.split(Path, ".") do
		if not Current then
			return nil
		end

		Current = (Current :: Instance):FindFirstChild(Step)
	end

	return Current
end

--> One is the hud being cloned again, the others UIController saying a screen opened or shut.
--> Those are Fastsignal connections, which are not RBXScriptConnections but disconnect like one.
type Connection = RBXScriptConnection | { Disconnect: (self: any) -> () }

local Stage = {
	Connections = {} :: { Connection },
}

--> The first node the rules would let the player buy, cheapest first, so the pointer lands on
--> the node the free purchase is meant for.
local function FindBuyable(): string?
	local Best: string? = nil
	local BestCost = math.huge

	for Id, Config in Upgrades.List do
		if Config.IsAction or UpgradeTreeController:IsOwned(Id) then
			continue
		end

		if not UpgradeRules.IsAvailable(UpgradeTreeController.Owned, Id) then
			continue
		end

		local Cost = UpgradeRules.GetCost(Id)

		if Cost < BestCost then
			Best = Id
			BestCost = Cost
		end
	end

	return Best
end

--> Puts the pointers on whichever copy of the hud is up. Nothing to point at is left alone rather
--> than warned about: the hud is cloned again every respawn and this is run again for each one.
local function PointAtButton(Tutorial: any, Hud: Instance)
	local Button = Resolve(Hud, ButtonPath)

	if not Button or not Button:IsA("GuiObject") then
		return
	end

	Tutorial.Arrow:Point(Button)
end

local function PointAtNode(Tutorial: any)
	local Id = FindBuyable()
	local Node = Id and UpgradeTreeController:GetNode(Id)
	local Button = Node and Node:getInstance()

	if not Button then
		return
	end

	Tutorial.Arrow:Point(Button)
end

function Stage.Start(Tutorial: any)
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local Hud = PlayerGui:FindFirstChild(HudName)

	if UIController:IsOpen(ScreenName) then
		PointAtNode(Tutorial)
	elseif Hud then
		PointAtButton(Tutorial, Hud)
	else
		warn("[Tutorial] there is no hud to point at")
	end

	table.insert(
		Stage.Connections,
		PlayerGui.ChildAdded:Connect(function(Child: Instance)
			if Child.Name == HudName and not UIController:IsOpen(ScreenName) then
				PointAtButton(Tutorial, Child)
			end
		end)
	)

	table.insert(
		Stage.Connections,
		UIController.Opened:Connect(function(Name: string)
			if Name ~= ScreenName then
				return
			end

			task.delay(LayoutDelay, function()
				if UIController:IsOpen(ScreenName) then
					PointAtNode(Tutorial)
				end
			end)
		end)
	)

	table.insert(
		Stage.Connections,
		UIController.Closed:Connect(function(Name: string)
			local Current = PlayerGui:FindFirstChild(HudName)

			if Name == ScreenName and Current then
				PointAtButton(Tutorial, Current)
			end
		end)
	)
end

function Stage.Cleanup(Tutorial: any)
	for _, Connection in Stage.Connections do
		Connection:Disconnect()
	end

	table.clear(Stage.Connections)

	Tutorial.Arrow:Stop()
end

return Stage
