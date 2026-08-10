local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local ItemDisplayController = require(Shared.Controllers.ItemDisplayController)
local CarryController = require(Shared.Controllers.CarryController)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local Signal = require(Shared.Packages.Fastsignal)
local Rolling = require(Shared.Utilities.Rolling)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local Parts = require(Assets.Parts)

local SFX = Assets.SFX.Rolling
local ConfettiVFX = Assets.VFX.ConfettiVFX

--> A desk swaps its rolled parts for permanent ones the moment the roll ends, so its cards
--> have to time out on their own. A pad keeps what it rolled, so its cards stay with it.
local DeskDisplayTime = 4

--> A desk stands in a corner with a ceiling right over it, so its cards have to draw over the
--> room to be readable at all. A pad stands in the open, where plain depth sorting looks better.
local DeskDisplay = { Duration = DeskDisplayTime, OnTop = true }

--> Only pad rolls carry one. A desk's rolled parts are swapped for permanent ones the moment the
--> roll ends, so there would be nothing left to pick up by the time a prompt could show.
local PickupText = "Pick Up!"
local PickupHold = 1
local PickupDistance = 10

local RollingService = {}

--> Fires with what the pad landed on, once per part picked up. Nothing listens yet: a pad roll
--> never reaches the server, so there is nowhere for a picked up part to go until there is.
RollingService.ItemPickedUp = Signal.new()

function RollingService:Roll(Positions: { [number]: CFrame? }?)
	local Count = if Positions then #Positions else PlayerData.RerollPads()

	return NetworkingClient.Roll.Invoke(Count):expect()
end

--> The part and its card arrived together and leave together. What a pickup actually means is left
--> to the signal, because this part only ever existed on this client.
function RollingService:_AddPickup(Model: Model, Card: BasePart, Final: Rolling.Result, Pad: number)
	--> An Attachment rather than a stand-in part: a prompt needs a BasePart or an Attachment to
	--> hang off, and a part would widen the model's bounds and drag its card up with them.
	local Host = Model:FindFirstChildWhichIsA("BasePart", true)

	if not Host then
		return
	end

	local Point = Instance.new("Attachment")
	Point.Name = "PickupPoint"
	Point.Parent = Host
	Point.WorldCFrame = Model:GetPivot()

	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Name = "Pickup"
	Prompt.ActionText = PickupText
	Prompt.HoldDuration = PickupHold
	Prompt.MaxActivationDistance = PickupDistance
	--> A keyboard lying on a pad hides behind the monitor on the pad in front of it easily enough
	Prompt.RequiresLineOfSight = false
	Prompt.Parent = Point

	Prompt.Triggered:Connect(function()
		--> Switched off first: the prompt outlives this frame and would happily fire twice, and it
		--> has no business showing on something already in the player's hands
		Prompt.Enabled = false

		--> Asked for rather than taken. The server holds the only real copy of what is on this pad
		--> and clears it as it hands it over, so two holds cannot both come back with a part.
		NetworkingClient.Items.PickUp.Invoke(Pad)
			:andThen(function()
				Point:Destroy()

				--> The card goes with the part rather than being dismissed, so the player can
				--> still read what they picked up. That also takes it out of the roll's list, or
				--> the next roll would dismiss a card that is now in somebody's hands.
				local Listed = table.find(self.LastDisplays or {}, Card)

				if Listed then
					table.remove(self.LastDisplays, Listed)
				end

				CarryController:Hold(Model, Final.Component, Card)
				self.ItemPickedUp:Fire(Final)
			end)
			:catch(function(Problem)
				warn(`[Pickup] {Problem}`)
				Prompt.Enabled = true
			end)
	end)
end

--> Each entry carries how its own reward card should behave, and an entry with no Display leaves
--> its card up for the caller to dismiss. That is why the anchors come back alongside the
--> container: they are deliberately not inside it, because a desk throws the container away as
--> soon as this returns and the cards have to outlive that.
function RollingService:_RollVizual(Info: {
	[number]: {
		CFrame: CFrame,
		Display: ItemDisplayController.Options?,
		Pad: number?,
		Final: {
			Component: string,
			Variant: string,
		},
	},
}): (Model, { BasePart })
	local NewContainer = Instance.new("Model")
	NewContainer.Name = "RollVizual" .. os.clock()
	NewContainer.Parent = workspace

	local HighlightEffect = Instance.new("Highlight")
	HighlightEffect.Parent = NewContainer
	HighlightEffect.FillColor = Color3.fromRGB(0, 0, 0)
	HighlightEffect.FillTransparency = 0
	HighlightEffect.OutlineColor = Color3.fromRGB(255, 255, 255)
	HighlightEffect.OutlineTransparency = 0
	HighlightEffect.DepthMode = Enum.HighlightDepthMode.Occluded

	-- Hardcoed for now, will be changed later (Amount=speed_upgrade/something idk)
	local Amount = 20
	local Opening = 0.245
	local Fastest = 0.028
	local Fade = 0.25

	local Camera = workspace.CurrentCamera
	local Fov = Camera.FieldOfView
	local Zoom = 45

	local TickSound = SFX.Tick:Clone()
	TickSound.Parent = NewContainer

	local RewardSound = SFX.Reward:Clone()
	RewardSound.Parent = NewContainer

	--> What the last pass leaves standing, in Info's order, so each one can be told what it is
	local Finals: { Model } = {}

	for RollIndex = 1, Amount do
		local Alpha = RollIndex / Amount

		local Insts = {}
		for _, Data in Info do
			--> Blur through variants of this slot's own component, so a monitor slot
			--> never flashes a keyboard on its way to the result.
			local Variant = if RollIndex < Amount then Rolling.RollVariant() else Data.Final.Variant
			local Model: Model = Parts(Data.Final.Component, Variant)

			--> Placed on the model's own pivot, which is what the offsets are measured against
			Model:PivotTo(Data.CFrame)
			Model:ScaleTo(0.01)
			Model.Parent = NewContainer
			table.insert(Insts, Model)
		end

		TickSound.TimePosition = 0
		TickSound:Play()

		local Duration = Opening * (Fastest / Opening) ^ Alpha

		local Connection, StartedAt = nil, os.clock()
		Connection = RunService.RenderStepped:Connect(function()
			if StartedAt + Duration < os.clock() then
				Connection:Disconnect()
				Connection = nil
				if RollIndex < Amount then
					for _, Model in Insts do
						Model:Destroy()
					end
				else
					for _, Model in Insts do
						Model:ScaleTo(1)
					end
				end
				return
			else
				local ConnectionAlpha = (os.clock() - StartedAt) / Duration
				for _, Model in Insts do
					Model:ScaleTo(math.max(0.01, math.sin(ConnectionAlpha * (math.pi / 2))))
				end

				local Progress = (RollIndex - 1 + ConnectionAlpha) / Amount
				Camera.FieldOfView = Fov + (Zoom - Fov) * math.sin(Progress * (math.pi / 2))
			end
		end)

		repeat
			RunService.RenderStepped:Wait()
		until not Connection

		if RollIndex == Amount then
			Finals = Insts
		end
	end

	RewardSound:Play()

	for _, Model in NewContainer:GetChildren() do
		if Model:IsA("Model") then
			local Confetti = ConfettiVFX:Clone()
			Confetti.Anchored = true
			Confetti.CanCollide = false
			Confetti.CanQuery = false
			Confetti.CanTouch = false
			Confetti.CFrame = Model:GetPivot()
			Confetti.Parent = NewContainer

			Confetti.Attachment.confetti:Emit(60)
			Debris:AddItem(Confetti, 3)
		end
	end

	--> Popped in on the confetti rather than after the fade, so the reward reads as one beat
	local Displays = {}

	for Index, Model in Finals do
		local Entry = Info[Index]
		local Card = ItemDisplayController:Show(Model, Entry.Final.Component, Entry.Final.Variant, Entry.Display)

		table.insert(Displays, Card)

		if Entry.Pad then
			self:_AddPickup(Model, Card, Entry.Final, Entry.Pad)
		end
	end

	local FadeStartedAt = os.clock()
	repeat
		local FadeAlpha = math.min((os.clock() - FadeStartedAt) / Fade, 1)
		local Transparency = math.sin(FadeAlpha * (math.pi / 2))

		HighlightEffect.FillTransparency = Transparency
		HighlightEffect.OutlineTransparency = Transparency
		Camera.FieldOfView = Zoom + (Fov - Zoom) * Transparency
		RunService.RenderStepped:Wait()
	until FadeAlpha >= 1

	return NewContainer, Displays
end

--> One entry per component, placed by its offset from the anchor's pivot. This is the desk
--> roll's layout only; a pad roll lands a single component and places it on the pad itself.
function RollingService:GetDeskVisualData(Anchor: CFrame, Desk: Rolling.Desk)
	local VisualData = {}

	for Component, Offset in Offsets.Desk do
		table.insert(VisualData, {
			CFrame = Anchor * Offset,
			Display = DeskDisplay,
			Final = { Component = Component, Variant = Desk[Component] },
		})
	end

	return VisualData
end

--> Rolls a desk's three components onto the desk itself, then hands back the container
--> so the caller can swap it for permanent parts.
function RollingService:RollDesk(DeskModel: Model, Desk: Rolling.Desk)
	return self:_RollVizual(self:GetDeskVisualData(DeskModel:GetPivot(), Desk))
end

--> One roll at a time. The visual yields for its whole run, and a second roll starting underneath
--> it destroys the first one's container halfway through that run, leaving the first to animate
--> parts that are already gone. The flag is cleared through a pcall so a failed roll cannot wedge
--> the pad shut for the rest of the session.
function RollingService:RollSlots()
	if self.Rolling then
		return nil
	end

	self.Rolling = true

	local Ok, Results = pcall(function()
		return self:_RollSlots()
	end)

	self.Rolling = false

	if not Ok then
		warn(`[Rolling] roll failed: {Results}`)
		return nil
	end

	return Results
end

function RollingService:_RollSlots()
	local Levitate = 2
	local SlotsUnlocked = PlayerData.RerollPads()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local RollResults = RollingService:Roll().Results

	local VisualData = {}

	--> One part per pad, not a desk's worth: the pad rolled a single component, so it floats
	--> on the pad's own pivot instead of being offset into a desk layout.
	for SlotIndex = 1, SlotsUnlocked do
		local Pad = Plot.Pads:FindFirstChild(SlotIndex)
		local Result = RollResults[SlotIndex - 1]

		if Pad and Result then
			table.insert(VisualData, {
				CFrame = Pad:GetPivot() + Vector3.new(0, Levitate, 0),
				--> The slot the server filed this part under, which is what a pickup asks for
				Pad = SlotIndex - 1,
				Final = { Component = Result.Component, Variant = Result.Variant },
			})
		end
	end

	if RollingService.LastVizual then
		RollingService.LastVizual:Destroy()
	end

	--> The cards live outside the container, so clearing the last roll has to take them too
	for _, Anchor in RollingService.LastDisplays or {} do
		ItemDisplayController:Dismiss(Anchor)
	end

	RollingService.LastVizual, RollingService.LastDisplays = RollingService:_RollVizual(VisualData)

	return RollResults
end

function RollingService:Start()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	local Button = Plot:WaitForChild("Buttons"):WaitForChild("Roll"):WaitForChild("Button")
	local Prompt = Button:WaitForChild("ProximityPrompt")

	Prompt.Triggered:Connect(function()
		--> RollSlots turns a second roll away on its own, but taking the prompt down says so
		--> rather than leaving the pad looking like it ignored them.
		Prompt.Enabled = false

		local Data = self:RollSlots()

		Prompt.Enabled = true
		print(Data)
	end)
end

return RollingService
