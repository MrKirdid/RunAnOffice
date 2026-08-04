local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local networkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local Rolling = require(Shared.Utilities.Rolling)
local PlayerData = require(Shared.PlayerData).client
local Parts = require(Assets.Parts)

local SFX = Assets.SFX.Rolling
local ConfettiVFX = Assets.VFX.ConfettiVFX

local RollingService = {}

function RollingService:Roll(Positions: { [number]: CFrame? }?)
	local Count = if Positions then #Positions else PlayerData.RerollPads()

	return networkingClient.Roll.Invoke(Count):expect()
end

function RollingService:_roll_vizual(Info: {
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

	-- Hardcoed for now, will be changed later (amount=speed_upgrade/something idk)
	local amount = 20
	local levitate = 2
	local opening = 0.245
	local fastest = 0.028
	local fade = 0.25

	local Camera = workspace.CurrentCamera
	local fov = Camera.FieldOfView
	local zoom = 45

	local TickSound = SFX.Tick:Clone()
	TickSound.Parent = NewContainer

	local RewardSound = SFX.Reward:Clone()
	RewardSound.Parent = NewContainer

	for RollIndex = 1, amount do
		local Alpha = RollIndex / amount

		local insts = {}
		for _, Data in Info do
			local NewRollData = Rolling.RollOne()
			local Model: Model = RollIndex < amount and Parts(NewRollData.Component, NewRollData.Variant)
				or Parts(Data.Final.Component, Data.Final.Variant)

			Model.WorldPivot = Model:GetPivot():ToWorldSpace() * CFrame.new(0, -Model:GetExtentsSize().Y / 2, 0)
			Model:PivotTo(Data.CFrame + Vector3.new(0, levitate, 0))
			Model:ScaleTo(0.01)
			Model.Parent = NewContainer
			table.insert(insts, Model)
		end

		TickSound.TimePosition = 0
		TickSound:Play()

		local Duration = opening * (fastest / opening) ^ Alpha

		local Connection, StartedAt = nil, os.clock()
		Connection = RunService.RenderStepped:Connect(function()
			if StartedAt + Duration < os.clock() then
				Connection:Disconnect()
				Connection = nil
				if RollIndex < amount then
					for _, Model in insts do
						Model:Destroy()
					end
				else
					for _, Model in insts do
						Model:ScaleTo(1)
					end
				end
				return
			else
				local ConnectionAlpha = (os.clock() - StartedAt) / Duration
				for _, Model in insts do
					Model:ScaleTo(math.max(0.01, math.sin(ConnectionAlpha * (math.pi / 2))))
				end

				local Progress = (RollIndex - 1 + ConnectionAlpha) / amount
				Camera.FieldOfView = fov + (zoom - fov) * math.sin(Progress * (math.pi / 2))
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
		local FadeAlpha = math.min((os.clock() - FadeStartedAt) / fade, 1)
		local Transparency = math.sin(FadeAlpha * (math.pi / 2))

		HighlightEffect.FillTransparency = Transparency
		HighlightEffect.OutlineTransparency = Transparency
		Camera.FieldOfView = zoom + (fov - zoom) * Transparency
		RunService.RenderStepped:Wait()
	until FadeAlpha >= 1

	return NewContainer
end

function RollingService:RollSlots()
	local SlotsUnlocked = PlayerData.RerollPads()
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local RollResults = RollingService:Roll().Results

	local Visual_data = {}

	for SlotIndex = 1, SlotsUnlocked do
		Visual_data[SlotIndex] =
			{ CFrame = Plot.Pads:FindFirstChild(SlotIndex):GetPivot(), Final = RollResults[SlotIndex - 1] }
	end

	if RollingService.LastVizual then
		RollingService.LastVizual:Destroy()
	end

	RollingService.LastVizual = RollingService:_roll_vizual(Visual_data)

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
