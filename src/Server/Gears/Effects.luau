local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared

local AntiCheatService = require(ServerScriptService.Server.Services.AntiCheatService)
local GearConfigs = require(Shared.Configs.Gears)
local NetworkingServer = require(Shared.Networking.networkingServer)
local NetworkingTypes = require(Shared.Networking.networkingTypes)
local SoundConfigs = require(Shared.Configs.Sounds)
local StatusService = require(ServerScriptService.Server.Services.StatusService)
local StealingService = require(ServerScriptService.Server.Services.StealingService)

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

--> the look of each, in Shared.VFX.Gears
type Fx = NetworkingTypes.Gears_Fx

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
local BombPower = 41

--> the tnt: thrown to the aim at about this speed across the ground, with this much lift when
--> there is nothing to aim at, then the bigger blast
local ThrowSpeed = 90
local ThrowLift = 25
local TNTFuse = 2
local TNTRadius = 22
local TNTPower = 53

--> the blast's lift over its sideways push, so nobody is shoved along the floor. The camera kick is
--> each client's own, off how close it stood.
--> A blast throws whoever is at its centre (2 * BlastLift * Power ^ 2 / gravity) studs and the
--> edge a quarter of that: the tnt about 20 at the centre, the bomb about 12.
local BlastLift = 0.7

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
local TrapDrop = Vector3.new(0, -2.75, 0)
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

--> the fuse: how many sparks a second and the light they throw, and how fast a thrown stick tumbles
local SparkRate = 45
local SparkColor = Color3.fromRGB(255, 190, 80)
local FuseLight = 6
local TumbleSpeed = 14

--> the slowed: tinted green for as long as the goo has them
local GooTint = Color3.fromRGB(110, 230, 80)

--> A throw is timed to come down on the aim: never quicker than this, and never longer, which is
--> also what caps how far it goes. Aims further from the origin than any map is are thrown out.
local MinThrowTime = 0.25
local MaxThrowTime = 1.2
local MaxCoordinate = 100_000

--> How far under a thing dropped or splatted the floor is looked for, from where it was let go.
local GroundReach = 60

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

--> What it looked like, sent to every client to draw: Shared.VFX.Gears is the look of each Kind.
--> Nothing about what the gear did rides on this; that is all done here before it goes out.
local function Show(Kind: Fx, At: Vector3, Direction: Vector3, Size: number, By: Player?, Target: Player?)
	NetworkingServer.Gears.Effect.FireAll({
		Kind = Kind,
		At = At,
		Direction = Direction,
		Size = Size,
		By = By,
		Target = Target,
	})
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
	end
end

--> The bang itself: the look on every client, the sound played at the spot, and the throw done by
--> hand around it. Every client kicks its own camera off how close it stood.
local function Explode(Owner: Player, Position: Vector3, Radius: number, Power: number)
	PlaySound("Explode", Position)
	Show("Blast", Position, Vector3.yAxis, Radius, Owner)
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

--> Everything a cast for walls and floors should see through: whatever the gears have left lying
--> about, the floors of every plot its owner has not bought, which stand solid here and on nobody's
--> screen, and every character unless the cast is looking for them.
local function WorldParams(HitCharacters: boolean?): RaycastParams
	local Ignore: { Instance } = { GetFolder() }

	for _, Hidden in AntiCheatService.Hidden do
		table.move(Hidden, 1, #Hidden, #Ignore + 1, Ignore)
	end

	if not HitCharacters then
		for _, Other in Players:GetPlayers() do
			if Other.Character then
				table.insert(Ignore, Other.Character)
			end
		end
	end

	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = Ignore
	Params.RespectCanCollide = true

	return Params
end

--> The floor under a point, or nil with nothing solid within reach. Cast from a little above, so a
--> point sunk just into the floor still finds it.
local function GroundBelow(Position: Vector3): Vector3?
	local Result = workspace:Raycast(Position + Vector3.new(0, 1, 0), Vector3.new(0, -GroundReach, 0), WorldParams())

	return if Result then Result.Position else nil
end

--> Follows something thrown along the path it actually flew, frame by frame, and calls OnHit with the
--> first thing it passed through. Thrown things never collide: physics against the server's copy of
--> the world bounced them off the unbought floors nobody else can see and stuck them there in mid
--> air. The cast leaves those floors out; an invisible wall that is solid, a locked base's door,
--> still stops it.
local function Track(Part: BasePart, Params: RaycastParams, OnHit: (Result: RaycastResult) -> ())
	local Last = Part.Position
	local Connection: RBXScriptConnection

	Connection = RunService.Heartbeat:Connect(function()
		if not Part.Parent then
			Connection:Disconnect()
			return
		end

		local Now = Part.Position
		local Result = if Now ~= Last then workspace:Raycast(Last, Now - Last, Params) else nil

		Last = Now

		if Result then
			Connection:Disconnect()
			OnHit(Result)
		end
	end)
end

--> The aim as sent, if it is a real point: the client can send anything, and a NaN or an infinity
--> would turn into a velocity nobody could aim.
local function CleanAim(Aim: Vector3?): Vector3?
	if not Aim or Aim ~= Aim or Aim.Magnitude > MaxCoordinate then
		return nil
	end

	return Aim
end

--> Something thrown from the hand so that it comes down on the aim: timed off how far away that is
--> at about Speed across the ground, and lifted by exactly what gravity takes back over that time.
--> An aim past MaxThrowTime of flight is brought in to that. Nothing to aim at is a lob straight
--> ahead. The server keeps the part so the throw lands where it was thrown, and it collides with
--> nothing: Track is what finds where it comes down.
local function Throw(Context: Context, Part: BasePart, Speed: number, Lift: number)
	local Forward = Context.Root.CFrame.LookVector
	local Origin = Context.Root.Position + Forward * 2
	local Aim = CleanAim(Context.Aim)
	local Velocity = Forward * Speed + Vector3.new(0, Lift, 0)

	if Aim then
		local Reach = Speed * MaxThrowTime
		local Offset = Aim - Origin

		--> as far up or down as it may go across, so a point down a pit is not a throw at the floor
		Offset = Vector3.new(Offset.X, math.clamp(Offset.Y, -Reach, Reach), Offset.Z)

		local Flat = Vector3.new(Offset.X, 0, Offset.Z)
		local Time = math.clamp(Flat.Magnitude / Speed, MinThrowTime, MaxThrowTime)

		--> brought in along the line to it when it is further than the longest flight carries
		if Flat.Magnitude > Reach then
			Offset = Flat.Unit * Reach + Vector3.new(0, Offset.Y, 0)
			Flat = Vector3.new(Offset.X, 0, Offset.Z)
		end

		Velocity = Flat / Time + Vector3.new(0, Offset.Y / Time + workspace.Gravity * Time / 2, 0)
	end

	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.Position = Origin
	Part.AssemblyLinearVelocity = Velocity
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

--> Size is how big the swing and the hit look, 1 for the wooden bat.
local function Swing(Power: number, Size: number): Effect
	return function(Context: Context)
		local Forward = Context.Root.CFrame.LookVector
		local Origin = Context.Root.Position

		PlaySound("Swing", Context.Root)
		Show("Swing", Origin, Forward, Size, Context.Player)

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

			--> a wall between the two is a swing into the wall
			if workspace:Raycast(Origin, Away, WorldParams()) then
				continue
			end

			StatusService:Fling(Other, (Flat.Unit + Vector3.new(0, SwingLift, 0)) * Power)

			--> what the bat is for: a thief it connects with drops whoever they were carrying off,
			--> and the employee goes straight back to the desk they were taken from
			StealingService:Caught(Other)

			PlaySound("Bonk", Root)
			Show("Bonk", Root.Position, Flat.Unit, Size, Context.Player, Other)
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

Effects.WoodenBat = Swing(WoodenPower, GearConfigs.List.WoodenBat.Swing or 1)
Effects.SteelBat = Swing(SteelPower, GearConfigs.List.SteelBat.Swing or 1)

Effects.Bomb = function(Context: Context)
	local Bomb = BuildFromGear("Bomb", Vector3.new(2, 2, 2), Color3.fromRGB(30, 30, 35))
	Bomb.Anchored = true
	Bomb.CanCollide = false
	Bomb.CanQuery = false
	--> sat on the floor under the player, or under their feet where they stand with none found
	local Floor = GroundBelow(Context.Root.Position)
	local At = if Floor then Floor + Vector3.new(0, Bomb.Size.Y / 2, 0) else Context.Root.Position + BombDrop

	Bomb.CFrame = CFrame.new(At) * Context.Root.CFrame.Rotation
	Bomb.Parent = GetFolder()

	Fuse(Context.Player, Bomb, BombFuse, BombRadius, BombPower)
end

Effects.TNT = function(Context: Context)
	local Stick = BuildFromGear("TNT", Vector3.new(1.5, 2, 1.5), Color3.fromRGB(220, 50, 40))

	Throw(Context, Stick, ThrowSpeed, ThrowLift)

	--> It stops dead on the first thing it comes down on, stood up on it, so it goes off where it
	--> was thrown rather than rolling on. Players are thrown past, not stuck to.
	Track(Stick, WorldParams(), function(Hit: RaycastResult)
		Stick.Anchored = true
		Stick.CFrame = CFrame.new(Hit.Position + Hit.Normal * Stick.Size.Y / 2) * Context.Root.CFrame.Rotation
	end)

	Fuse(Context.Player, Stick, TNTFuse, TNTRadius, TNTPower)
end

--> The puddle where the ball came down: spread out from nothing, and slowing whoever is not the
--> one who threw it, from the last step in.
local function Splat(Owner: Player, Position: Vector3, Target: Player?)
	local Puddle = BuildPart("Goo", Vector3.new(GooSize.Y, 0.2, 0.2), Color3.fromRGB(90, 230, 60))
	Puddle.Shape = Enum.PartType.Cylinder
	Puddle.CFrame = CFrame.new(Position) * CFrame.Angles(0, 0, math.pi / 2)
	Puddle.Anchored = true
	Puddle.CanCollide = false
	Puddle.CanQuery = false
	Puddle.Material = Enum.Material.Neon
	Puddle.Parent = GetFolder()

	PlaySound("Splat", Puddle)
	Show("Splat", Position, Vector3.yAxis, 1, Owner, Target)

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

	local Owner = Context.Player
	local Landed = false

	local function Land(At: Vector3, Target: Player?)
		if Landed then
			return
		end

		Landed = true

		Ball:Destroy()
		Splat(Owner, At, Target)
	end

	Throw(Context, Ball, GooSpeed, GooLift)

	--> every character but the thrower's own is something to hit
	local Params = WorldParams(true)
	local Filter = Params.FilterDescendantsInstances

	if Owner.Character then
		table.insert(Filter, Owner.Character)
		Params.FilterDescendantsInstances = Filter
	end

	Track(Ball, Params, function(Hit: RaycastResult)
		local Other = GetToucher(Hit.Instance :: BasePart)

		if Other then
			StatusService:Set(Other, "Goo", GooFactor, GooSlow)
			Tint(Other, GooTint, GooSlow)
			Kick(Other, GooShake)
		end

		--> the puddle lies on the floor under where the ball hit, a wall or a player included
		Land(GroundBelow(Hit.Position) or Hit.Position, Other)
	end)

	task.delay(GooFlight, function()
		if Ball.Parent then
			Land(GroundBelow(Ball.Position) or Ball.Position)
		end
	end)
end

--> A plate at the feet that holds the first other player to step on it, then is gone. The one
--> caught gets the count over their head.
Effects.Trap = function(Context: Context)
	local Plate = BuildPart("Trap", TrapSize, Color3.fromRGB(120, 120, 130))
	local Floor = GroundBelow(Context.Root.Position)

	Plate.Position = if Floor then Floor + Vector3.new(0, TrapSize.Y / 2, 0) else Context.Root.Position + TrapDrop
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
		Show("Snap", Plate.Position, Vector3.yAxis, 1, Owner, Other)

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
	Show("Gulp", Context.Root.Position, Vector3.yAxis, 1, Context.Player, Context.Player)
end

--> Heard going and heard coming back, so the ones around know to look again.
Effects.InvisibilityCloak = function(Context: Context)
	local Player = Context.Player

	StatusService:Hide(Player, CloakTime)
	PlaySound("Cloak", Context.Root)
	Show("Cloak", Context.Root.Position, Vector3.yAxis, 1, Player)

	task.delay(CloakTime, function()
		local Root = GetRoot(Player)

		if Root then
			PlaySound("Cloak", Root)
			Show("Cloak", Root.Position, Vector3.yAxis, 1, Player)
		end
	end)
end

return Effects
