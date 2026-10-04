local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Core = require(Shared.VFX.Core)
local Textures = require(Shared.VFX.Textures)

--> What every gear looks like when it does its thing, built out of Core's blocks on the client. The
--> server says what happened and where; this draws it. Scaled to a character about five studs tall
--> and kept cartoony: this is an office, not a battleground, so nothing here covers the screen.
--> Hit-stop and the camera kick are only ever for the local player's own hit.

local Ns, Cs, Nr = Core.Ns, Core.Cs, Core.Nr
local Draw = Core.Draw

local White = Color3.new(1, 1, 1)

local Settings = {
	Swing = {
		Color = Color3.fromRGB(255, 245, 220),
		Reach = 3.5,
		Size = 7,
	},
	Bonk = {
		Color = Color3.fromRGB(255, 225, 90),
		Deep = Color3.fromRGB(255, 150, 40),
		HitStop = 0.07,
		Shake = 0.25,
		Fov = 3,
	},
	Blast = {
		Color = Color3.fromRGB(255, 150, 40),
		Hot = Color3.fromRGB(255, 235, 150),
		Deep = Color3.fromRGB(200, 60, 20),
		Smoke = Color3.fromRGB(165, 158, 150),
		Scorch = Color3.fromRGB(20, 16, 14),
		--> a blast shakes the camera of anyone within this many radii of it, harder the closer
		ShakeReach = 2.5,
		Shake = 0.7,
		Fov = 5,
	},
	Goo = {
		Color = Color3.fromRGB(110, 235, 70),
		Deep = Color3.fromRGB(40, 150, 30),
	},
	Snap = {
		Spark = Color3.fromRGB(255, 240, 190),
		Ice = Color3.fromRGB(140, 215, 255),
	},
	Gulp = {
		Color = Color3.fromRGB(255, 215, 80),
	},
	Cloak = {
		Color = Color3.fromRGB(170, 120, 255),
		Deep = Color3.fromRGB(90, 50, 170),
	},
}

local function Chest(Model: Model?): Vector3?
	local Root = Model and Model:FindFirstChild("HumanoidRootPart")

	return if Root and Root:IsA("BasePart") then Root.Position + Vector3.new(0, 0.6, 0) else nil
end

--> A ring of smoke puffs thrown out along the floor, the dust a thing kicks up when it lands.
local function DustRing(At: Vector3, Count: number, Speed: number, Size: number, Color: Color3, Life: number)
	for Index = 1, Count do
		local Angle = Index / Count * math.pi * 2
		local Out = Vector3.new(math.cos(Angle), 0.1, math.sin(Angle))
		local From = At + Vector3.new(0, 0.6, 0)

		Core:Emit(CFrame.lookAt(From, From + Out), {
			Texture = Textures.Smoke,
			LightEmission = 0,
			LightInfluence = 1,
			EmissionDirection = Enum.NormalId.Front,
			SpreadAngle = Vector2.new(10, 6),
			Speed = Nr(Speed * 0.7, Speed),
			Drag = 4.5,
			RotSpeed = Nr(-50, 50),
			Color = Cs(Color),
			Size = Ns({ { 0, Size * 0.4 }, { 1, Size } }),
			Transparency = Ns({ { 0, 0.45 }, { 0.5, 0.7 }, { 1, 1 } }),
			Lifetime = Nr(Life * 0.75, Life),
		}, 1)
	end
end

--> A flat ring spreading out over the floor.
local function FloorRing(At: Vector3, Color: Color3, From: number, To: number, Life: number)
	Core:Emit(Core.Facing(At + Vector3.new(0, 0.2, 0), Vector3.yAxis), {
		Texture = Textures.HardRing,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = Nr(0.01),
		Rotation = Nr(0),
		Color = Cs(Color),
		Brightness = 2,
		Size = Ns({ { 0, From }, { 1, To } }),
		Transparency = Ns({ { 0, 0.1 }, { 1, 1 } }),
		Lifetime = Nr(Life),
	}, 1)
end

--> Little flecks thrown out of a point in a cone around Direction, falling as they go.
local function Sparks(At: Vector3, Direction: Vector3, Color: Color3, Count: number, Speed: number, Spread: number)
	Core:Emit(Core.Facing(At, Direction), {
		Texture = Textures.Streak,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(Spread, Spread),
		Speed = Nr(Speed * 0.4, Speed),
		Drag = 5,
		Acceleration = Vector3.new(0, -40, 0),
		Rotation = Nr(0),
		Color = Cs(White, Color),
		Brightness = 3,
		Size = Ns({ { 0, 1 }, { 1, 0.2 } }),
		Transparency = Ns(0, 0, 1),
		Lifetime = Nr(0.2, 0.4),
	}, Count)
end

--> Blobs thrown up and out that fall back down: goo, mostly.
local function Droplets(At: Vector3, Color: Color3, Count: number, Size: number)
	Core:Emit(Core.Facing(At, Vector3.yAxis), {
		Texture = Textures.Glow,
		LightEmission = 0.3,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(70, 70),
		Speed = Nr(10, 22),
		Acceleration = Vector3.new(0, -70, 0),
		Color = Cs(Color),
		Size = Ns(Size, Size * 0.5),
		Transparency = Ns({ { 0, 0.05 }, { 0.8, 0.2 }, { 1, 1 } }),
		Lifetime = Nr(0.45, 0.7),
	}, Count)
end

local Gears = {
	Name = "Gears",
	Settings = Settings,
}

--> The bat going round: a crescent in front of the swinger and a few streaks along it. Drawn the
--> moment the swinger clicks on their own screen, and off the server's word on everyone else's.
function Gears.Swing(Model: Model, Strength: number)
	local Root = Model:FindFirstChild("HumanoidRootPart")

	if not Root or not Root:IsA("BasePart") then
		return
	end

	local Setting = Settings.Swing
	local Look = Root.CFrame.LookVector
	local At = Root.Position + Look * Setting.Reach + Vector3.new(0, 0.5, 0)

	Core:Emit(CFrame.lookAt(At, At + Look), {
		Texture = Textures.Slash,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = Cs(White, Setting.Color),
		Brightness = 1.6,
		Rotation = Nr(-30, -10),
		Size = Ns(Setting.Size * Strength),
		Transparency = Ns({ { 0, 0.15 }, { 0.7, 0.35 }, { 1, 1 } }),
		Lifetime = Nr(0.2),
	}, 1)

	for Index = 1, 3 do
		Core:After((Index - 1) * 0.03, function()
			local Side = Root.CFrame.RightVector * Draw:NextNumber(-1.5, 1.5)
			local From = At + Side + Vector3.new(0, Draw:NextNumber(-0.6, 0.6), 0)

			Core:Emit(CFrame.lookAt(From, From + Root.CFrame.RightVector), {
				Texture = Textures.Streak,
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				EmissionDirection = Enum.NormalId.Front,
				Speed = Nr(14, 20),
				Rotation = Nr(0),
				Color = Cs(White, Setting.Color),
				Brightness = 2,
				Size = Ns(2.4, 0.6),
				Transparency = Ns(0.2, 1),
				Lifetime = Nr(0.12, 0.16),
			}, 1)
		end)
	end
end

--> A bat connecting: the victim flashes white, a bonk star and a ring of sparks go off on them and
--> the floor under their feet puffs. Mine is the swing that landed, which earns the hit-stop and
--> the kick; Strength is 1 for the wooden bat and more for the steel one.
function Gears.Bonk(Target: Model?, At: Vector3, Direction: Vector3, Strength: number, Mine: boolean)
	local Setting = Settings.Bonk
	local Hit = Chest(Target) or At

	if Target then
		Core:Silhouette(Target, White, 0.08)
	end

	if Mine then
		Core:Hitstop(Setting.HitStop * Strength)
		Core:CameraHit(Setting.Shake * Strength, 0.25, Setting.Fov * Strength)
	end

	Core:FlashLight(Hit, Setting.Color, 14, 4, 0.25)

	Core:Emit(Hit, {
		Texture = Textures.StarGlint,
		Color = Cs(White),
		Brightness = 4,
		ZOffset = 1,
		Rotation = Nr(0, 30),
		Size = Ns({ { 0, 1 }, { 0.3, 5 * Strength }, { 1, 0 } }),
		Transparency = Ns(0),
		Lifetime = Nr(0.22),
	}, 1)

	Core:After(0.04, function()
		Core:Emit(Hit, {
			Texture = Textures.SparkBurst,
			Color = Cs(Setting.Color, Setting.Deep),
			Brightness = 1.5,
			Size = Ns({ { 0, 4 * Strength }, { 1, 8 * Strength } }),
			Transparency = Ns({ { 0, 0.2 }, { 1, 1 } }),
			Lifetime = Nr(0.18),
		}, 1)
	end)

	Core:Emit(Core.Facing(Hit, Direction), {
		Texture = Textures.SoftRing,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = Nr(0.01),
		Rotation = Nr(0),
		Color = Cs(White, Setting.Color),
		Brightness = 2,
		Size = Ns({ { 0, 1 }, { 1, 5 * Strength } }),
		Transparency = Ns(0.35, 1),
		Lifetime = Nr(0.25),
	}, 1)

	Sparks(Hit, (Direction + Vector3.new(0, 0.6, 0)).Unit, Setting.Color, math.round(12 * Strength), 45, 60)

	local Floor = Core.Ground(Hit, if Target then { Target } else nil)

	DustRing(Floor.Position, 8, 18 * Strength, 4, Color3.fromRGB(215, 215, 220), 0.8)
end

--> A bomb or a stick of tnt going off. Radius is the blast's own, so the bigger one looks bigger.
--> Anyone close enough gets their camera kicked, harder the nearer they stood.
function Gears.Blast(At: Vector3, Radius: number, Near: number?)
	local Setting = Settings.Blast
	local Scale = Radius / 14
	local Floor = Core.Ground(At)

	Core:FlashLight(At + Vector3.new(0, 2, 0), Setting.Color, Radius * 1.5, 3, 0.4)

	if Near then
		local Closeness = 1 - math.clamp(Near / (Radius * Setting.ShakeReach), 0, 1)

		if Closeness > 0 then
			Core:CameraHit(Setting.Shake * Closeness, 0.45, Setting.Fov * Closeness)
		end
	end

	--> back to front: rays, the hot core, then the fireball rolling out of it
	Core:Emit(At, {
		Texture = Textures.Rays,
		Color = Cs(Setting.Hot, Setting.Color),
		Brightness = 1.6,
		ZOffset = -0.5,
		Size = Ns({ { 0, 6 * Scale }, { 1, 16 * Scale } }),
		Transparency = Ns({ { 0, 0.15 }, { 0.6, 0.5 }, { 1, 1 } }),
		Lifetime = Nr(0.18),
	}, 1)

	Core:Emit(At, {
		Texture = Textures.Glow,
		Color = Cs(White, Setting.Hot, Setting.Color),
		Brightness = 3,
		Size = Ns({ { 0, 5 * Scale }, { 0.3, 11 * Scale }, { 1, 8 * Scale } }),
		Transparency = Ns({ { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }),
		Lifetime = Nr(0.3),
	}, 1)

	Core:After(0.045, function()
		Core:Emit(At + Vector3.new(0, 1, 0), {
			Texture = Textures.Smoke,
			LightEmission = 1,
			LightInfluence = 0,
			Brightness = 1.2,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(180, 180),
			Speed = Nr(14 * Scale, 26 * Scale),
			Drag = 4,
			RotSpeed = Nr(-90, 90),
			Color = Cs(Setting.Color, Setting.Deep, Setting.Deep),
			Size = Ns({ { 0, 2.5 * Scale }, { 1, 5 * Scale } }),
			Transparency = Ns({ { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } }),
			Lifetime = Nr(0.4, 0.6),
		}, 14)
	end)

	--> what is left hanging after the fire has gone
	Core:After(0.15, function()
		Core:Emit(At + Vector3.new(0, 1.5, 0), {
			Texture = Textures.Smoke,
			LightEmission = 0,
			LightInfluence = 1,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(180, 180),
			Speed = Nr(8 * Scale, 14 * Scale),
			Drag = 2,
			Acceleration = Vector3.new(0, 3, 0),
			RotSpeed = Nr(-40, 40),
			Color = Cs(Setting.Smoke),
			Size = Ns({ { 0, 2.5 * Scale }, { 1, 6 * Scale } }),
			Transparency = Ns({ { 0, 0.55 }, { 0.6, 0.75 }, { 1, 1 } }),
			Lifetime = Nr(1.2, 1.8),
		}, 10)
	end)

	FloorRing(Floor.Position, Setting.Color, 2, Radius * 2, 0.35)
	DustRing(Floor.Position, 12, 34 * Scale, 9 * Scale, Color3.fromRGB(200, 195, 190), 1.2)
	Sparks(At, Vector3.yAxis, Setting.Hot, math.round(26 * Scale), 70 * Scale, 80)
	Core:Debris(Floor, math.round(8 * Scale), 0.8 * Scale)
	Core:GroundMark(Floor, Textures.GroundCrack, Radius * 1.1, Setting.Scorch, 0.35, 4)
	Core:GroundMark(Floor, Textures.GroundCrack, Radius * 1.1, Setting.Color, 0, 0.4, true)
end

--> The goo ball coming down: a splash of droplets and a ring where the puddle spreads from. A player
--> it hit square flashes green with it.
function Gears.Splat(At: Vector3, Target: Model?)
	local Setting = Settings.Goo

	if Target then
		Core:Silhouette(Target, Setting.Color, 0.12)
	end

	Droplets(At + Vector3.new(0, 0.3, 0), Setting.Color, 18, 0.7)
	FloorRing(At, Setting.Color, 1, 11, 0.3)

	Core:Emit(At + Vector3.new(0, 0.5, 0), {
		Texture = Textures.Glow,
		LightEmission = 0.4,
		Color = Cs(Setting.Color, Setting.Deep),
		Size = Ns({ { 0, 2 }, { 1, 6 } }),
		Transparency = Ns({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = Nr(0.25),
	}, 1)
end

--> The trap shutting on someone: metal sparks off the jaws, a cold ring along the floor and the one
--> caught flashing ice blue.
function Gears.Snap(At: Vector3, Target: Model?)
	local Setting = Settings.Snap

	if Target then
		Core:Silhouette(Target, Setting.Ice, 0.15)
	end

	Sparks(At + Vector3.new(0, 0.4, 0), Vector3.yAxis, Setting.Spark, 16, 40, 70)
	FloorRing(At, Setting.Ice, 1, 10, 0.35)

	Core:Emit(At + Vector3.new(0, 0.5, 0), {
		Texture = Textures.StarGlint,
		Color = Cs(White),
		Brightness = 4,
		Size = Ns({ { 0, 1 }, { 0.3, 4 }, { 1, 0 } }),
		Transparency = Ns(0),
		Lifetime = Nr(0.2),
	}, 1)

	DustRing(At, 8, 14, 3, Setting.Ice, 0.9)
end

--> The speed potion going down: sparkles rising round the drinker and a ring at their feet.
function Gears.Gulp(Model: Model)
	local Setting = Settings.Gulp
	local At = Chest(Model)

	if not At then
		return
	end

	Core:Silhouette(Model, Setting.Color, 0.1)
	FloorRing(At - Vector3.new(0, 3, 0), Setting.Color, 1, 8, 0.3)

	Core:Emit(Core.Facing(At - Vector3.new(0, 2.5, 0), Vector3.yAxis), {
		Texture = Textures.StarSoft,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(25, 25),
		Speed = Nr(6, 12),
		Drag = 2,
		Rotation = Nr(0, 90),
		Color = Cs(White, Setting.Color),
		Brightness = 2,
		Size = Ns({ { 0, 0.2 }, { 0.3, 1 }, { 1, 0 } }),
		Transparency = Ns(0),
		Lifetime = Nr(0.5, 0.8),
	}, 14)
end

--> The cloak going on or coming off: a purple poof and a few glints in it.
function Gears.Cloak(At: Vector3)
	local Setting = Settings.Cloak

	Core:Emit(At, {
		Texture = Textures.Smoke,
		LightEmission = 0.3,
		LightInfluence = 0.5,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(180, 180),
		Speed = Nr(6, 12),
		Drag = 5,
		RotSpeed = Nr(-60, 60),
		Color = Cs(Setting.Color, Setting.Deep),
		Size = Ns({ { 0, 2 }, { 1, 5 } }),
		Transparency = Ns({ { 0, 0.2 }, { 1, 1 } }),
		Lifetime = Nr(0.5, 0.8),
	}, 12)

	Core:Emit(At, {
		Texture = Textures.StarSoft,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(180, 180),
		Speed = Nr(5, 10),
		Drag = 3,
		Color = Cs(White, Setting.Color),
		Brightness = 2,
		Size = Ns({ { 0, 0.3 }, { 0.3, 1.2 }, { 1, 0 } }),
		Transparency = Ns(0),
		Lifetime = Nr(0.4, 0.6),
	}, 8)
end

return Gears
