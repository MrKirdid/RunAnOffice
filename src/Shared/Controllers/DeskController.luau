local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Assets = ReplicatedStorage:WaitForChild("Assets")

local NetworkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local RollingController = require(Shared.Controllers.RollingController)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local DeskData = require(Shared.Utilities.DeskData)
local Signal = require(Shared.Packages.Fastsignal)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local Parts = require(Assets.Parts)

local DeskController = {
	Desks = {} :: { [string]: Model },

	ComponentsChanged = Signal.new(),
}

function DeskController:GetDeskID(Floor: number, Slot: number): string
	return tostring(Floor) .. "-" .. tostring(Slot)
end

local Spinning: { [string]: boolean } = {}

function DeskController:SpawnComponents(Floor: number, Slot: number)
	local DeskID = self:GetDeskID(Floor, Slot)
	local Desk = self.Desks[DeskID]
	local Components = PlayerData.Floors[Floor].Desks[Slot]()

	if not Desk or not Components or Spinning[DeskID] then
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

			Model:PivotTo(Pivot * Offset)
			Model.Parent = Container
		end
	end

	self.ComponentsChanged:Fire(Floor, Slot)
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

	if Roll then
		local Components = PlayerData.Floors[Floor].Desks[Slot]()

		if Components then
			Spinning[DeskID] = true

			local Ok, Problem = pcall(function()
				RollingController:RollDesk(Desk, Components):Destroy()
			end)

			Spinning[DeskID] = nil

			if not Ok then
				warn(`[Desk] roll failed: {Problem}`)
			end
		end
	end

	self:SpawnComponents(Floor, Slot)
end

function DeskController:RemoveDesk(Floor: number, Slot: number)
	local DeskID = self:GetDeskID(Floor, Slot)
	local Desk = self.Desks[DeskID]

	if Desk then
		Desk:Destroy()
		self.Desks[DeskID] = nil

		self.ComponentsChanged:Fire(Floor, Slot)
	end
end

function DeskController:GetNextAvailableDesk(): (number?, number?)
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	return DeskData.GetNextAvailable(PlayerData, Plot)
end

function DeskController:Start()
	local WatchDesk = function(Floor: number, Slot: number)
		PlayerData.Floors[Floor].Desks[Slot].Changed(function()
			self:SpawnComponents(Floor, Slot)
		end)
	end

	local WatchFloor = function(Floor: number)
		local Desks = PlayerData.Floors[Floor].Desks

		for Slot in Desks() do
			self:NewDesk(Floor, Slot)
			WatchDesk(Floor, Slot)
		end

		Desks.OnKeyAdded(function(Slot: number)
			WatchDesk(Floor, Slot)

			task.spawn(function()
				self:NewDesk(Floor, Slot, true)
			end)
		end)

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

	local Board = Plot:WaitForChild("Boards"):WaitForChild("BuyDesk")
	local BuyUI = Board:WaitForChild("Main"):WaitForChild("BuyUI")
	local GoButton = BuyUI:WaitForChild("BuyDesk"):WaitForChild("GoButton")

	GoButton.Activated:Connect(function()
		local Floor, Slot = self:GetNextAvailableDesk()

		if not Floor or not Slot then
			return
		end

		NetworkingClient.Purchases.BuyDesk.Fire()
	end)
end

return DeskController
