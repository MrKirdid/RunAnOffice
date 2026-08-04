local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Assets = ReplicatedStorage:WaitForChild("Assets")

local PlotController = require(Shared.Controllers.PlotController)
local DeskPlacements = require(Shared.Configs.DeskPlacements)
local PlayerData = require(Shared.PlayerData).client

local DeskController = {
	Desks = {} :: { [number]: Model },
}

function DeskController:GetDeskID(Floor: number, Slot: number): string
	return tostring(Floor) .. "-" .. tostring(Slot)
end

function DeskController:NewDesk(Floor: number, Slot: number)
	local DeskID = self:GetDeskID(Floor, Slot)
	local DeskCFrame = select(2, PlotController:GetPlot(Players.LocalPlayer)).Floors[Floor].Slots[Slot].CFrame
	local Desk = Assets.Desk:Clone()

	Desk:PivotTo(DeskCFrame)
	Desk.Parent = workspace.Desks

	DeskController.Desks[DeskID] = Desk
end

-- Lowest floor/slot the player has unlocked but not put a desk in yet.
function DeskController:GetNextAvailableDesk(): (number?, number?)
	local Floors = {}

	for Floor in PlayerData.Floors() do
		table.insert(Floors, Floor)
	end

	table.sort(Floors)

	for _, Floor in Floors do
		local Taken = {}

		for Slot in PlayerData.Floors[Floor].Desks() do
			Taken[tonumber(Slot)] = true
		end

		for Slot = 1, #DeskPlacements.Base do
			if not Taken[Slot] then
				return Floor, Slot
			end
		end
	end

	return nil, nil
end

function DeskController:Start()
	local WatchFloor = function(Floor: number)
		local Desks = PlayerData.Floors[Floor].Desks

		for Slot in Desks() do
			self:NewDesk(Floor, Slot)
		end

		Desks.OnKeyAdded(function(Slot: number)
			self:NewDesk(Floor, Slot)
		end)
	end

	for Floor in PlayerData.Floors() do
		WatchFloor(Floor)
	end

	PlayerData.Floors.OnKeyAdded(function(Floor: number)
		WatchFloor(Floor)
	end)

	select(2, PlotController:GetPlot(Players.LocalPlayer)).Boards.BuyDesk.Main.BuyUI.BuyDesk.GoButton.Activated:Connect(
		function()
			local Floor, Slot = self:GetNextAvailableDesk()

			if not Floor or not Slot then
				return -- every unlocked floor is full
			end
		end
	)
end

return DeskController
