local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskController = require(Shared.Controllers.DeskController)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).client

--> The beam from the player's feet to the part on the first desk that the one in hand replaces.
--> Which of the three it is comes off what is being held; the desk itself if that cannot be told.
--> The server sees the swap land.

local ComponentsName = "Components"

--> How long the desk gets to be stood up on the client, and how often it is looked for.
local DeskWait = 10
local DeskPoll = 0.2

local function FindDesk(): Model?
	local Floors = DeskData.GetFloors(PlayerData)
	local Floor = Floors[1]
	local Slot = Floor and DeskData.GetSlots(PlayerData, Floor)[1]

	if not Floor or not Slot then
		return nil
	end

	return DeskController.Desks[DeskController:GetDeskID(Floor, Slot)]
end

--> The model standing on the desk for the component in hand, if the desk has built it.
local function FindSlot(Desk: Model): PVInstance?
	local Held = PlayerData.Holding()
	local Component = Held and Held.Component
	local Built = Desk:FindFirstChild(ComponentsName)
	local Model = Built and Component and Built:FindFirstChild(Component)

	return if Model and Model:IsA("Model") then Model else nil
end

local Stage = {
	Looking = false,
}

function Stage.Start(Tutorial: any)
	Stage.Looking = true

	local Desk = FindDesk()
	local Waited = 0

	while not Desk and Stage.Looking and Waited < DeskWait do
		Waited += task.wait(DeskPoll)
		Desk = FindDesk()
	end

	if not Stage.Looking then
		return
	end

	Stage.Looking = false

	if not Desk then
		warn("[Tutorial] there is no desk standing to point at")
		return
	end

	local Target = FindSlot(Desk) or Desk
	local Anchor = if Target:IsA("BasePart") then Target else Target:FindFirstChildWhichIsA("BasePart", true)

	if not Anchor then
		return
	end

	Tutorial.Follow:Start(Anchor)
end

function Stage.Cleanup(Tutorial: any)
	Stage.Looking = false

	Tutorial.Follow:Stop()
end

return Stage
