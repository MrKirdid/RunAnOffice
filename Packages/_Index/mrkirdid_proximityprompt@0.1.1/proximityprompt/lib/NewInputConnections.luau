-- Types
type Properties = {
	prompt: ProximityPrompt,
	ButtonHeldDown: any,
	CurrentBarSize: any,
	CurrentFrameScaleFactor: any,
	PromptTransparency: any,
	InputFrameScaleFactor: any,
}

-- Constants
local APPEAR_SOUND = "rbxassetid://10066931761"
local CLICK_SOUND = "rbxassetid://10128760939"
local HOLD_SOUND = "rbxassetid://421058925"
local TRIGGER_SOUND = "rbxassetid://10128766965"

-- Services
local RunService = game:GetService("RunService")

-- Imports
local Packages = script:FindFirstAncestorOfClass("Folder")
local Fusion = require(Packages.Fusion)
local New = Fusion.New
local Hydrate = Fusion.Hydrate

--[[
	@docs PlaySound
]]
local function PlaySound(SoundId, Properties: { [string]: any }?)
	local Sound = script:FindFirstChild(SoundId)

	if not Sound then
		Sound = New("Sound")({
			Name = SoundId,
			SoundId = SoundId,
			Volume = 0.35,
			Parent = script,
		})

		if Properties then
			Hydrate(Sound)(Properties)
		end
	end

	Sound:Play()
end

--[[
	@docs StopSound
]]
local function StopSound(SoundId)
	local Sound = script:FindFirstChild(SoundId)
	if Sound then
		Sound:Stop()
	end
end

--[[
	@docs NewInputConnections
]]
return function(Properties: Properties): { RBXScriptConnection }
	local InputConnections = {}
	local HoldStart = os.clock()

	PlaySound(APPEAR_SOUND)

	----------------------------------------------------------------
	-- 🔒 SAFETY: stop HOLD sound if prompt is destroyed or removed
	----------------------------------------------------------------
	InputConnections[#InputConnections + 1] = Properties.prompt.Destroying:Connect(function()
		StopSound(HOLD_SOUND)
	end)

	InputConnections[#InputConnections + 1] = Properties.prompt.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			StopSound(HOLD_SOUND)
		end
	end)

	----------------------------------------------------------------
	-- Hold logic
	----------------------------------------------------------------
	if Properties.prompt.HoldDuration > 0 then
		InputConnections[#InputConnections + 1] = RunService.RenderStepped:Connect(function(deltaTime)
			if not Properties.ButtonHeldDown:get() then
				Properties.CurrentBarSize:set(0)
				return
			end

			local TimeHeldDown = os.clock() - HoldStart
			Properties.CurrentBarSize:set(
				math.min(Properties.CurrentBarSize:get() + deltaTime / Properties.prompt.HoldDuration, 1)
			)

			local HoldSound = script:FindFirstChild(HOLD_SOUND)
			if HoldSound then
				HoldSound.PlaybackSpeed = 0.5 + TimeHeldDown
			end
		end)

		InputConnections[#InputConnections + 1] = Properties.prompt.PromptButtonHoldBegan:Connect(function()
			HoldStart = os.clock()

			PlaySound(HOLD_SOUND, {
				Looped = true,
				Volume = 0.2,
			})

			PlaySound(CLICK_SOUND, {
				Volume = 1,
			})

			Properties.ButtonHeldDown:set(true)
			Properties.CurrentFrameScaleFactor:set(Properties.InputFrameScaleFactor)
		end)

		InputConnections[#InputConnections + 1] = Properties.prompt.PromptButtonHoldEnded:Connect(function()
			StopSound(HOLD_SOUND)
			Properties.ButtonHeldDown:set(false)
			Properties.CurrentFrameScaleFactor:set(1)
		end)
	end

	----------------------------------------------------------------
	-- Triggered
	----------------------------------------------------------------
	InputConnections[#InputConnections + 1] = Properties.prompt.Triggered:Connect(function()
		if Properties.prompt.HoldDuration > 0 then
			PlaySound(TRIGGER_SOUND)
		else
			PlaySound(CLICK_SOUND, { Volume = 1 })
			Properties.ButtonHeldDown:set(true)
			task.delay(1 / 60, Properties.ButtonHeldDown.set, Properties.ButtonHeldDown, false)
		end
	end)

	return InputConnections
end
