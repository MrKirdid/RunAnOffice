local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Assets = ReplicatedStorage:WaitForChild("Assets")

local NetworkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local RollingController = require(Shared.Controllers.RollingController)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local DeskData = require(Shared.Utilities.DeskData)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local Parts = require(Assets.Parts)

local DeskController = {
	Desks = {} :: { [string]: Model },
}

function DeskController:GetDeskID(Floor: number, Slot: number): string
	return tostring(Floor) .. "-" .. tostring(Slot)
end

--> Parts the desk already owns, rebuilt from scratch so a reroll can just call this again.
function DeskController:SpawnComponents(Floor: number, Slot: number)
	local Desk = self.Desks[self:GetDeskID(Floor, Slot)]
	local Components = PlayerData.Floors[Floor].Desks[Slot]()

	if not Desk or not Components then
		return
	end

	local Existing = Desk:FindFirstChild("Components")

	if Existing then
		Existing:Destroy()
	end

	local Container = Instance.new("Folder")
	Container.Name = "Components"
	Container.Parent = Desk

	local Pivot = Desk:GetPivot()

	for Component, Offset in Offsets.Desk do
		local Variant = Components[Component]

		if Variant then
			local Model: Model = Parts(Component, Variant)

			--> Placed on the model's own pivot, matching the roll visual so the swap is seamless
			Model:PivotTo(Pivot * Offset)
			Model.Parent = Container
		end
	end
end

function DeskController:NewDesk(Floor: number, Slot: number, Roll: boolean?)
	local DeskID = self:GetDeskID(Floor, Slot)
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local DeskCFrame = DeskPlacements.GetCFrame(Plot, Floor, Slot)

	if not DeskCFrame then
		return
	end

	local Desk = Assets.Desk:Clone()

	Desk:PivotTo(DeskCFrame)
	Desk.Parent = workspace.Desks

	DeskController.Desks[DeskID] = Desk

	--> A freshly bought desk rolls its parts in, an existing one just has them already
	if Roll then
		local Components = PlayerData.Floors[Floor].Desks[Slot]()

		if Components then
			RollingController:RollDesk(Desk, Components):Destroy()
		end
	end

	self:SpawnComponents(Floor, Slot)
end

--> The slot's data is gone by the time this runs, so it only has the model to clean up.
function DeskController:RemoveDesk(Floor: number, Slot: number)
	local DeskID = self:GetDeskID(Floor, Slot)
	local Desk = self.Desks[DeskID]

	if Desk then
		Desk:Destroy()
		self.Desks[DeskID] = nil
	end
end

-- Lowest floor/slot the player has unlocked but not put a desk in yet.
function DeskController:GetNextAvailableDesk(): (number?, number?)
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	return DeskData.GetNextAvailable(PlayerData, Plot)
end

function DeskController:Start()
	local WatchFloor = function(Floor: number)
		local Desks = PlayerData.Floors[Floor].Desks

		for Slot in Desks() do
			self:NewDesk(Floor, Slot)
		end

		--> Spawned mid session means it was just bought, so roll it in. Spawned in the
		--> loop above means the player already owned it, so it appears fully built.
		Desks.OnKeyAdded(function(Slot: number)
			task.spawn(function()
				self:NewDesk(Floor, Slot, true)
			end)
		end)

		--> Only admin tooling clears a slot today, but the model has to go with the data
		--> either way or the plot keeps showing a desk nobody owns.
		Desks.OnKeyRemoved(function(Slot: number)
			self:RemoveDesk(Floor, Slot)
		end)
	end

	for Floor in PlayerData.Floors() do
		WatchFloor(Floor)
	end

	PlayerData.Floors.OnKeyAdded(function(Floor: number)
		WatchFloor(Floor)
	end)

	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	--> The plot model replicates before its descendants do, so a plain index here races
	local Board = Plot:WaitForChild("Boards"):WaitForChild("BuyDesk")
	local BuyUI = Board:WaitForChild("Main"):WaitForChild("BuyUI")
	local GoButton = BuyUI:WaitForChild("BuyDesk"):WaitForChild("GoButton")

	GoButton.Activated:Connect(function()
		local Floor, Slot = self:GetNextAvailableDesk()

		if not Floor or not Slot then
			return -- every unlocked floor is full
		end

		--> The server picks the slot again and owns the roll, this is just the ask
		NetworkingClient.Purchases.BuyDesk.Fire()
	end)
end

return DeskController
