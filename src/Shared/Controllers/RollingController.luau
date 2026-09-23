local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local ItemDisplayController = require(Shared.Controllers.ItemDisplayController)
local Items = require(Shared.Utilities.Items)
local SoundController = require(Shared.Controllers.SoundController)
local CarryController = require(Shared.Controllers.CarryController)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local Signal = require(Shared.Packages.Fastsignal)
local Rolling = require(Shared.Utilities.Rolling)
local PartConfigs = require(Shared.Configs.Parts)
local Offsets = require(Shared.Configs.Offsets)
local Tiers = require(Shared.Utilities.Tiers)
local VfxController = require(Shared.Controllers.VfxController)
local PlayerData = require(Shared.PlayerData).client
local Store = require(Shared.Utilities.Store)
local Parts = require(Assets.Parts)

local SFX = Assets.SFX.Rolling
local ConfettiVFX = Assets.VFX.ConfettiVFX

local DeskDisplayTime = 4

--> How often Auto Roll looks for a chance to press the button.
local AutoRollInterval = 3
local DeskDisplay = { Duration = DeskDisplayTime, OnTop = true }

local PickupText = "Pick Up!"
local PickupHold = 0.33
local PickupDistance = 10

type Entries = { [string]: { Value: number, Rarity: number } }

type VisualEntry = {
	CFrame: CFrame,
	Display: ItemDisplayController.Options?,
	Pad: number?,
	Fixed: boolean?,
	Final: { Component: string, Variant: string },
}

local CameraZoom = 45

--> Rolls overlap: desks bought back to back spawn one each, and a desk roll can land under a pad
--> roll. Left alone every one of them drives the FieldOfView and each reads the last one's zoom as
--> the value to hand back, so the camera never returns. Only the newest roll drives it.
local Focus = {
	Latest = 0,
	Active = 0,
	Base = nil :: number?,
}

local function ClaimCamera(): number
	if Focus.Active == 0 then
		Focus.Base = workspace.CurrentCamera.FieldOfView
	end

	Focus.Active += 1
	Focus.Latest += 1

	return Focus.Latest
end

local function OwnsCamera(Ticket: number): boolean
	return Ticket == Focus.Latest
end

local function ReleaseCamera(Ticket: number)
	if OwnsCamera(Ticket) and Focus.Base then
		workspace.CurrentCamera.FieldOfView = Focus.Base
	end

	Focus.Active -= 1

	if Focus.Active == 0 then
		Focus.Base = nil
	end
end

local Excluding: { [string]: Entries } = {}

--> A blur free to draw the part being won shows the result early, so both halves exclude it.
local function BlurComponent(Final: string): string
	local Others = Excluding[Final]

	if not Others then
		Others = {}

		for Name, Entry in PartConfigs.BaseValues do
			if Name ~= Final then
				Others[Name] = Entry
			end
		end

		Excluding[Final] = Others
	end

	if next(Others) == nil then
		return Final
	end

	return Rolling.Pick(Others)
end

local function GetBlurVariants(Info: { { Final: { Component: string, Variant: string } } }): { [string]: Entries }
	local Landing: { [string]: { [string]: boolean } } = {}

	for _, Data in Info do
		local Blocked = Landing[Data.Final.Component]

		if not Blocked then
			Blocked = {}
			Landing[Data.Final.Component] = Blocked
		end

		Blocked[Data.Final.Variant] = true
	end

	local Tables: { [string]: Entries } = {}

	for Component in PartConfigs.BaseValues do
		local Blocked = Landing[Component]
		local Variants: Entries = {}
		local Any = false

		for Name, Entry in PartConfigs.Variants do
			if not (Blocked and Blocked[Name]) then
				Variants[Name] = Entry
				Any = true
			end
		end

		Tables[Component] = if Any then Variants else PartConfigs.Variants
	end

	return Tables
end

local RollingService = {}

RollingService.ItemPickedUp = Signal.new()

function RollingService:Roll(Positions: { [number]: CFrame? }?)
	local Count = if Positions then #Positions else PlayerData.RerollPads()

	return NetworkingClient.Roll.Invoke(Count):expect()
end

function RollingService:_AddPickup(Model: Model, Card: BasePart, Final: Rolling.Result, Pad: number)
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
	Prompt.RequiresLineOfSight = false
	Prompt.Parent = Point

	Prompt.Triggered:Connect(function()
		--> One part at a time. The server refuses this too; answering here saves the round trip
		--> and the warning it would come back with.
		if Items.IsHeld(PlayerData.Holding()) then
			SoundController:Play("Error")
			return
		end

		Prompt.Enabled = false

		NetworkingClient.Items.PickUp
			.Invoke(Pad)
			:andThen(function()
				SoundController:Play("Confirm")

				Point:Destroy()

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

function RollingService:_Spin(
	Info: { VisualEntry },
	Ticket: number,
	NewContainer: Model,
	Displays: { BasePart }
): { BasePart }
	local BlurVariants = GetBlurVariants(Info)

	local HighlightEffect = Instance.new("Highlight")
	HighlightEffect.Parent = NewContainer
	HighlightEffect.FillColor = Color3.fromRGB(0, 0, 0)
	HighlightEffect.FillTransparency = 0
	HighlightEffect.OutlineColor = Color3.fromRGB(255, 255, 255)
	HighlightEffect.OutlineTransparency = 0
	HighlightEffect.DepthMode = Enum.HighlightDepthMode.Occluded

	--> How much quicker the spin resolves, off the rolling branch of the upgrade tree. Both ends of
	--> the curve are divided by it, so the whole spin shortens by the same factor rather than the
	--> tail alone, and the number of ticks stays the same.
	--> Fast Spin doubles whatever the tree got the spin to.
	local Speed = math.max(PlayerData.Multipliers.RollSpeed(), 0.1)
		* (if Store.Owns(PlayerData, "FastSpin") then 2 else 1)

	local Amount = 20
	local Opening = 0.245 / Speed
	local Fastest = 0.028 / Speed
	local Fade = 0.25
	local TickTopPitch = 3.5

	local Camera = workspace.CurrentCamera

	--> Where this roll's zoom starts. A roll taking over mid spin picks the camera up where the
	--> last one left it rather than snapping back out first.
	local From = Camera.FieldOfView

	local TickSound = SFX.Tick:Clone()
	TickSound.Parent = NewContainer

	local RewardSound = SFX.Reward:Clone()
	RewardSound.Parent = NewContainer

	local Finals: { Model } = {}

	for RollIndex = 1, Amount do
		local Alpha = RollIndex / Amount

		local Insts = {}
		for _, Data in Info do
			local Blurring = RollIndex < Amount

			local Component = if Blurring and not Data.Fixed
				then BlurComponent(Data.Final.Component)
				else Data.Final.Component

			local Variant = if Blurring then Rolling.Pick(BlurVariants[Component]) else Data.Final.Variant

			local Model: Model = Parts(Component, Variant)

			Model:PivotTo(Data.CFrame)
			Model:ScaleTo(0.01)
			Model.Parent = NewContainer
			table.insert(Insts, Model)
		end

		--> Geometric like the timing curve is, so the step between ticks is the same interval
		--> every time instead of flattening out as the spin speeds up.
		local PitchAlpha = if Amount > 1 then (RollIndex - 1) / (Amount - 1) else 1

		TickSound.PlaybackSpeed = TickTopPitch ^ PitchAlpha
		TickSound.TimePosition = 0
		TickSound:Play()

		local Duration = Opening * (Fastest / Opening) ^ Alpha

		local StartedAt = os.clock()

		while true do
			local Elapsed = os.clock() - StartedAt

			if Elapsed >= Duration then
				break
			end

			local StepAlpha = Elapsed / Duration

			for _, Model in Insts do
				Model:ScaleTo(math.max(0.01, math.sin(StepAlpha * (math.pi / 2))))
			end

			if OwnsCamera(Ticket) then
				local Progress = (RollIndex - 1 + StepAlpha) / Amount
				Camera.FieldOfView = From + (CameraZoom - From) * math.sin(Progress * (math.pi / 2))
			end

			RunService.RenderStepped:Wait()
		end

		if RollIndex < Amount then
			for _, Model in Insts do
				Model:Destroy()
			end
		else
			for _, Model in Insts do
				Model:ScaleTo(1)
			end

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

	--> Only what the spin landed on wears one. The models the reel is blurred with are thrown away
	--> a frame later, and an aura flickering through them would give the result away before the
	--> spin got to it.
	for Index, Model in Finals do
		local Entry = Info[Index]

		VfxController:Aura(Model, (Tiers.FromVariant(Entry.Final.Variant)))

		local Card = ItemDisplayController:Show(Model, Entry.Final.Component, Entry.Final.Variant, Entry.Display)

		table.insert(Displays, Card)

		if Entry.Pad then
			self:_AddPickup(Model, Card, Entry.Final, Entry.Pad)
		end
	end

	local FadeStartedAt = os.clock()
	local FadeAlpha = 0

	repeat
		FadeAlpha = math.min((os.clock() - FadeStartedAt) / Fade, 1)

		local Transparency = math.sin(FadeAlpha * (math.pi / 2))

		HighlightEffect.FillTransparency = Transparency
		HighlightEffect.OutlineTransparency = Transparency

		if OwnsCamera(Ticket) then
			local Base = Focus.Base or From
			Camera.FieldOfView = CameraZoom + (Base - CameraZoom) * Transparency
		end

		RunService.RenderStepped:Wait()
	until FadeAlpha >= 1

	return Displays
end

--> The container and the cards are built out here so a spin that throws part way still has both
--> torn down, and the camera handed back, instead of leaving a half built roll in the workspace.
function RollingService:_RollVizual(Info: { VisualEntry }): (Model, { BasePart })
	local Ticket = ClaimCamera()

	local NewContainer = Instance.new("Model")
	NewContainer.Name = "RollVizual" .. os.clock()
	NewContainer.Parent = workspace

	local Displays: { BasePart } = {}

	local Ok, Problem = pcall(function()
		self:_Spin(Info, Ticket, NewContainer, Displays)
	end)

	ReleaseCamera(Ticket)

	if not Ok then
		NewContainer:Destroy()

		for _, Anchor in Displays do
			ItemDisplayController:Dismiss(Anchor)
		end

		error(Problem, 0)
	end

	return NewContainer, Displays
end

function RollingService:GetDeskVisualData(Anchor: CFrame, Desk: Rolling.Desk)
	local VisualData = {}

	for Component, Offset in Offsets.Desk do
		table.insert(VisualData, {
			CFrame = Anchor * Offset,
			Display = DeskDisplay,
			Fixed = true,
			Final = { Component = Component, Variant = Desk[Component] },
		})
	end

	return VisualData
end

function RollingService:RollDesk(DeskModel: Model, Desk: Rolling.Desk)
	return self:_RollVizual(self:GetDeskVisualData(DeskModel:GetPivot(), Desk))
end

--> One part, in the one place on the desk it belongs: the spin behind a slot button. Fixed like
--> the desk roll is, because which of the three this is was settled by the button that was pressed
--> -- only the quality is still up in the air, so only the variant blurs.
function RollingService:RollComponent(Anchor: CFrame, Component: string, Variant: string)
	return self:_RollVizual({
		{
			CFrame = Anchor,
			Display = DeskDisplay,
			Fixed = true,
			Final = { Component = Component, Variant = Variant },
		},
	})
end

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

	for SlotIndex = 1, SlotsUnlocked do
		local Pad = Plot.Pads:FindFirstChild(SlotIndex)
		local Result = RollResults[SlotIndex - 1]

		if Pad and Result then
			table.insert(VisualData, {
				CFrame = Pad:GetPivot() + Vector3.new(0, Levitate, 0),
				Pad = SlotIndex - 1,
				Final = { Component = Result.Component, Variant = Result.Variant },
			})
		end
	end

	if RollingService.LastVizual then
		RollingService.LastVizual:Destroy()
	end

	for _, Anchor in RollingService.LastDisplays or {} do
		ItemDisplayController:Dismiss(Anchor)
	end

	--> Dropped before the roll rather than after it, or a roll that throws leaves these pointing
	--> at the torn down one for the rest of the session.
	RollingService.LastVizual, RollingService.LastDisplays = nil, nil

	RollingService.LastVizual, RollingService.LastDisplays = RollingService:_RollVizual(VisualData)

	return RollResults
end

function RollingService:Start()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	local Button = Plot:WaitForChild("Buttons"):WaitForChild("Roll"):WaitForChild("Button")
	local Prompt = Button:WaitForChild("ProximityPrompt")

	Prompt.Triggered:Connect(function()
		Prompt.Enabled = false

		SoundController:Play("Press")

		local Data = self:RollSlots()

		Prompt.Enabled = true
		print(Data)
	end)

	--> Auto Roll presses the button for the player while they stand on their own plot. Paced by
	--> the spin rather than a timer, and never while a roll is already going or the button is
	--> switched off for one.
	task.spawn(function()
		while true do
			task.wait(AutoRollInterval)

			if not Store.Owns(PlayerData, "AutoRoll") or self.Rolling or not Prompt.Enabled then
				continue
			end

			local Character = Players.LocalPlayer.Character
			local Root = Character and Character:FindFirstChild("HumanoidRootPart")

			if not Root or not Root:IsA("BasePart") then
				continue
			end

			local Reach = Plot:GetExtentsSize().Magnitude / 2

			if (Plot:GetPivot().Position - Root.Position).Magnitude > Reach then
				continue
			end

			Prompt.Enabled = false
			self:RollSlots()
			Prompt.Enabled = true
		end
	end)
end

return RollingService
