local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local NetworkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local Rolling = require(Shared.Utilities.Rolling)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local Parts = require(Assets.Parts)

local SFX = Assets.SFX.Rolling
local ConfettiVFX = Assets.VFX.ConfettiVFX

local RollingService = {}

function RollingService:Roll(Positions: { [number]: CFrame? }?)
	local Count = if Positions then #Positions else PlayerData.RerollPads()

	return NetworkingClient.Roll.Invoke(Count):expect()
end

function RollingService:_RollVizual(Info: {
	[number]: {
		CFrame: CFrame,
		Final: {
			Component: string,
			Variant: string,
		},
	},
})
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

	local FadeStartedAt = os.clock()
	repeat
		local FadeAlpha = math.min((os.clock() - FadeStartedAt) / Fade, 1)
		local Transparency = math.sin(FadeAlpha * (math.pi / 2))

		HighlightEffect.FillTransparency = Transparency
		HighlightEffect.OutlineTransparency = Transparency
		Camera.FieldOfView = Zoom + (Fov - Zoom) * Transparency
		RunService.RenderStepped:Wait()
	until FadeAlpha >= 1

	return NewContainer
end

--> One entry per component, placed by its offset from the anchor's pivot. Shared by the
--> desk roll and the pad roll so both land the three parts in the same relative layout.
function RollingService:GetDeskVisualData(Anchor: CFrame, Desk: Rolling.Desk)
	local VisualData = {}

	for Component, Offset in Offsets.Desk do
		table.insert(VisualData, {
			CFrame = Anchor * Offset,
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

function RollingService:RollSlots()
	local Levitate = 2
	local SlotsUnlocked = PlayerData.RerollPads()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local RollResults = RollingService:Roll().Results

	local VisualData = {}

	for SlotIndex = 1, SlotsUnlocked do
		local Pad = Plot.Pads:FindFirstChild(SlotIndex)
		local Desk = RollResults[SlotIndex - 1]

		if Pad and Desk then
			local Anchor = Pad:GetPivot() + Vector3.new(0, Levitate, 0)

			for _, Entry in self:GetDeskVisualData(Anchor, Desk) do
				table.insert(VisualData, Entry)
			end
		end
	end

	if RollingService.LastVizual then
		RollingService.LastVizual:Destroy()
	end

	RollingService.LastVizual = RollingService:_RollVizual(VisualData)

	return RollResults
end

function RollingService:Start()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	local Button = Plot:WaitForChild("Buttons"):WaitForChild("Roll"):WaitForChild("Button")

	Button:WaitForChild("ProximityPrompt").Triggered:Connect(function()
		local Data = self:RollSlots()
		print(Data)
	end)
end

return RollingService
