local RunService = game:GetService("RunService")

--> A kick to the camera for a moment that deserves one: a desk bought, an upgrade landing, a
--> firework going off, somebody walking out with your employee. Applied on top of whatever the
--> camera is doing, after it has done it, so the player's own camera is never fought.

local BindName = "ScreenShake"

--> Studs of throw per unit of strength, degrees of roll per unit, and how the throw dies: the
--> shake is a random offset scaled by what is left of it, and what is left drains at this rate.
local Throw = 0.35
local Roll = 0.6
local Decay = 9

--> How much a new shake can pile onto one still running. Two bangs in a row are louder than one
--> but not a rattle that never ends.
local MaxStrength = 3

local Draw = Random.new()

local ScreenShakeController = {
	Name = "ScreenShakeController",

	--> what is left of the shake, 0 when the camera is still
	Strength = 0,
}

--> Adds a shake. Strength is in the units above, so 1 is a nudge and 3 is a bang.
function ScreenShakeController:Shake(Strength: number)
	self.Strength = math.min(self.Strength + Strength, MaxStrength)
end

function ScreenShakeController:Step(Delta: number)
	if self.Strength <= 0 then
		return
	end

	local Camera = workspace.CurrentCamera
	local Left = self.Strength

	self.Strength = math.max(Left - Left * Decay * Delta, 0)

	if self.Strength < 0.02 then
		self.Strength = 0
		return
	end

	local Offset = Vector3.new(Draw:NextNumber(-1, 1), Draw:NextNumber(-1, 1), 0) * Throw * Left
	local Tilt = math.rad(Draw:NextNumber(-1, 1) * Roll * Left)

	Camera.CFrame = Camera.CFrame * CFrame.new(Offset) * CFrame.Angles(0, 0, Tilt)
end

function ScreenShakeController:Start()
	--> after the camera scripts have placed the camera for the frame, so the kick is on top of
	--> the frame's own move rather than under it
	RunService:BindToRenderStep(BindName, Enum.RenderPriority.Camera.Value + 1, function(Delta: number)
		self:Step(Delta)
	end)
end

return ScreenShakeController
