local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared

local GearConfigs = require(Shared.Configs.Gears)
local NetworkingServer = require(Shared.Networking.networkingServer)
local SoundConfigs = require(Shared.Configs.Sounds)
local StatusService = require(ServerScriptService.Server.Services.StatusService)

--> What each gear does when it is used, keyed like Configs.Gears. Run on the server, off a use
--> GearService has already checked, so nothing here asks whether the player owns the thing or
--> is holding it. Nothing here takes health: bats and bombs fling, goo slows, the trap freezes,
--> the cloak hides, the potion speeds up. Every one of them makes a sound where it happens, and
--> whoever it lands on gets a kick on their screen.

export type Context = {
	Player: Player,
	Character: Model,
	Root: BasePart,

	--> where the mouse was, for the ones that are thrown
	Aim: Vector3?,
}

type Effect = (Context: Context) -> ()

--> A swing reaches this far, and only counts in front: the dot of the two directions past this.
local SwingRange = 9
local SwingCone = 0.2

--> studs per second sideways and up for each bat, and the kick the screen gets
local WoodenPower = 55
local SteelPower = 105
local SwingLift = 0.55
local SwingShake = 1.2

--> the bomb: where it sits, how long it burns, how far the blast reaches and how hard it throws
local BombDrop = Vector3.new(0, -2.5, 0)
local BombFuse = 2.5
local BombRadius = 14
local BombPower = 80

--> the tnt: thrown at the aim with this much speed and this much lift, then the bigger blast
local ThrowSpeed = 90
local ThrowLift = 25
local TNTFuse = 2
local TNTRadius = 22
local TNTPower = 125

--> the blast's lift over its sideways push, so nobody is shoved along the floor, and the kick
local BlastLift = 0.7
local BlastShake = 2

--> goo: the ball thrown, how long it may fly before it splats on its own, the puddle it leaves,
--> how long that lies there, how slow it makes you and for how long after a touch
local GooSpeed = 70
local GooLift = 22
local GooFlight = 3
local GooSize = Vector3.new(9, 0.4, 9)
local GooLife = 20
local GooFactor = 0.4
local GooSlow = 4
local GooShake = 0.4

--> how long the puddle takes to spread out to its full size
local SplatTween = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--> the trap: how long it waits armed, how long it holds whoever steps on it, and the kick
local TrapSize = Vector3.new(3, 0.5, 3)
local TrapLife = 60
local TrapHold = 4
local TrapShake = 1

--> the countdown over a frozen head: how big, how high, and what it is drawn in
local CountSize = UDim2.fromScale(4, 1.6)
local CountOffset = Vector3.new(0, 3.2, 0)
local CountFace = Font.new("rbxassetid://11598289817", Enum.FontWeight.Heavy)
local CountColor = Color3.fromRGB(140, 220, 255)
local FreezeColor = Color3.fromRGB(120, 200, 255)

local PotionFactor = 1.5
local PotionTime = 15

local CloakTime = 10

--> how long a burst of particles is switched on for: Emit does not replicate, Enabled does
local BurstTime = 0.15

--> the fuse: how many sparks a second and the light they throw, and how fast a thrown stick tumbles
local SparkRate = 45
local SparkColor = Color3.fromRGB(255, 190, 80)
local FuseLight = 6
local TumbleSpeed = 14

--> the smoke a blast leaves and the sparks a trap throws
local SmokeColor = Color3.fromRGB(90, 90, 95)
local BonkColor = Color3.fromRGB(255, 240, 150)

--> the slowed: tinted green for as long as the goo has them
local GooTint = Color3.fromRGB(110, 230, 80)

--> the parts the effects leave in the world, so a sweep could find them
local EffectsFolderName = "GearEffects"

--> how long a world sound is kept around after it is started, whatever its length
local SoundLifetime = 8

local Draw = Random.new()

local function GetFolder(): Folder
	local Folder = workspace:FindFirstChild(EffectsFolderName)

	if Folder and Folder:IsA("Folder") then
		return Folder
	end

	local New = Instance.new("Folder")
	New.Name = EffectsFolderName
	New.Parent = workspace

	return New
end

local function GetRoot(Player: Player): BasePart?
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	return if Root and Root:IsA("BasePart") then Root else nil
end

--> The player a part belongs to, for something that touched a puddle, a trap or a thrown ball.
local function GetToucher(Hit: BasePart): Player?
	local Character = Hit:FindFirstAncestorOfClass("Model")

	return if Character then Players:GetPlayerFromCharacter(Character) else nil
end

--> A sound out of the gear table, built where it is played. Hung off the part, or off an
--> attachment on the terrain for a place with no part left at it.
local function PlaySound(Name: string, At: BasePart | Vector3): Sound?
	local Effect = SoundConfigs.Gear[Name]

	if not Effect or Effect.Id == "" then
		return nil
	end

	local Sound = Instance.new("Sound")
	Sound.Name = `Gear_{Name}`
	Sound.SoundId = "rbxassetid://" .. Effect.Id
	Sound.Volume = Effect.Volume or SoundConfigs.Volume
	Sound.Looped = Effect.Loop == true

	local Speed = Effect.Speed or 1
	local Spread = Effect.Spread or 0

	Sound.PlaybackSpeed = Speed * (1 + Draw:NextNumber(-Spread, Spread))

	if Effect.Range then
		Sound.RollOffMode = Enum.RollOffMode.Linear
		Sound.RollOffMinDistance = math.min(10, Effect.Range)
		Sound.RollOffMaxDistance = Effect.Range
	end

	if typeof(At) == "Vector3" then
		local Point = Instance.new("Attachment")
		Point.Name = Sound.Name
		Point.Parent = workspace.Terrain
		Point.WorldPosition = At
		Sound.Parent = Point

		Debris:AddItem(Point, SoundLifetime)
	else
		Sound.Parent = At

		if not Sound.Looped then
			Debris:AddItem(Sound, SoundLifetime)
		end
	end

	Sound:Play()

	return Sound
end

--> The kick on a player's screen. Only for the one it landed on.
local function Kick(Player: Player, Strength: number)
	NetworkingServer.Gears.Hit.Fire(Player, Strength)
end

--> A puff of particles in a colour, switched on for a moment. Enabled replicates; Emit does not.
local function Puff(Part: BasePart, Color: Color3, Rate: number, Size: number, Speed: number)
	local Emitter = Instance.new("ParticleEmitter")
	Emitter.Color = ColorSequence.new(Color)
	Emitter.Rate = Rate
	Emitter.Lifetime = NumberRange.new(0.4, 0.8)
	Emitter.Speed = NumberRange.new(Speed * 0.5, Speed)
	Emitter.SpreadAngle = Vector2.new(180, 180)
	Emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	Emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	Emitter.Enabled = true
	Emitter.Parent = Part

	task.delay(BurstTime, function()
		Emitter.Enabled = false
	end)
end

--> Sparks off a lit thing, and a light with them, for as long as it is there.
local function Sparks(Part: BasePart)
	local Emitter = Instance.new("ParticleEmitter")
	Emitter.Name = "Sparks"
	Emitter.Color = ColorSequence.new(SparkColor)
	Emitter.LightEmission = 1
	Emitter.Rate = SparkRate
	Emitter.Lifetime = NumberRange.new(0.25, 0.5)
	Emitter.Speed = NumberRange.new(4, 8)
	Emitter.SpreadAngle = Vector2.new(180, 180)
	Emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	Emitter.Parent = Part

	local Light = Instance.new("PointLight")
	Light.Color = SparkColor
	Light.Brightness = 2
	Light.Range = FuseLight
	Light.Parent = Part
end

--> A puff at a spot with no part at it: a clear anchored one is stood there for the burst.
local function PuffAt(Position: Vector3, Color: Color3, Rate: number, Size: number, Speed: number)
	local Holder = Instance.new("Part")
	Holder.Name = "Puff"
	Holder.Size = Vector3.one
	Holder.Transparency = 1
	Holder.Anchored = true
	Holder.CanCollide = false
	Holder.CanQuery = false
	Holder.CanTouch = false
	Holder.Position = Position
	Holder.Parent = GetFolder()

	Puff(Holder, Color, Rate, Size, Speed)
	Debris:AddItem(Holder, 2)
end

--> The slowed wear the goo for as long as it has them.
local function Tint(Player: Player, Color: Color3, Seconds: number)
	local Character = Player.Character

	if not Character then
		return
	end

	local Glow = Instance.new("Highlight")
	Glow.Name = "Gooed"
	Glow.FillColor = Color
	Glow.FillTransparency = 0.6
	Glow.OutlineColor = Color
	Glow.DepthMode = Enum.HighlightDepthMode.Occluded
	Glow.Parent = Character

	Debris:AddItem(Glow, Seconds)
end

--> Everyone within Radius of a point is thrown away from it, the one who lit it included: a
--> bomb dropped at your own feet is your problem too.
local function Blast(_Owner: Player, Position: Vector3, Radius: number, Power: number)
	for _, Other in Players:GetPlayers() do
		local Root = GetRoot(Other)

		if not Root then
			continue
		end

		local Away = Root.Position - Position
		local Distance = Away.Magnitude

		if Distance > Radius then
			continue
		end

		local Flat = Vector3.new(Away.X, 0, Away.Z)
		local Direction = if Flat.Magnitude > 0.1 then Flat.Unit else Vector3.zAxis

		--> harder the closer they stood, never less than half
		local Falloff = 1 - (Distance / Radius) * 0.5

		StatusService:Fling(Other, (Direction + Vector3.new(0, BlastLift, 0)) * Power * Falloff)
		Kick(Other, BlastShake * Falloff)
	end
end

--> The bang itself: an explosion that pushes nothing and breaks nothing, for the look, the sound
--> played at the spot, and the throw done by hand around it.
local function Explode(Owner: Player, Position: Vector3, Radius: number, Power: number)
	local Explosion = Instance.new("Explosion")
	Explosion.Position = Position
	Explosion.BlastRadius = Radius
	Explosion.BlastPressure = 0
	Explosion.DestroyJointRadiusPercent = 0
	Explosion.Parent = workspace

	PlaySound("Explode", Position)
	PuffAt(Position, SmokeColor, 400, Radius * 0.35, Radius * 0.9)
	Blast(Owner, Position, Radius, Power)
end

--> The gear's own model out of the place, for the thing thrown or dropped: the bomb that lands is
--> the bomb that was in the hand. A handle that is not there falls back to a plain part.
local function BuildFromGear(Key: string, Size: Vector3, Color: Color3): BasePart
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local Folder = Assets and Assets:FindFirstChild(GearConfigs.Folder)
	local Tool = Folder and Folder:FindFirstChild(Key)
	local Handle = Tool and Tool:FindFirstChild("Handle")

	if not Handle or not Handle:IsA("BasePart") then
		local Part = Instance.new("Part")
		Part.Name = Key
		Part.Size = Size
		Part.Color = Color
		Part.Material = Enum.Material.SmoothPlastic

		return Part
	end

	local Copy = Handle:Clone()
	Copy.Name = Key
	Copy.Anchored = false
	Copy.CanCollide = true
	Copy.CanTouch = true
	Copy.Massless = false

	return Copy
end

local function BuildPart(Name: string, Size: Vector3, Color: Color3): Part
	local Part = Instance.new("Part")
	Part.Name = Name
	Part.Size = Size
	Part.Color = Color
	Part.Material = Enum.Material.SmoothPlastic
	Part.TopSurface = Enum.SurfaceType.Smooth
	Part.BottomSurface = Enum.SurfaceType.Smooth

	return Part
end

--> Something thrown from the hand towards the aim, with lift so it arcs. Nothing to aim at is a
--> lob straight ahead. The server keeps the part so the throw lands where it was thrown.
local function Throw(Context: Context, Part: BasePart, Speed: number, Lift: number)
	local Origin = Context.Root.Position + Context.Root.CFrame.LookVector * 2
	local Towards = if Context.Aim then Context.Aim - Origin else Context.Root.CFrame.LookVector
	local Direction = if Towards.Magnitude > 0.1 then Towards.Unit else Context.Root.CFrame.LookVector

	Part.CanQuery = false
	Part.Position = Origin
	Part.AssemblyLinearVelocity = Direction * Speed + Vector3.new(0, Lift, 0)
	Part.AssemblyAngularVelocity = Vector3.new(Draw:NextNumber(-1, 1), Draw:NextNumber(-1, 1), Draw:NextNumber(-1, 1))
		* TumbleSpeed
	Part.Parent = GetFolder()
	Part:SetNetworkOwner(nil)

	PlaySound("Throw", Context.Root)
end

--> A fuse burning on a part: the beep that goes with it, and the bang after. The beep is looped,
--> so it goes with the part.
local function Fuse(Owner: Player, Part: BasePart, Seconds: number, Radius: number, Power: number)
	PlaySound("Fuse", Part)
	Sparks(Part)

	task.delay(Seconds, function()
		if not Part.Parent then
			return
		end

		local Position = Part.Position

		Part:Destroy()
		Explode(Owner, Position, Radius, Power)
	end)
end

local function Swing(Power: number): Effect
	return function(Context: Context)
		local Forward = Context.Root.CFrame.LookVector
		local Origin = Context.Root.Position

		PlaySound("Swing", Context.Root)

		for _, Other in Players:GetPlayers() do
			if Other == Context.Player then
				continue
			end

			local Root = GetRoot(Other)

			if not Root then
				continue
			end

			local Away = Root.Position - Origin

			if Away.Magnitude > SwingRange then
				continue
			end

			local Flat = Vector3.new(Away.X, 0, Away.Z)

			if Flat.Magnitude < 0.1 or Flat.Unit:Dot(Forward) < SwingCone then
				continue
			end

			StatusService:Fling(Other, (Flat.Unit + Vector3.new(0, SwingLift, 0)) * Power)
			PlaySound("Bonk", Root)
			Puff(Root, BonkColor, 250, 0.7, 12)
			Kick(Other, SwingShake)
		end
	end
end

--> The count over a frozen head, ticking down to when they can move again.
local function Countdown(Player: Player, Seconds: number)
	local Character = Player.Character
	local Head = Character and Character:FindFirstChild("Head")

	if not Head or not Head:IsA("BasePart") then
		return
	end

	local Board = Instance.new("BillboardGui")
	Board.Name = "Frozen"
	Board.Size = CountSize
	Board.StudsOffset = CountOffset
	Board.AlwaysOnTop = true
	Board.Adornee = Head

	local Text = Instance.new("TextLabel")
	Text.BackgroundTransparency = 1
	Text.Size = UDim2.fromScale(1, 1)
	Text.FontFace = CountFace
	Text.TextColor3 = CountColor
	Text.TextScaled = true
	Text.Parent = Board

	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Color3.new(0, 0, 0)
	Stroke.Thickness = 2
	Stroke.Parent = Text

	Board.Parent = Head

	local Glow = Instance.new("Highlight")
	Glow.Name = "Frozen"
	Glow.FillColor = FreezeColor
	Glow.FillTransparency = 0.5
	Glow.OutlineColor = FreezeColor
	Glow.DepthMode = Enum.HighlightDepthMode.Occluded
	Glow.Parent = Character

	task.spawn(function()
		local Left = Seconds

		while Left > 0 and Board.Parent do
			Text.Text = "Frozen " .. math.ceil(Left)
			task.wait(0.1)
			Left -= 0.1
		end

		Board:Destroy()
		Glow:Destroy()
	end)
end

local Effects: { [string]: Effect } = {}

Effects.WoodenBat = Swing(WoodenPower)
Effects.SteelBat = Swing(SteelPower)

Effects.Bomb = function(Context: Context)
	local Bomb = BuildFromGear("Bomb", Vector3.new(2, 2, 2), Color3.fromRGB(30, 30, 35))
	Bomb.Anchored = true
	Bomb.CanCollide = false
	Bomb.CanQuery = false
	Bomb.CFrame = CFrame.new(Context.Root.Position + BombDrop) * Context.Root.CFrame.Rotation
	Bomb.Parent = GetFolder()

	Fuse(Context.Player, Bomb, BombFuse, BombRadius, BombPower)
end

Effects.TNT = function(Context: Context)
	local Stick = BuildFromGear("TNT", Vector3.new(1.5, 2, 1.5), Color3.fromRGB(220, 50, 40))

	Throw(Context, Stick, ThrowSpeed, ThrowLift)
	Fuse(Context.Player, Stick, TNTFuse, TNTRadius, TNTPower)
end

--> The puddle where the ball came down: spread out from nothing, and slowing whoever is not the
--> one who threw it, from the last step in.
local function Splat(Owner: Player, Position: Vector3)
	local Puddle = BuildPart("Goo", Vector3.new(GooSize.Y, 0.2, 0.2), Color3.fromRGB(90, 230, 60))
	Puddle.Shape = Enum.PartType.Cylinder
	Puddle.CFrame = CFrame.new(Position) * CFrame.Angles(0, 0, math.pi / 2)
	Puddle.Anchored = true
	Puddle.CanCollide = false
	Puddle.CanQuery = false
	Puddle.Material = Enum.Material.Neon
	Puddle.Parent = GetFolder()

	PlaySound("Splat", Puddle)
	Puff(Puddle, Color3.fromRGB(120, 240, 80), 300, 0.9, 14)

	TweenService:Create(Puddle, SplatTween, { Size = Vector3.new(GooSize.Y, GooSize.X, GooSize.Z) }):Play()

	Puddle.Touched:Connect(function(Hit: BasePart)
		local Other = GetToucher(Hit)

		if Other and Other ~= Owner then
			StatusService:Set(Other, "Goo", GooFactor, GooSlow)
			Tint(Other, GooTint, GooSlow)
		end
	end)

	Debris:AddItem(Puddle, GooLife)
end

--> A ball of goo thrown where the mouse points. It splats on the first thing it hits that is not
--> the thrower, or on its own once it has flown long enough, and anyone it hits square is slowed
--> on the spot.
Effects.Goo = function(Context: Context)
	local Ball = BuildPart("GooBall", Vector3.new(1.6, 1.6, 1.6), Color3.fromRGB(90, 230, 60))
	Ball.Shape = Enum.PartType.Ball
	Ball.Material = Enum.Material.Neon
	Ball.CanTouch = true

	local Owner = Context.Player
	local Landed = false

	local function Land(At: Vector3)
		if Landed then
			return
		end

		Landed = true

		Ball:Destroy()
		Splat(Owner, At)
	end

	Ball.Touched:Connect(function(Hit: BasePart)
		local Other = GetToucher(Hit)

		if Other == Owner or Hit:IsDescendantOf(GetFolder()) then
			return
		end

		if Other then
			StatusService:Set(Other, "Goo", GooFactor, GooSlow)
			Tint(Other, GooTint, GooSlow)
			Kick(Other, GooShake)
		end

		--> the puddle lies where the ball is, on the ground under it
		Land(Ball.Position - Vector3.new(0, Ball.Size.Y / 2, 0))
	end)

	Throw(Context, Ball, GooSpeed, GooLift)

	task.delay(GooFlight, function()
		if Ball.Parent then
			Land(Ball.Position)
		end
	end)
end

--> A plate at the feet that holds the first other player to step on it, then is gone. The one
--> caught gets the count over their head.
Effects.Trap = function(Context: Context)
	local Plate = BuildPart("Trap", TrapSize, Color3.fromRGB(120, 120, 130))
	Plate.Position = Context.Root.Position + Vector3.new(0, -2.75, 0)
	Plate.Anchored = true
	Plate.CanCollide = false
	Plate.CanQuery = false
	Plate.Material = Enum.Material.Metal
	Plate.Parent = GetFolder()

	local Owner = Context.Player
	local Sprung = false

	Plate.Touched:Connect(function(Hit: BasePart)
		local Other = GetToucher(Hit)

		if Sprung or not Other or Other == Owner then
			return
		end

		Sprung = true

		local Root = GetRoot(Other)

		StatusService:Freeze(Other, TrapHold)
		Countdown(Other, TrapHold)
		Kick(Other, TrapShake)

		PlaySound("Snap", Plate.Position)
		PuffAt(Plate.Position, SmokeColor, 300, 0.5, 10)

		if Root then
			PlaySound("Freeze", Root)
		end

		Plate:Destroy()
	end)

	Debris:AddItem(Plate, TrapLife)
end

Effects.SpeedPotion = function(Context: Context)
	StatusService:Set(Context.Player, "Potion", PotionFactor, PotionTime)
	PlaySound("Gulp", Context.Root)
	Puff(Context.Root, Color3.fromRGB(255, 220, 90), 200, 0.6, 10)
end

--> Heard going and heard coming back, so the ones around know to look again.
Effects.InvisibilityCloak = function(Context: Context)
	local Player = Context.Player

	StatusService:Hide(Player, CloakTime)
	PlaySound("Cloak", Context.Root)
	Puff(Context.Root, Color3.fromRGB(180, 140, 255), 250, 0.8, 12)

	task.delay(CloakTime, function()
		local Root = GetRoot(Player)

		if Root then
			PlaySound("Cloak", Root)
		end
	end)
end

return Effects
