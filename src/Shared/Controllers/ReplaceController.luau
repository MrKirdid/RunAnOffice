--[[
	Everywhere the part in your hands could go.

	While something is held, every desk already wearing that same kind of component gets a readout
	of the one it is wearing and a prompt to trade it out, so the choice is made by comparing the
	two rather than by remembering what a desk had.

	What is held comes from replicated data rather than from whatever the client did last, so the
	previews only ever agree with what the server thinks is in hand. The server decides which of
	the three components a swap lands in, so this only has to say which desk.
]]

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

--> Matching what a held part's readout does, so the two cards being compared sit at the same
--> height above the thing they describe.
local CardDrop = 2

local ReplaceController = {
	Showing = {} :: { BasePart },
	--> Tracked separately from the cards because these hang off the desk's own parts. Only a desk
	--> that rebuilds takes its own away, and a swap rebuilds exactly one desk.
	Points = {} :: { Attachment },
}

--> The desk's own component, not the held one: the point of the card is to show what would be
--> lost. Sparkle off, because nothing here is a reward.
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

	--> An Attachment for the same reason the pickup prompt uses one: a stand-in part would widen
	--> the model's bounds and shove its card off the top of it.
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
		--> Off before the trip, so a second hold cannot ask twice while the first is in flight.
		--> The server would turn the second down anyway, this just stops it being asked.
		Prompt.Enabled = false

		NetworkingClient.Items.Replace.Invoke({ Floor = Floor, Slot = Slot })
			:andThen(function()
				--> The desk rebuilds itself off replicated data, and the empty hands that come
				--> back with it are what clear these previews
				CarryController:Clear()
			end)
			:catch(function(Problem)
				warn(`[Replace] {Problem}`)
				Prompt.Enabled = true
			end)
	end)
end

--> Rebuilt from scratch on every change rather than patched, because the things it is built from,
--> what is held and which desks wear it, both move.
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

			--> A desk can hold the data for a component whose model has not spawned yet
			if Variant and Model then
				self:_Offer(Model, tonumber(Floor), tonumber(Slot), Component, Variant)
			end
		end
	end
end

function ReplaceController:Start()
	--> Holding is the whole trigger: it fills when the server hands a part over and empties when
	--> the server takes it back, so both ends of a carry land here without being told twice.
	PlayerData.Holding.Changed(function()
		self:Refresh()
	end)

	--> Desks arriving, leaving or being rebuilt all change what there is to offer
	Players.LocalPlayer.CharacterAdded:Connect(function()
		self:Refresh()
	end)

	self:Refresh()
end

return ReplaceController
