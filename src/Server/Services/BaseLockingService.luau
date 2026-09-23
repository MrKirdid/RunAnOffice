local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared

local AntiCheatService = require(script.Parent.AntiCheatService)
local GameConfigs = require(Shared.Configs.GameConfigs)
local PlayerData = require(Shared.PlayerData).server
local PlotBounds = require(Shared.Utilities.PlotBounds)
local PlotService = require(script.Parent.PlotService)

--> How long the lasers stay up after the button. The label at the door counts this down.
local LockSeconds = 60

--> Written on the plot as server time, 0 when open. Attributes replicate on their own, so every
--> client draws the lasers and the countdown off this one number and nothing is sent by hand.
local LockedAttribute = "LockedUntil"

local LasersName = "Lasers"
local WallName = "InvisibleWall"
local ButtonName = "LockBase"

--> How often the locked bases are swept for anyone who should not be in them.
local SweepInterval = 0.2

--> Somebody this close to the door when it shuts was on their way through it, and is let in as a
--> guest rather than caught on the wrong side of a wall that was not there a moment ago.
local ThresholdRadius = 12

--> How many sweeps in a row somebody has to be found inside before it counts. One is a frame of
--> a laggy client's position landing somewhere it was not.
local EvictAfter = 2

--> How long a player is left alone after being thrown out, so the body they leave behind is not
--> thrown out again every sweep until the strikes add up to a kick.
local EvictCooldown = 6

--> How long to wait for PlotService to hand a player their plot before giving up on the character.
local PlotTimeout = 15

--> The owner's character and the owner's lasers are put in a pair of groups that do not collide,
--> which is what lets the owner walk through their own door while it stops everyone else. Physics
--> on every client and the anti-cheat's casts read the same groups, so nobody has to be told.
local function GetGroups(Index: number): (string, string)
	return `Plot{Index}`, `Lasers{Index}`
end

type Lock = {
	Owner: Player,
	Plot: Model,
	LasersGroup: string,
	Until: number,
	--> Whoever was already inside when the door shut. They may leave, and while they are a guest
	--> the door lets them, but once out they are out.
	Guests: { [Player]: boolean },
	--> Sweeps in a row each intruder has been seen inside.
	Seen: { [Player]: number },
}

type Prepared = {
	Plot: Model,
	Click: RBXScriptConnection,
}

local function GetRoot(Player: Player): BasePart?
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	return if Root and Root:IsA("BasePart") then Root else nil
end

--> Inside any floor's room box, by the same boxes VisitService and the client read, so the three
--> never disagree about what counts as in.
local function IsInside(Plot: Model, Position: Vector3): boolean
	return PlotBounds.IsInside(Plot, Position)
end

local function IsAtDoor(Plot: Model, Position: Vector3): boolean
	local Lasers = Plot:FindFirstChild(LasersName)
	local Wall = Lasers and Lasers:FindFirstChild(WallName)

	if not Wall or not Wall:IsA("BasePart") then
		return false
	end

	return (Wall.Position - Position).Magnitude <= ThresholdRadius
end

local function SetSolid(Lasers: Instance, Solid: boolean)
	for _, Part in Lasers:GetDescendants() do
		if Part:IsA("BasePart") then
			Part.CanCollide = Solid
		end
	end
end

--> Whether a player's character passes this base's lasers. Only ever set back to solid for a
--> guest on the way out now that guests are not let through; kept as the one place the group
--> pair is written.
local function SetPassable(Player: Player, LasersGroup: string, Passable: boolean)
	local Index = PlotService.Plots[Player]

	if not Index then
		return
	end

	local CharacterGroup = GetGroups(Index)

	PhysicsService:CollisionGroupSetCollidable(CharacterGroup, LasersGroup, not Passable)
end

local BaseLockingService = {
	Name = "BaseLockingService",
	Locks = {} :: { [Player]: Lock },
	--> Plots already wired up, by owner, so a respawn does not bind the button twice and a
	--> leaver's binding comes off with them.
	Prepared = {} :: { [Player]: Prepared },
	--> When each player was last thrown out of somewhere.
	Evicted = {} :: { [Player]: number },
}

--> What the purple branch of the upgrade tree has bought this player, 0 until the first lock is.
--> Nothing acts on it yet, but the upgrades that raise it are live, so the number is already
--> accurate for whatever ends up reading it.
function BaseLockingService:GetDefense(Player: Player): number
	local Data = PlayerData[Player]

	return if Data then Data.Defense() else 0
end

function BaseLockingService:IsLocked(Player: Player): boolean
	return self.Locks[Player] ~= nil
end

--> Whether somebody is inside a locked base by right: they were there when the door shut. Anyone
--> else found inside got through a wall, and StealingService refuses them on the strength of it.
function BaseLockingService:IsGuest(Owner: Player, Player: Player): boolean
	local Lock = self.Locks[Owner]

	return Lock ~= nil and Lock.Guests[Player] == true
end

function BaseLockingService:Lock(Player: Player): boolean
	if self.Locks[Player] then
		return false
	end

	local Index = PlotService.Plots[Player]
	local Plot = PlotService:GetPlot(Player)
	local Lasers = Plot and Plot:FindFirstChild(LasersName)

	if not Index or not Plot or not Lasers then
		return false
	end

	local _, LasersGroup = GetGroups(Index)
	local Guests = {}

	for _, Other in Players:GetPlayers() do
		local Root = Other ~= Player and GetRoot(Other)

		--> Remembered so the sweep does not throw them out, but the door is as solid to them as to
		--> anyone: being inside when it shut is not a way through it, or a thief already in the
		--> room would walk out with the employee the lock was meant to keep.
		if Root and (IsInside(Plot, Root.Position) or IsAtDoor(Plot, Root.Position)) then
			Guests[Other] = true
		end
	end

	local Until = workspace:GetServerTimeNow() + LockSeconds

	self.Locks[Player] = {
		Owner = Player,
		Plot = Plot,
		LasersGroup = LasersGroup,
		Until = Until,
		Guests = Guests,
		Seen = {},
	}

	SetSolid(Lasers, true)
	Plot:SetAttribute(LockedAttribute, Until)

	--> the tutorial's lock step reads the flag, not the lock itself, which is over in a minute
	local Data = PlayerData[Player]

	if Data and not Data.TutorialLocked() then
		Data.TutorialLocked(true)
	end

	return true
end

function BaseLockingService:Unlock(Player: Player)
	local Lock = self.Locks[Player]

	if not Lock then
		return
	end

	self.Locks[Player] = nil

	for Guest in Lock.Guests do
		SetPassable(Guest, Lock.LasersGroup, false)
	end

	local Lasers = Lock.Plot:FindFirstChild(LasersName)

	if Lasers then
		SetSolid(Lasers, false)
	end

	Lock.Plot:SetAttribute(LockedAttribute, 0)
end

--> Someone in a locked base who was not there when it locked. The door is solid to them, so
--> they did not walk in: it is a strike, the same put-back as any other, and the character goes
--> so there is nothing left inside to argue about. Once, and then the body is left alone.
function BaseLockingService:Evict(Player: Player, Now: number)
	local Last = self.Evicted[Player]

	if Last and Now - Last < EvictCooldown then
		return
	end

	local Character = Player.Character
	local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

	if not Humanoid or Humanoid.Health <= 0 then
		return
	end

	self.Evicted[Player] = Now

	AntiCheatService:Flag(Player, "base")
	Humanoid.Health = 0
end

function BaseLockingService:Sweep()
	local Now = workspace:GetServerTimeNow()

	for Owner, Lock in self.Locks do
		if Now >= Lock.Until then
			self:Unlock(Owner)
			continue
		end

		for _, Other in Players:GetPlayers() do
			if Other == Owner then
				continue
			end

			local Root = GetRoot(Other)
			local Inside = Root ~= nil and IsInside(Lock.Plot, Root.Position)

			if not Inside then
				Lock.Seen[Other] = nil

				--> Out is out. The door was open to them while they were a guest; it is not now.
				if Lock.Guests[Other] and not (Root and IsAtDoor(Lock.Plot, Root.Position)) then
					Lock.Guests[Other] = nil
					SetPassable(Other, Lock.LasersGroup, false)
				end

				continue
			end

			if Lock.Guests[Other] then
				continue
			end

			local Seen = (Lock.Seen[Other] or 0) + 1
			Lock.Seen[Other] = Seen

			if Seen >= EvictAfter then
				self:Evict(Other, Now)
			end
		end
	end
end

--> The plot's lasers into their group, open, and the button wired to its owner. The click is the
--> engine's own, so the player it names is the one who clicked; only the owner's counts.
function BaseLockingService:PreparePlot(Player: Player, Plot: Model, Index: number)
	local Existing = self.Prepared[Player]

	if Existing and Existing.Plot == Plot then
		return
	end

	if Existing then
		Existing.Click:Disconnect()
		self.Prepared[Player] = nil
	end

	local _, LasersGroup = GetGroups(Index)
	local Lasers = Plot:FindFirstChild(LasersName)

	if Lasers then
		for _, Part in Lasers:GetDescendants() do
			if Part:IsA("BasePart") then
				Part.CollisionGroup = LasersGroup
			end
		end

		SetSolid(Lasers, false)
	else
		warn(`[BaseLocking] plot {Index} has no {LasersName} folder, so it cannot be locked`)
	end

	Plot:SetAttribute(LockedAttribute, 0)

	local Button = Plot:FindFirstChild(ButtonName, true)
	local Detector = Button and Button:FindFirstChildOfClass("ClickDetector")

	if not Detector then
		warn(`[BaseLocking] plot {Index} has no {ButtonName} button with a ClickDetector`)
		return
	end

	self.Prepared[Player] = {
		Plot = Plot,
		Click = Detector.MouseClick:Connect(function(Clicker: Player)
			if Clicker == Player then
				self:Lock(Player)
			end
		end),
	}
end

--> Every part of the character into the owner's group, the ones that turn up later included:
--> accessories and tools arrive after the rig, and one part left in Default is one the door
--> catches on.
local function GroupCharacter(Character: Model, Group: string)
	for _, Part in Character:GetDescendants() do
		if Part:IsA("BasePart") then
			Part.CollisionGroup = Group
		end
	end

	Character.DescendantAdded:Connect(function(Part)
		if Part:IsA("BasePart") then
			Part.CollisionGroup = Group
		end
	end)
end

--> The plot is handed out on join and the character comes after it, so it is usually there by
--> now. Usually: at boot this service wakes before PlotService does, so anyone already standing
--> in the game is waited on rather than skipped, or their own door would stop them.
function BaseLockingService:HandleCharacter(Player: Player, Character: Model)
	local Deadline = os.clock() + PlotTimeout

	while not PlotService.Plots[Player] and Player.Character == Character and os.clock() < Deadline do
		task.wait(0.1)
	end

	local Index = PlotService.Plots[Player]
	local Plot = PlotService:GetPlot(Player)

	if not Index or not Plot or Player.Character ~= Character then
		return
	end

	local CharacterGroup = GetGroups(Index)

	GroupCharacter(Character, CharacterGroup)
	AntiCheatService:SetCollisionGroup(Player, CharacterGroup)
	self:PreparePlot(Player, Plot, Index)
end

function BaseLockingService:HandlePlayer(Player: Player)
	Player.CharacterAdded:Connect(function(Character)
		self:HandleCharacter(Player, Character)
	end)

	if Player.Character then
		task.spawn(function()
			self:HandleCharacter(Player, Player.Character :: Model)
		end)
	end
end

function BaseLockingService:Init()
	for Index = 1, GameConfigs.PlotAmount do
		local CharacterGroup, LasersGroup = GetGroups(Index)

		for _, Group in { CharacterGroup, LasersGroup } do
			if not PhysicsService:IsCollisionGroupRegistered(Group) then
				PhysicsService:RegisterCollisionGroup(Group)
			end
		end

		PhysicsService:CollisionGroupSetCollidable(CharacterGroup, LasersGroup, false)
	end

	for _, Player in Players:GetPlayers() do
		self:HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player)
		self:HandlePlayer(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player)
		self:Unlock(Player)

		--> A guest leaving takes their passage with them, so the next player handed their group
		--> does not inherit an open door.
		for _, Lock in self.Locks do
			if Lock.Guests[Player] then
				Lock.Guests[Player] = nil
				SetPassable(Player, Lock.LasersGroup, false)
			end
		end

		local Existing = self.Prepared[Player]

		if Existing then
			Existing.Click:Disconnect()
			self.Prepared[Player] = nil
		end

		self.Evicted[Player] = nil
	end)
end

function BaseLockingService:Start()
	local Elapsed = 0

	RunService.Heartbeat:Connect(function(Delta: number)
		Elapsed += Delta

		if Elapsed < SweepInterval then
			return
		end

		Elapsed = 0
		self:Sweep()
	end)
end

return BaseLockingService
