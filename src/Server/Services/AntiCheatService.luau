local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared

local Admins = require(Shared.Configs.Admins)

--> Every check here reads what the client replicated and asks whether physics could have done it.
--> None of them trust a value the client reports about itself: the humanoid's state and floor
--> material are the client's to set, so ground is found with a cast and speed with a ruler.
--> A player caught is put back where they last stood, not kicked -- a kick is for someone who
--> keeps at it, and the bar for that is set high enough that a bad connection never reaches it.

--> How much over WalkSpeed a player may move before it counts. Covers the momentum of landing,
--> a shove from another character, and the odd late frame from the client.
local SpeedTolerance = 1.3

--> Studs per second granted on top of the tolerance, so a WalkSpeed of 0 still forgives jitter.
local SpeedSlack = 2

--> How many seconds of unspent movement a player banks. A client on a bad connection stops sending
--> positions and then sends the whole gap at once; the bank is what lets that arrive as the walk
--> it was rather than as a burst. The cap is what stops a cheater standing still to save up:
--> what it buys them is one hop of a few seconds' walking, and then the wait to earn another.
local BankSeconds = 3

--> How far into debt the bank goes before it is a strike, in studs.
local Overdraft = 8

--> Airborne this long without dropping and something other than physics is holding you up. A jump
--> from a standing start is back on the ground in about half a second, so this is generous.
local HoverSeconds = 2

--> Studs a jump may carry you above where you left the ground, on top of the jump height itself.
local ClimbSlack = 3

--> How far under the standing height the ground may be and still count as under you: slopes, the
--> lip of a step, a slab the client and server disagree about by a hair.
local GroundReach = 1.5

--> Only movement this short is ray-checked for walls. A longer step is a laggy client catching up,
--> and the straight line between where it was and where it is now says nothing about the route it
--> took. The speed check is what catches a long step that was not lag.
local ClipSegment = 3

--> Strikes fade one at a time this many seconds apart, and this many live at once is a kick.
--> A lag spike is a strike or two; twenty is somebody who keeps trying.
local StrikeDecay = 10
local KickStrikes = 20

--> How long after any teleport -- the plot, a floor, or being put back -- the checks stay off,
--> so the arrival is not read as the very thing it is correcting. The client's stale positions
--> from before it heard about the move are still landing for the first part of it.
local GraceSeconds = 0.5

--> How far from where a teleport put them a player may be when the grace runs out. Half a second
--> of falling and walking is well inside it; a client that shrugged the move off is not.
local AnchorSlack = 25

--> How far Y must drop between samples to count as still falling, and how far the root must move
--> between samples to count as the client still sending.
local DescentStep = 0.25
local MoveStep = 0.05

--> A root that has not moved for this long is a client that stopped sending, not a character
--> holding still: even the top of a standing jump is over in a few frames.
local MaxStall = 0.3

type Record = {
	Strikes: number,
	LastStrike: number,
}

type Watch = {
	Character: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Record: Record,
	--> the wall cast: leaves out every character, so brushing past someone is not a wall, and
	--> is cast as the player's own collision group, so what their character passes through by
	--> the group rules -- their own base's lasers -- is not a wall either
	WallParams: RaycastParams,
	--> excludes the player's own character and nothing else, so another player is ground
	GroundParams: RaycastParams,
	LastPosition: Vector3,
	LastGood: CFrame,
	LastMove: number,
	Bank: number,
	Airborne: boolean,
	AirStartY: number,
	MinY: number,
	LastDescent: number,
	GraceUntil: number,
	Anchor: CFrame?,
}

local function IsExempt(Player: Player): boolean
	return Admins.UserIds[Player.UserId] == true
end

--> Studs per second the player may cover, and the most they may have banked.
local function GetAllowed(Humanoid: Humanoid): number
	return Humanoid.WalkSpeed * SpeedTolerance + SpeedSlack
end

--> Studs a jump reaches, off whichever of the two settings the humanoid is using.
local function GetJumpHeight(Humanoid: Humanoid): number
	if Humanoid.UseJumpPower then
		return (Humanoid.JumpPower * Humanoid.JumpPower) / (2 * workspace.Gravity)
	end

	return Humanoid.JumpHeight
end

local AntiCheatService = {
	Name = "AntiCheatService",
	Watches = {} :: { [Player]: Watch },
	--> Kept apart from the watch so a reset does not wipe the count. A watch lives as long as a
	--> character; this lives as long as the player.
	Records = {} :: { [Player]: Record },
	--> The collision group each player's character is put in, by whoever put it there. Kept
	--> here as well as on the watch because it is set before the character exists.
	Groups = {} :: { [Player]: string },
}

function AntiCheatService:RefreshParams()
	local Characters = {}

	for _, Player in Players:GetPlayers() do
		if Player.Character then
			table.insert(Characters, Player.Character)
		end
	end

	for _, Watch in self.Watches do
		Watch.WallParams.FilterDescendantsInstances = Characters
	end
end

--> Tells the checks which collision group the player's character moves as, so a cast agrees with
--> physics about what is solid to them. Called by whatever assigns the group.
function AntiCheatService:SetCollisionGroup(Player: Player, Group: string)
	self.Groups[Player] = Group

	local Watch = self.Watches[Player]

	if Watch then
		Watch.WallParams.CollisionGroup = Group
		Watch.GroundParams.CollisionGroup = Group
	end
end

--> A strike from outside: something another system caught the player doing that the movement
--> checks could not see. Same cost and the same put-back as one of their own.
function AntiCheatService:Flag(Player: Player, Reason: string)
	local Watch = self.Watches[Player]

	if not Watch or Watch.Humanoid.Health <= 0 then
		return
	end

	self:Strike(Player, Watch, Reason, os.clock())
end

--> A flat block the width of the root, cast down to the standing height and a little past it.
--> A block rather than a ray so that standing on the edge of a slab still finds the slab.
function AntiCheatService:IsGrounded(Watch: Watch): boolean
	local Root, Humanoid = Watch.Root, Watch.Humanoid
	local Reach = Humanoid.HipHeight + Root.Size.Y / 2 + GroundReach
	local Footprint = Vector3.new(Root.Size.X, 0.2, Root.Size.Z)

	return workspace:Blockcast(Root.CFrame, Footprint, Vector3.new(0, -Reach, 0), Watch.GroundParams) ~= nil
end

--> Lifts the checks for a moment and takes Target as where the character should be by the time
--> they come back. The bank is refilled so the first steps after arriving count as a walk and
--> the spot to go back to starts moving again at once.
function AntiCheatService:Forgive(Player: Player, Target: CFrame)
	local Watch = self.Watches[Player]

	if not Watch then
		return
	end

	Watch.GraceUntil = os.clock() + GraceSeconds
	Watch.Anchor = Target
	Watch.LastPosition = Target.Position
	Watch.LastGood = Target
	Watch.Bank = GetAllowed(Watch.Humanoid) * BankSeconds
	Watch.Airborne = false
end

--> The one way the server should move a character. Anything that pivots a player without going
--> through here is read as the player having done it themselves.
function AntiCheatService:Teleport(Player: Player, Target: CFrame)
	local Character = Player.Character

	if not Character then
		return
	end

	Character:PivotTo(Target)
	self:Forgive(Player, Target)
end

function AntiCheatService:Strike(Player: Player, Watch: Watch, Reason: string, Now: number)
	local Record = Watch.Record

	Record.Strikes += 1
	Record.LastStrike = Now

	warn(`[AntiCheat] {Player.Name}: {Reason} at {Watch.Root.Position} (strike {Record.Strikes})`)

	if Record.Strikes >= KickStrikes then
		Player:Kick("Movement checks failed repeatedly.")
		return
	end

	--> Settled here and not left to the teleport, which has nothing to do when the character has
	--> gone between the check and the strike: a bank left in debt is a strike every frame after.
	Watch.Bank = 0
	Watch.LastPosition = Watch.Root.Position
	Watch.Root.AssemblyLinearVelocity = Vector3.zero
	self:Teleport(Player, Watch.LastGood)
end

function AntiCheatService:Sample(Player: Player, Watch: Watch, Delta: number, Now: number)
	local Humanoid = Watch.Humanoid

	if Humanoid.Health <= 0 then
		return
	end

	--> The root is the client's part to reparent, and a check on a root that has left the
	--> character checks nothing. Picked up again from the character if it is back; a character
	--> alive with no root in it is not one the game made.
	if Watch.Root.Parent ~= Watch.Character then
		local Root = Watch.Character:FindFirstChild("HumanoidRootPart")

		if not Root or not Root:IsA("BasePart") then
			Player:Kick("Character tampered with.")
			return
		end

		Watch.Root = Root
	end

	local Root = Watch.Root
	local Record = Watch.Record

	if Record.Strikes > 0 and Now - Record.LastStrike > StrikeDecay then
		Record.Strikes -= 1
		Record.LastStrike = Now
	end

	local Position = Root.Position

	if Now < Watch.GraceUntil then
		Watch.LastPosition = Position
		return
	end

	--> Grace is over, and the character has to be about where the teleport put them. A client
	--> that kept sending its own position through the move is put there again, and it costs a
	--> strike, so a client that keeps shrugging moves off runs out of them.
	local Anchor = Watch.Anchor

	if Anchor then
		Watch.Anchor = nil

		if (Position - Anchor.Position).Magnitude > AnchorSlack then
			self:Strike(Player, Watch, "anchor", Now)
			return
		end
	end

	--> Speed is measured flat. Falling is as fast as gravity says and is the fly check's business.
	local Allowed = GetAllowed(Humanoid)
	local Step = Position - Watch.LastPosition
	local Flat = Vector3.new(Step.X, 0, Step.Z)
	local Length = Step.Magnitude

	--> Movement after a stall starts the hover clock over: whatever the air time before the client
	--> went quiet, the part of it that was a freeze says nothing about flight.
	if Length > MoveStep then
		if Now - Watch.LastMove > MaxStall then
			Watch.LastDescent = Now
		end

		Watch.LastMove = Now
	end

	Watch.Bank = math.min(Watch.Bank + Allowed * Delta, Allowed * BankSeconds) - Flat.Magnitude

	if Watch.Bank < -Overdraft then
		self:Strike(Player, Watch, "speed", Now)
		return
	end

	--> A ray from the last spot to this one crosses a solid face only if the root went through it.
	--> Starting inside a part finds nothing, which is fine: the crossing into it was the frame
	--> before, and that one was caught.
	if Length > 0 and Length <= ClipSegment and workspace:Raycast(Watch.LastPosition, Step, Watch.WallParams) then
		self:Strike(Player, Watch, "clip", Now)
		return
	end

	if self:IsGrounded(Watch) then
		Watch.Airborne = false

		--> Only a spot reached with the bank near full is worth going back to. A walk at full speed
		--> earns more than it spends and stays there; a cheat drains it from the first frame, so the
		--> spot kept is the one they set off from rather than the frame before they were caught.
		if Watch.Bank >= Allowed * (BankSeconds - 0.5) then
			Watch.LastGood = Root.CFrame
		end

		Watch.LastPosition = Position
		return
	end

	--> Measured from the last sample, which was on the ground, rather than from this one: a root
	--> that went from the floor to thirty studs up in one step left the ground at the floor.
	if not Watch.Airborne then
		Watch.Airborne = true
		Watch.AirStartY = Watch.LastPosition.Y
		Watch.MinY = Position.Y
		Watch.LastDescent = Now
		Watch.LastPosition = Position
		return
	end

	if Position.Y < Watch.MinY - DescentStep then
		Watch.MinY = Position.Y
		Watch.LastDescent = Now
	end

	if Position.Y > Watch.AirStartY + GetJumpHeight(Humanoid) + ClimbSlack then
		self:Strike(Player, Watch, "fly", Now)
		return
	end

	--> Hanging in the air is only a strike while the client is still sending: a client that froze
	--> mid-jump sits at the same spot for as long as the freeze and then falls, and that is not
	--> flight. Somebody parked in the air sending nothing is going nowhere until they move, and
	--> from the moment they do this has two seconds to see it.
	if Now - Watch.LastDescent > HoverSeconds and Now - Watch.LastMove <= MaxStall then
		self:Strike(Player, Watch, "hover", Now)
		return
	end

	Watch.LastPosition = Position
end

function AntiCheatService:Track(Player: Player, Character: Model)
	local Root = Character:WaitForChild("HumanoidRootPart", 10)
	local Humanoid = Character:WaitForChild("Humanoid", 10)

	if not Root or not Humanoid or Player.Character ~= Character then
		return
	end

	local Record = self.Records[Player]

	if not Record then
		return
	end

	local Now = os.clock()
	local Group = self.Groups[Player] or "Default"

	local WallParams = RaycastParams.new()
	WallParams.FilterType = Enum.RaycastFilterType.Exclude
	WallParams.RespectCanCollide = true
	WallParams.IgnoreWater = true
	WallParams.CollisionGroup = Group

	local GroundParams = RaycastParams.new()
	GroundParams.FilterType = Enum.RaycastFilterType.Exclude
	GroundParams.FilterDescendantsInstances = { Character }
	GroundParams.RespectCanCollide = true
	GroundParams.IgnoreWater = true
	GroundParams.CollisionGroup = Group

	--> Grace from the start, because the spawn itself is a move to the plot that lands a frame or
	--> two after the root exists.
	self.Watches[Player] = {
		Character = Character,
		Root = Root :: BasePart,
		Humanoid = Humanoid :: Humanoid,
		Record = Record,
		WallParams = WallParams,
		GroundParams = GroundParams,
		LastPosition = (Root :: BasePart).Position,
		LastGood = (Root :: BasePart).CFrame,
		LastMove = Now,
		Bank = GetAllowed(Humanoid :: Humanoid) * BankSeconds,
		Airborne = false,
		AirStartY = 0,
		MinY = 0,
		LastDescent = Now,
		GraceUntil = Now + GraceSeconds,
		Anchor = nil,
	}

	self:RefreshParams()
end

--> Every character goes into the wall cast filter, exempt or not: an admin standing in a doorway
--> is still not a wall. Only the watching is skipped.
function AntiCheatService:HandlePlayer(Player: Player)
	local Exempt = IsExempt(Player)

	if not Exempt then
		self.Records[Player] = { Strikes = 0, LastStrike = os.clock() }
	end

	Player.CharacterAdded:Connect(function(Character)
		self:RefreshParams()

		if not Exempt then
			self:Track(Player, Character)
		end
	end)

	Player.CharacterRemoving:Connect(function()
		self.Watches[Player] = nil
		self:RefreshParams()
	end)

	if Player.Character then
		self:RefreshParams()

		if not Exempt then
			self:Track(Player, Player.Character)
		end
	end
end

function AntiCheatService:Init()
	for _, Player in Players:GetPlayers() do
		self:HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player)
		self:HandlePlayer(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player)
		self.Watches[Player] = nil
		self.Records[Player] = nil
		self.Groups[Player] = nil
		self:RefreshParams()
	end)
end

function AntiCheatService:Start()
	RunService.Heartbeat:Connect(function(Delta)
		local Now = os.clock()

		for Player, Watch in self.Watches do
			self:Sample(Player, Watch, Delta, Now)
		end
	end)
end

return AntiCheatService
