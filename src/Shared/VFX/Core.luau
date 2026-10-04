local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--> The building blocks every gear effect is made of, ported from the VFX lab. Everything runs on one
--> scaled clock, so an effect can hit-stop on the local player's own hit, and so it can be frozen at
--> any instant with PauseAt for a frame-by-frame review in edit mode. Client only: nothing here is
--> made on the server, so none of it replicates or costs anyone else a frame.

--> how slow the world runs during a hit-stop
local HitstopScale = 0.06

local FolderName = "GearVfx"

--> the drop Ground casts, and where it gives up and guesses
local GroundLift = 4
local GroundReach = 60

local Draw = Random.new()

type Job = {
	Fn: (Delta: number, Age: number) -> boolean,
	Age: number,
	Real: boolean,
}

export type Ground = {
	Position: Vector3,
	Normal: Vector3,
	Material: Enum.Material,
	Color: Color3,
}

local Core = {
	Name = "Core",

	--> 1 is normal, 0 is frozen
	TimeScale = 1,

	--> the world clock, which a hit-stop slows
	Now = 0,

	--> freezes the clock the moment Now reaches it, for review
	PauseAt = nil :: number?,

	Draw = Draw,

	_Jobs = {} :: { Job },
	_Emitters = {} :: { [ParticleEmitter]: boolean },

	--> the attachments bursts and lights hang off, which live on the terrain rather than in the folder
	_Attachments = {} :: { [Attachment]: boolean },
	_Hitstop = 0,
	_LastScale = 1,
	_Connection = nil :: RBXScriptConnection?,
}

local function GetFolder(): Folder
	local Existing = workspace:FindFirstChild(FolderName)

	if Existing and Existing:IsA("Folder") then
		return Existing
	end

	local Folder = Instance.new("Folder")
	Folder.Name = FolderName
	Folder.Parent = workspace

	return Folder
end

Core.GetFolder = GetFolder

function Core:_Step(RealDelta: number)
	local Base = RealDelta * self.TimeScale
	local Scale = self.TimeScale

	if self._Hitstop > 0 and Base > 0 then
		self._Hitstop -= Base
		Scale *= HitstopScale
	end

	local WorldDelta = RealDelta * Scale

	self.Now += WorldDelta

	if self.PauseAt and self.Now >= self.PauseAt then
		self.TimeScale = 0
		self.PauseAt = nil
		Scale = 0
	end

	if Scale ~= self._LastScale then
		self._LastScale = Scale

		for Emitter in self._Emitters do
			Emitter.TimeScale = Scale
		end
	end

	local Index = 1

	while Index <= #self._Jobs do
		local Job = self._Jobs[Index]
		local Delta = if Job.Real then Base else WorldDelta

		Job.Age += Delta

		if Job.Fn(Delta, Job.Age) then
			Index += 1
			continue
		end

		table.remove(self._Jobs, Index)
	end
end

--> Fn runs every frame until it returns false. Real runs it on unscaled time, for the camera.
function Core:Run(Fn: (Delta: number, Age: number) -> boolean, Real: boolean?)
	if not self._Connection then
		self._Connection = RunService.Heartbeat:Connect(function(Delta: number)
			self:_Step(Delta)
		end)
	end

	table.insert(self._Jobs, { Fn = Fn, Age = 0, Real = Real == true })
end

function Core:After(Delay: number, Fn: () -> (), Real: boolean?)
	self:Run(function(_Delta: number, Age: number): boolean
		if Age < Delay then
			return true
		end

		Fn()

		return false
	end, Real)
end

function Core:Hitstop(Seconds: number)
	self._Hitstop = math.max(self._Hitstop, Seconds)
end

--> Everything gone and the clock back to normal, for the end of a review.
function Core:Clear()
	table.clear(self._Jobs)
	table.clear(self._Emitters)

	GetFolder():ClearAllChildren()

	for Attachment in self._Attachments do
		Attachment:Destroy()
	end

	table.clear(self._Attachments)

	self._Hitstop = 0
	self.TimeScale = 1
	self.PauseAt = nil
end

--> A NumberSequence: one value, evenly spaced values, or a list of { Time, Value, Envelope? }.
function Core.Ns(...: any): NumberSequence
	local Values = { ... }

	if type(Values[1]) == "table" then
		local Points = {}

		for _, Point in Values[1] do
			table.insert(Points, NumberSequenceKeypoint.new(Point[1], Point[2], Point[3] or 0))
		end

		return NumberSequence.new(Points)
	end

	if #Values == 1 then
		return NumberSequence.new(Values[1])
	end

	local Points = {}

	for Index, Value in Values do
		table.insert(Points, NumberSequenceKeypoint.new((Index - 1) / (#Values - 1), Value))
	end

	return NumberSequence.new(Points)
end

function Core.Cs(...: Color3): ColorSequence
	local Colors = { ... }

	if #Colors == 1 then
		return ColorSequence.new(Colors[1])
	end

	local Points = {}

	for Index, Color in Colors do
		table.insert(Points, ColorSequenceKeypoint.new((Index - 1) / (#Colors - 1), Color))
	end

	return ColorSequence.new(Points)
end

function Core.Nr(Min: number, Max: number?): NumberRange
	return NumberRange.new(Min, Max or Min)
end

--> A frame whose +Y points along Direction, for rings drawn VelocityPerpendicular.
function Core.Facing(Position: Vector3, Direction: Vector3): CFrame
	if math.abs(Direction.Unit:Dot(Vector3.yAxis)) > 0.99 then
		return CFrame.new(Position)
	end

	return CFrame.lookAt(Position, Position + Direction) * CFrame.Angles(-math.pi / 2, 0, 0)
end

--> One burst: an attachment where it goes, an emitter set up off Props, Count particles, and both
--> gone once the last particle is.
function Core:Emit(At: CFrame | Vector3, Props: { [string]: any }, Count: number?)
	local Attachment = Instance.new("Attachment")
	Attachment.WorldCFrame = if typeof(At) == "Vector3" then CFrame.new(At) else At

	local Emitter = Instance.new("ParticleEmitter")
	Emitter.Enabled = false
	Emitter.LightEmission = 1
	Emitter.LightInfluence = 0
	Emitter.Speed = NumberRange.new(0)
	Emitter.Rotation = NumberRange.new(0, 360)

	for Key, Value in Props do
		(Emitter :: any)[Key] = Value
	end

	Emitter.TimeScale = self._LastScale
	Emitter.Parent = Attachment
	Attachment.Parent = workspace.Terrain
	self._Attachments[Attachment] = true

	self._Emitters[Emitter] = true
	Emitter:Emit(Count or 1)

	self:After(Emitter.Lifetime.Max + 0.25, function()
		self._Emitters[Emitter] = nil
		self._Attachments[Attachment] = nil
		Attachment:Destroy()
	end)
end

--> A solid flash over a character, the cartoon "got hit" frame. Real time.
function Core:Silhouette(Model: Model, Fill: Color3, Seconds: number)
	local Flash = Instance.new("Highlight")
	Flash.Adornee = Model
	Flash.DepthMode = Enum.HighlightDepthMode.Occluded
	Flash.FillColor = Fill
	Flash.FillTransparency = 0
	Flash.OutlineColor = Fill
	Flash.OutlineTransparency = 0
	Flash.Parent = GetFolder()

	self:After(Seconds, function()
		Flash:Destroy()
	end, true)
end

function Core:FlashLight(Position: Vector3, Color: Color3, Range: number, Brightness: number, Life: number)
	local Attachment = Instance.new("Attachment")
	Attachment.WorldPosition = Position

	local Light = Instance.new("PointLight")
	Light.Color = Color
	Light.Range = Range
	Light.Brightness = Brightness
	Light.Shadows = false
	Light.Parent = Attachment
	Attachment.Parent = workspace.Terrain
	self._Attachments[Attachment] = true

	self:Run(function(_Delta: number, Age: number): boolean
		local Done = math.clamp(Age / Life, 0, 1)

		Light.Brightness = Brightness * (1 - Done) ^ 2

		if Done < 1 then
			return true
		end

		self._Attachments[Attachment] = nil
		Attachment:Destroy()

		return false
	end)
end

--> A kick through Humanoid.CameraOffset and the field of view, both written as deltas so nothing
--> builds up in the aim. Only ever for the local player.
function Core:CameraHit(Shake: number, Seconds: number, Fov: number)
	local Character = Players.LocalPlayer and Players.LocalPlayer.Character
	local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
	local Camera = workspace.CurrentCamera

	if not Humanoid or not Camera then
		return
	end

	local LastOffset = Vector3.zero
	local LastFov = 0

	self:Run(function(_Delta: number, Age: number): boolean
		local Done = math.clamp(Age / Seconds, 0, 1)
		local Offset = if Done < 1 then Draw:NextUnitVector() * Shake * (1 - Done) ^ 2 else Vector3.zero
		local Kick = if Done < 1 then Fov * math.exp(-Age * 9) * math.cos(Age * 16) else 0

		Humanoid.CameraOffset += Offset - LastOffset
		Camera.FieldOfView += Kick - LastFov

		LastOffset = Offset
		LastFov = Kick

		return Done < 1
	end, true)
end

--> The floor under a point: where, which way it faces, and what it is made of, for dust and chunks
--> that match it. Nothing within reach is a guess a few studs down.
function Core.Ground(Position: Vector3, Exclude: { Instance }?): Ground
	local Params = RaycastParams.new()
	local Ignore: { Instance } = { GetFolder() }

	if Exclude then
		table.move(Exclude, 1, #Exclude, 2, Ignore)
	end

	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = Ignore
	Params.RespectCanCollide = true

	local Result = workspace:Raycast(Position + Vector3.new(0, GroundLift, 0), Vector3.new(0, -GroundReach, 0), Params)

	if not Result then
		return {
			Position = Position - Vector3.new(0, 3, 0),
			Normal = Vector3.yAxis,
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(99, 95, 98),
		}
	end

	local Hit = Result.Instance

	return {
		Position = Result.Position,
		Normal = Result.Normal,
		Material = Result.Material,
		Color = if Hit:IsA("BasePart") and Hit ~= workspace.Terrain then Hit.Color else Color3.fromRGB(99, 95, 98),
	}
end

--> Chunks thrown up off the floor that bounce three times and shrink away. Moved by hand, not by
--> physics, so they freeze with the clock and never shove anyone.
function Core:Debris(Floor: Ground, Count: number, Scale: number, Push: Vector3?)
	local Gravity = 150

	for _ = 1, Count do
		local Size = Draw:NextNumber(0.45, 1.2) * Scale
		local Chunk = Instance.new("Part")
		Chunk.Size = Vector3.new(Size, Size * Draw:NextNumber(0.6, 1), Size * Draw:NextNumber(0.7, 1.2))
		Chunk.Material = Floor.Material
		Chunk.Color = Floor.Color:Lerp(Color3.new(1, 1, 1), Draw:NextNumber(0, 0.18))
		Chunk.Anchored = true
		Chunk.CanCollide = false
		Chunk.CanQuery = false
		Chunk.CanTouch = false
		Chunk.CastShadow = false

		local Full = Chunk.Size

		local Angle = Draw:NextNumber(0, math.pi * 2)
		local Velocity = Vector3.new(math.cos(Angle), 0, math.sin(Angle)) * Draw:NextNumber(14, 34)
			+ Vector3.new(0, Draw:NextNumber(28, 52), 0)
			+ (Push or Vector3.zero) * Draw:NextNumber(0.5, 1)
		local Position = Floor.Position + Vector3.new(0, 0.5, 0)
		local Rotation = CFrame.Angles(Draw:NextNumber(0, 6), Draw:NextNumber(0, 6), Draw:NextNumber(0, 6))
		local Spin = Draw:NextUnitVector() * Draw:NextNumber(8, 18)
		local Rest = Floor.Position.Y + Size * 0.3
		local Bounces = 0
		local Life = Draw:NextNumber(1.2, 1.6)

		Chunk.CFrame = CFrame.new(Position) * Rotation
		Chunk.Parent = GetFolder()

		self:Run(function(Delta: number, Age: number): boolean
			if Delta > 0 and Bounces < 3 then
				Velocity -= Vector3.new(0, Gravity * Delta, 0)
				Position += Velocity * Delta
				Rotation = CFrame.fromAxisAngle(Spin.Unit, Spin.Magnitude * Delta) * Rotation

				if Position.Y < Rest then
					Position = Vector3.new(Position.X, Rest, Position.Z)
					Bounces += 1
					Velocity = Vector3.new(Velocity.X * 0.55, -Velocity.Y * 0.3, Velocity.Z * 0.55)
					Spin *= 0.5
				end
			end

			local Shrink = math.clamp((Age - Life) / 0.3, 0, 1)

			Chunk.Size = Full * (1 - Shrink) + Vector3.new(0.01, 0.01, 0.01)
			Chunk.CFrame = CFrame.new(Position) * Rotation

			if Shrink < 1 then
				return true
			end

			Chunk:Destroy()

			return false
		end)
	end
end

--> A flat image lying on the floor that fades out: a scorch, a splat. Glow ignores the lighting.
function Core:GroundMark(
	Floor: Ground,
	Texture: string,
	Size: number,
	Color: Color3,
	Alpha: number,
	Life: number,
	Glow: boolean?
)
	local Fade = math.min(0.8, Life / 2)

	local Holder = Instance.new("Part")
	Holder.Size = Vector3.new(Size, 0.05, Size)
	Holder.Transparency = 1
	Holder.Anchored = true
	Holder.CanCollide = false
	Holder.CanQuery = false
	Holder.CanTouch = false
	--> marks only ever go on floors, so the floor is taken to face up
	Holder.CFrame = CFrame.new(Floor.Position + Vector3.new(0, 0.06, 0))
		* CFrame.Angles(0, Draw:NextNumber(0, math.pi * 2), 0)

	local Gui = Instance.new("SurfaceGui")
	Gui.Face = Enum.NormalId.Top
	Gui.CanvasSize = Vector2.new(512, 512)
	Gui.LightInfluence = if Glow then 0 else 1
	Gui.Parent = Holder

	local Image = Instance.new("ImageLabel")
	Image.BackgroundTransparency = 1
	Image.Size = UDim2.fromScale(1, 1)
	Image.Image = Texture
	Image.ImageColor3 = Color
	Image.ImageTransparency = Alpha
	Image.Parent = Gui

	Holder.Parent = GetFolder()

	self:Run(function(_Delta: number, Age: number): boolean
		local Done = math.clamp((Age - (Life - Fade)) / Fade, 0, 1)

		Image.ImageTransparency = Alpha + (1 - Alpha) * Done

		if Done < 1 then
			return true
		end

		Holder:Destroy()

		return false
	end)
end

return Core
