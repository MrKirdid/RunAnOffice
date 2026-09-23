local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ScreenShakeController = require(Shared.Controllers.ScreenShakeController)
local SoundController = require(Shared.Controllers.SoundController)

--> A volley of fireworks off a point in the world: each shell climbs on a curve with a trail
--> behind it, bangs, and throws its colour. The effect is built here off the pack's numbers rather
--> than cloned out of the place, so a retuned emitter is a retuned number.

local ContainerName = "Fireworks"

--> Seconds in the air and studs climbed, each drawn between the pair off one seed so a short flight
--> is a low one; and how far the shell curves over while it climbs, in degrees.
local FlightDuration = NumberRange.new(0.15, 0.6)
local FlightStuds = NumberRange.new(10, 15)
local CurveAngle = 60

--> How long the spent shell hangs around for its sparks to finish, and how long after the bang
--> the sparks keep coming.
local Linger = 2
local SparkTime = 0.3

--> The gap between shells in a volley, and how many go up when nobody says.
local VolleyGap = NumberRange.new(0.05, 0.085)
local VolleySize = NumberRange.new(5, 7)

local LinesBurst = NumberRange.new(60, 100)
local SparksBurst = NumberRange.new(40, 80)

local LinesTexture = "rbxassetid://3113323162"
local SparksTexture = "rbxassetid://6763809313"
local SmokeTexture = "rbxassetid://5440074294"

local Colors = {
	Color3.fromRGB(255, 34, 34),
	Color3.fromRGB(255, 107, 38),
	Color3.fromRGB(255, 196, 46),
	Color3.fromRGB(158, 255, 94),
	Color3.fromRGB(156, 255, 247),
	Color3.fromRGB(160, 174, 255),
	Color3.fromRGB(222, 156, 255),
	Color3.fromRGB(255, 179, 226),
}

local Draw = Random.new()

local FireworksController = {
	--> the colour of the last bang, so two in a row are never the same
	LastColor = nil :: Color3?,
}

local function GetContainer(): Folder
	local Existing = workspace:FindFirstChild(ContainerName)

	if Existing and Existing:IsA("Folder") then
		return Existing
	end

	local Container = Instance.new("Folder")
	Container.Name = ContainerName
	Container.Parent = workspace

	return Container
end

local function BuildTrail(Name: string, Parent: BasePart, Offset: number, Texture: string?, Lifetime: number)
	local Head = Instance.new("Attachment")
	Head.CFrame = CFrame.new(0, 0, Offset)
	Head.Parent = Parent

	local Tail = Instance.new("Attachment")
	Tail.CFrame = CFrame.new(0.068, 0.068, -Offset)
	Tail.Parent = Parent

	local Trail = Instance.new("Trail")
	Trail.Name = Name
	Trail.Attachment0 = Head
	Trail.Attachment1 = Tail
	Trail.Lifetime = Lifetime
	Trail.MinLength = 0.1
	Trail.LightEmission = 1
	Trail.LightInfluence = 0
	Trail.FaceCamera = true
	Trail.TextureLength = 0.5
	Trail.TextureMode = Enum.TextureMode.Stretch
	Trail.Color = ColorSequence.new(Color3.new(1, 1, 1))

	if Texture then
		Trail.Texture = Texture
		Trail.Transparency = NumberSequence.new(0, 1)
		Trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.647),
			NumberSequenceKeypoint.new(0.466, 0.647),
			NumberSequenceKeypoint.new(1, 0),
		})
	else
		Trail.Transparency = NumberSequence.new(0.5, 1)
		Trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.647),
			NumberSequenceKeypoint.new(0.2, 0.647),
			NumberSequenceKeypoint.new(0.4, 0.606),
			NumberSequenceKeypoint.new(0.616, 0.481),
			NumberSequenceKeypoint.new(0.835, 0.263),
			NumberSequenceKeypoint.new(1, 0),
		})
	end

	Trail.Parent = Parent
end

local function BuildLines(Parent: Attachment): ParticleEmitter
	local Lines = Instance.new("ParticleEmitter")
	Lines.Name = "Lines"
	Lines.Enabled = false
	Lines.Texture = LinesTexture
	Lines.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.699, 0.3125),
		NumberSequenceKeypoint.new(1, 0),
	})
	Lines.Transparency = NumberSequence.new(0)
	Lines.Lifetime = NumberRange.new(0.6, 1.3)
	Lines.Speed = NumberRange.new(41, 41)
	Lines.Rate = 11
	Lines.LightEmission = 0.2
	Lines.LightInfluence = 0.4
	Lines.SpreadAngle = Vector2.new(360, 360)
	Lines.Rotation = NumberRange.new(0, 360)
	Lines.RotSpeed = NumberRange.new(-80, 80)
	Lines.Acceleration = Vector3.new(0, -3, 0)
	Lines.Drag = 12.5
	Lines.Orientation = Enum.ParticleOrientation.VelocityParallel
	Lines.Brightness = 4.5
	Lines.LockedToPart = true
	Lines.Parent = Parent

	return Lines
end

local function BuildSparks(Parent: Attachment): ParticleEmitter
	local Sparks = Instance.new("ParticleEmitter")
	Sparks.Name = "Sparks"
	Sparks.Enabled = false
	Sparks.Texture = SparksTexture
	Sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.875, 0.875),
		NumberSequenceKeypoint.new(1, 0),
	})
	Sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	Sparks.Squash = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1875, 1),
		NumberSequenceKeypoint.new(1, -0.4875, 1),
	})
	Sparks.Lifetime = NumberRange.new(0.6, 1.2)
	Sparks.Speed = NumberRange.new(15, 15)
	Sparks.Rate = 100
	Sparks.LightEmission = 1
	Sparks.LightInfluence = 0
	Sparks.SpreadAngle = Vector2.new(-180, 180)
	Sparks.Rotation = NumberRange.new(-90, -90)
	Sparks.Drag = 5
	Sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	Sparks.Brightness = 10
	Sparks.ZOffset = 2
	Sparks.LockedToPart = true
	Sparks.Parent = Parent

	return Sparks
end

--> One shell: an invisible part carrying its trails and, at the tip, the burst.
local function BuildShell(): (BasePart, ParticleEmitter, ParticleEmitter)
	local Shell = Instance.new("Part")
	Shell.Name = "Firework"
	Shell.Size = Vector3.one
	Shell.Transparency = 1
	Shell.Anchored = true
	Shell.CanCollide = false
	Shell.CanQuery = false
	Shell.CanTouch = false
	Shell.CastShadow = false
	Shell.Massless = true

	BuildTrail("Follow", Shell, 0.171, nil, 0.2)
	BuildTrail("Smoke", Shell, 0.339, SmokeTexture, 0.45)

	local Explosion = Instance.new("Attachment")
	Explosion.Name = "Explosion"
	Explosion.Parent = Shell

	return Shell, BuildLines(Explosion), BuildSparks(Explosion)
end

function FireworksController:_PickColor(): Color3
	local Color = Colors[Draw:NextInteger(1, #Colors)]

	--> one more draw is enough: with eight to pick from it comes up the same twice only once in
	--> eight, and never three times
	if Color == self.LastColor then
		Color = Colors[Draw:NextInteger(1, #Colors)]
	end

	self.LastColor = Color

	return Color
end

function FireworksController:Launch(Position: Vector3)
	local Shell, Lines, Sparks = BuildShell()

	Shell.CFrame = CFrame.new(Position) * CFrame.Angles(0, math.rad(Draw:NextInteger(1, 360)), 0)
	Shell.Parent = GetContainer()

	SoundController:PlayAt("FireworkLaunch", Position)

	--> one seed for both, so the shell that is up the longest is the one that goes the highest
	local Seed = Draw:NextNumber()
	local Duration = FlightDuration.Min + (FlightDuration.Max - FlightDuration.Min) * Seed
	local Studs = FlightStuds.Min + (FlightStuds.Max - FlightStuds.Min) * Seed

	local Elapsed = 0
	local Climb: RBXScriptConnection

	Climb = RunService.RenderStepped:Connect(function(Delta: number)
		Elapsed += Delta

		if Elapsed >= Duration then
			Climb:Disconnect()
			return
		end

		local Fraction = Delta / Duration

		Shell.CFrame = Shell.CFrame
			* CFrame.Angles(math.rad(CurveAngle * Fraction), 0, 0)
			* CFrame.new(0, Studs * Fraction, 0)
	end)

	task.delay(Duration, function()
		if not Shell.Parent then
			return
		end

		SoundController:PlayAt("FireworkExplode", Shell.Position)
		ScreenShakeController:Shake(0.35)

		local Color = self:_PickColor()

		Lines.Color = ColorSequence.new(Color)
		Sparks.Color = ColorSequence.new(Color)

		Lines:Emit(Draw:NextInteger(LinesBurst.Min, LinesBurst.Max))
		Sparks:Emit(Draw:NextInteger(SparksBurst.Min, SparksBurst.Max))

		task.delay(SparkTime, function()
			Sparks.Enabled = false
		end)

		task.delay(Linger, function()
			Shell:Destroy()
		end)
	end)
end

--> A volley off one point. Yields for as long as the volley takes to go up, so a caller that
--> wants on with its life spawns it.
function FireworksController:Play(Position: Vector3, Amount: number?, Gap: number?)
	local Count = Amount or Draw:NextInteger(VolleySize.Min, VolleySize.Max)

	for _ = 1, Count do
		task.wait(Gap or Draw:NextNumber(VolleyGap.Min, VolleyGap.Max))

		self:Launch(Position)
	end
end

return FireworksController
