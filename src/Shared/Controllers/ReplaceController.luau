local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CarryController = require(Shared.Controllers.CarryController)
local DeskController = require(Shared.Controllers.DeskController)
local DeskData = require(Shared.Utilities.DeskData)
local ItemDisplayController = require(Shared.Controllers.ItemDisplayController)
local Items = require(Shared.Utilities.Items)
local NetworkingClient = require(Shared.Networking.networkingClient)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local SoundController = require(Shared.Controllers.SoundController)

--> Three words for the same prompt: a slot with a part on it is swapped, a slot emptied by a
--> theft is filled, and an employee is sat at a desk with nobody at it. The server does the
--> same thing every way.
local ReplaceText = "Replace"
local PlaceText = "Place"
local SeatText = "Seat"
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

--> The prompt itself, hung off a point somewhere on the desk. Where the point is and what the
--> prompt says are the caller's; what a hold does is the same everywhere.
function ReplaceController:_Prompt(Host: BasePart, Where: CFrame, Text: string, Floor: number, Slot: number)
	local Point = Instance.new("Attachment")
	Point.Name = "ReplacePoint"
	Point.Parent = Host
	Point.WorldCFrame = Where

	table.insert(self.Points, Point)

	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Name = "Replace"
	Prompt.ActionText = Text
	Prompt.HoldDuration = PromptHold
	Prompt.MaxActivationDistance = PromptDistance
	Prompt.RequiresLineOfSight = false
	Prompt.Parent = Point

	Prompt.Triggered:Connect(function()
		Prompt.Enabled = false

		local Held = PlayerData.Holding()

		--> only a part gets the card over where it landed; an employee sits down and is their
		--> own announcement
		self.Placed = if Items.IsPart(Held)
			then { Floor = Floor, Slot = Slot, Component = Held.Component, Variant = Held.Variant }
			else nil

		NetworkingClient.Items.Replace
			.Invoke({ Floor = Floor, Slot = Slot })
			:andThen(function(Placed: boolean)
				if not Placed then
					SoundController:Play("Error")

					self.Placed = nil
					Prompt.Enabled = true

					return
				end

				SoundController:Play("Lock")

				CarryController:Clear()
			end)
			:catch(function(Problem)
				warn(`[Replace] {Problem}`)

				SoundController:Play("Error")

				self.Placed = nil
				Prompt.Enabled = true
			end)
	end)
end

--> A slot with a part standing on it: the card over the part says what is being swapped out.
function ReplaceController:_Offer(Model: Model, Floor: number, Slot: number, Component: string, Variant: string)
	local Host = Model:FindFirstChildWhichIsA("BasePart", true)

	if not Host then
		return
	end

	table.insert(self.Showing, Preview(Model, Component, Variant))

	self:_Prompt(Host, Model:GetPivot(), ReplaceText, Floor, Slot)
end

--> A slot with nothing on it, emptied by a theft. There is no part to hang anything off, so the
--> prompt stands where the part would, off the desk itself.
function ReplaceController:_OfferEmpty(Desk: Model, Floor: number, Slot: number, Component: string)
	local Host = Desk:FindFirstChildWhichIsA("BasePart", true)
	local Offset = Offsets.Desk[Component]

	if not Host or not Offset then
		return
	end

	self:_Prompt(Host, Desk:GetPivot() * Offset, PlaceText, Floor, Slot)
end

--> A desk with nobody sat at it, for the employee in the arms. The prompt stands on the chair.
function ReplaceController:_OfferSeat(Desk: Model, Floor: number, Slot: number)
	local Host = Desk:FindFirstChildWhichIsA("BasePart", true)

	if not Host then
		return
	end

	self:_Prompt(Host, Desk:GetPivot() * Offsets.EmployeeDeskOffset, SeatText, Floor, Slot)
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

--> A stolen part is offered nowhere until it is secured: every desk here is in the thief's own
--> base, and the server has to have seen them in it before the part is theirs to place. An
--> employee is offered every empty chair and no full one: nobody comes off a desk for them.
function ReplaceController:Refresh()
	self:Clear()

	local Held = PlayerData.Holding()

	if not Items.IsHeld(Held) or Held.StolenFrom ~= nil then
		return
	end

	local Employee = Items.IsEmployee(Held)
	local Component = Held.Component

	for Floor in PlayerData.Floors() do
		local Desks = PlayerData.Floors[Floor].Desks

		for Slot in Desks() do
			local Components = Desks[Slot]()
			local Desk = DeskController.Desks[DeskController:GetDeskID(tonumber(Floor), tonumber(Slot))]

			if Employee then
				if Desk and type(Components) == "table" and Components.Employee == nil then
					self:_OfferSeat(Desk, tonumber(Floor), tonumber(Slot))
				end

				continue
			end

			local Variant = Components and Components[Component]
			local Built = Desk and Desk:FindFirstChild("Components")
			local Model = Built and Built:FindFirstChild(Component)

			if DeskData.IsPart(Variant) and Model then
				self:_Offer(Model :: Model, tonumber(Floor), tonumber(Slot), Component, Variant)
			elseif Variant == DeskData.Empty and Desk then
				self:_OfferEmpty(Desk, tonumber(Floor), tonumber(Slot), Component)
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
