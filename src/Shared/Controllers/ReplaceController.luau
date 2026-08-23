local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ItemDisplayController = require(Shared.Controllers.ItemDisplayController)
local CarryController = require(Shared.Controllers.CarryController)
local DeskController = require(Shared.Controllers.DeskController)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client

local PromptText = "Replace"
local PromptHold = 1
local PromptDistance = 10

local CardDrop = 2
local PlacedTime = 2.5

local ReplaceController = {
	Showing = {} :: { BasePart },
	Points = {} :: { Attachment },

	Placed = nil :: { Floor: number, Slot: number, Component: string, Variant: string }?,
}

local function Preview(Model: Model, Component: string, Variant: string): BasePart
	return ItemDisplayController:Show(Model, Component, Variant, {
		Glow = false,
		Drop = CardDrop,
		OnTop = true,
	})
end

function ReplaceController:Clear()
	for _, Card in self.Showing do
		ItemDisplayController:Dismiss(Card)
	end

	for _, Point in self.Points do
		Point:Destroy()
	end

	self.Showing = {}
	self.Points = {}
end

function ReplaceController:_Offer(Model: Model, Floor: number, Slot: number, Component: string, Variant: string)
	local Host = Model:FindFirstChildWhichIsA("BasePart", true)

	if not Host then
		return
	end

	table.insert(self.Showing, Preview(Model, Component, Variant))

	local Point = Instance.new("Attachment")
	Point.Name = "ReplacePoint"
	Point.Parent = Host
	Point.WorldCFrame = Model:GetPivot()

	table.insert(self.Points, Point)

	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Name = "Replace"
	Prompt.ActionText = PromptText
	Prompt.HoldDuration = PromptHold
	Prompt.MaxActivationDistance = PromptDistance
	Prompt.RequiresLineOfSight = false
	Prompt.Parent = Point

	Prompt.Triggered:Connect(function()
		Prompt.Enabled = false

		local Held = PlayerData.Holding()
		local Holding = Held and Held.Component
		local Quality = Held and Held.Variant

		self.Placed = if Holding and Quality
			then { Floor = Floor, Slot = Slot, Component = Holding, Variant = Quality }
			else nil

		NetworkingClient.Items.Replace.Invoke({ Floor = Floor, Slot = Slot })
			:andThen(function()
				CarryController:Clear()
			end)
			:catch(function(Problem)
				warn(`[Replace] {Problem}`)

				self.Placed = nil
				Prompt.Enabled = true
			end)
	end)
end

function ReplaceController:_ShowPlaced(Floor: number, Slot: number)
	local Placed = self.Placed

	if not Placed or tostring(Placed.Floor) ~= tostring(Floor) or tostring(Placed.Slot) ~= tostring(Slot) then
		return
	end

	self.Placed = nil

	local Desk = DeskController.Desks[DeskController:GetDeskID(tonumber(Floor) :: number, tonumber(Slot) :: number)]
	local Built = Desk and Desk:FindFirstChild("Components")
	local Model = Built and Built:FindFirstChild(Placed.Component)

	if not Model then
		return
	end

	ItemDisplayController:Show(Model :: Model, Placed.Component, Placed.Variant, {
		Duration = PlacedTime,
		Drop = CardDrop,
		OnTop = true,
	})
end

function ReplaceController:Refresh()
	self:Clear()

	local Held = PlayerData.Holding()
	local Component = Held and Held.Component

	if not Component then
		return
	end

	for Floor in PlayerData.Floors() do
		local Desks = PlayerData.Floors[Floor].Desks

		for Slot in Desks() do
			local Components = Desks[Slot]()
			local Variant = Components and Components[Component]
			local Desk = DeskController.Desks[DeskController:GetDeskID(tonumber(Floor), tonumber(Slot))]
			local Built = Desk and Desk:FindFirstChild("Components")
			local Model = Built and Built:FindFirstChild(Component)

			if Variant and Model then
				self:_Offer(Model, tonumber(Floor), tonumber(Slot), Component, Variant)
			end
		end
	end
end

function ReplaceController:Start()
	PlayerData.Holding.Changed(function()
		self:Refresh()
	end)

	DeskController.ComponentsChanged:Connect(function(Floor: number, Slot: number)
		self:_ShowPlaced(Floor, Slot)
		self:Refresh()
	end)

	Players.LocalPlayer.CharacterAdded:Connect(function()
		self:Refresh()
	end)

	self:Refresh()
end

return ReplaceController
