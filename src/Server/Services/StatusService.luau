local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkingServer = require(ReplicatedStorage.Shared.Networking.networkingServer)

local AntiCheatService = require(script.Parent.AntiCheatService)

--> What the gears do to a player, all in one place: slowed, sped up, frozen, hidden or flung.
--> Nothing here takes health. Speed is handed to MonetizationService as one attribute on the
--> player, the product of every modifier running, so it can fold it into the walk speed it
--> already owns; a frozen player is that attribute at 0.

local SpeedAttribute = "SpeedFactor"

--> set on the player while the cloak has them, so the tag over their head, which is drawn on
--> every client rather than on the character, knows to go with the rest of them
local HiddenAttribute = "Hidden"

--> How long a flung character is left to fly, limp, before it is stood back up and given back to
--> its own client, and how often timed statuses are looked over for ones that have run out.
local FlingTime = 1.6
local TickRate = 0.25

--> how far a limp joint bends and twists, so an arm swings but never folds through the body
local SwingLimit = 70
local TwistLimit = 45

--> how big a limp limb's collision box is against the limb
local ColliderScale = 0.7

type Modifier = {
	Factor: number,
	Until: number,
}

type Hidden = {
	Character: Model,
	Parts: { [Instance]: number },
	Display: Enum.HumanoidDisplayDistanceType,
	Until: number,
}

local StatusService = {
	Name = "StatusService",

	--> named speed modifiers per player, math.huge for one held until it is cleared
	Modifiers = {} :: { [Player]: { [string]: Modifier } },

	--> what a hidden character looked like before, so it comes back the same
	Hidden = {} :: { [Player]: Hidden },

	--> what a frozen humanoid could jump before, so it is given back exactly
	Jumps = {} :: { [Player]: { Height: number, Power: number } },

	--> the fling in progress per player, so a second one does not stand them up early
	Flung = {} :: { [Player]: number },

	--> what stands a limp character back up, while one is
	Limp = {} :: { [Player]: () -> () },
}

--> Goes limp, and hands back what stands it up again. Characters on the newer joints already
--> carry a limited ball socket beside every AnimationConstraint, held off by it: switching the
--> constraint off is all it takes. An older rig's Motor6Ds get a ball socket made for them. The
--> root's joint is left alone either way, or the part the velocity is on flies off on its own,
--> and every limb gets a solid box welded inside it so it lands on the floor rather than through
--> it: the humanoid keeps its own limbs' CanCollide off whatever is set on them.
local function Ragdoll(Character: Model, Humanoid: Humanoid): () -> ()
	local Made = {}
	local Joints = {}
	local Boxed = {}
	local Neck = Humanoid.RequiresNeck

	--> a neck with its joint off counts as broken, which would kill them
	Humanoid.RequiresNeck = false

	local function Limp(Part0: BasePart, Part1: BasePart)
		--> the two halves of a joint overlap, and solid against each other they would shove apart
		local Apart = Instance.new("NoCollisionConstraint")
		Apart.Name = "RagdollApart"
		Apart.Part0 = Part0
		Apart.Part1 = Part1
		Apart.Parent = Part0

		table.insert(Made, Apart)

		for _, Part in { Part0, Part1 } do
			if Boxed[Part] then
				continue
			end

			Boxed[Part] = true

			--> a little smaller than the limb, so neighbouring boxes do not grind against each other
			local Box = Instance.new("Part")
			Box.Name = "RagdollCollider"
			Box.Size = Part.Size * ColliderScale
			Box.CFrame = Part.CFrame
			Box.Transparency = 1
			Box.Massless = true
			Box.CanCollide = true
			Box.CanQuery = false
			Box.CanTouch = false
			Box.CollisionGroup = Part.CollisionGroup

			local Weld = Instance.new("WeldConstraint")
			Weld.Part0 = Part
			Weld.Part1 = Box
			Weld.Parent = Box

			Box.Parent = Part

			table.insert(Made, Box)
		end
	end

	for _, Joint in Character:GetDescendants() do
		if Joint:IsA("AnimationConstraint") then
			local Part0 = Joint.Attachment0 and Joint.Attachment0.Parent
			local Part1 = Joint.Attachment1 and Joint.Attachment1.Parent

			if not Part0 or not Part1 or not Part0:IsA("BasePart") or not Part1:IsA("BasePart") then
				continue
			end

			if Part0.Name == "HumanoidRootPart" or Part1.Name == "HumanoidRootPart" then
				continue
			end

			Limp(Part0, Part1)
			table.insert(Joints, Joint)
			Joint.Enabled = false

			continue
		end

		if not Joint:IsA("Motor6D") or not Joint.Part0 or not Joint.Part1 then
			continue
		end

		local Part0 = Joint.Part0 :: BasePart
		local Part1 = Joint.Part1 :: BasePart

		if Part0.Name == "HumanoidRootPart" or Part1.Name == "HumanoidRootPart" then
			continue
		end

		local Attachment0 = Instance.new("Attachment")
		Attachment0.Name = "RagdollAttachment"
		Attachment0.CFrame = Joint.C0
		Attachment0.Parent = Part0

		local Attachment1 = Instance.new("Attachment")
		Attachment1.Name = "RagdollAttachment"
		Attachment1.CFrame = Joint.C1
		Attachment1.Parent = Part1

		local Socket = Instance.new("BallSocketConstraint")
		Socket.Name = "RagdollSocket"
		Socket.Attachment0 = Attachment0
		Socket.Attachment1 = Attachment1
		Socket.LimitsEnabled = true
		Socket.UpperAngle = SwingLimit
		Socket.TwistLimitsEnabled = true
		Socket.TwistLowerAngle = -TwistLimit
		Socket.TwistUpperAngle = TwistLimit
		Socket.Parent = Part0

		table.insert(Made, Attachment0)
		table.insert(Made, Attachment1)
		table.insert(Made, Socket)

		Limp(Part0, Part1)
		table.insert(Joints, Joint)
		Joint.Enabled = false
	end

	return function()
		for _, Created in Made do
			Created:Destroy()
		end

		for _, Joint in Joints do
			Joint.Enabled = true
		end

		Humanoid.RequiresNeck = Neck
	end
end

local function GetHumanoid(Player: Player): Humanoid?
	local Character = Player.Character

	return Character and Character:FindFirstChildOfClass("Humanoid")
end

--> The product of everything running, dropping anything that has run out on the way.
function StatusService:GetSpeedFactor(Player: Player): number
	local Modifiers = self.Modifiers[Player]

	if not Modifiers then
		return 1
	end

	local Now = os.clock()
	local Factor = 1

	for Name, Modifier in Modifiers do
		if Modifier.Until <= Now then
			Modifiers[Name] = nil
			continue
		end

		Factor *= Modifier.Factor
	end

	return Factor
end

--> Writes the attribute the walk speed reads, and takes the jump away with the walk while frozen.
function StatusService:_Refresh(Player: Player)
	local Factor = self:GetSpeedFactor(Player)

	Player:SetAttribute(SpeedAttribute, Factor)

	local Humanoid = GetHumanoid(Player)

	if not Humanoid then
		return
	end

	local Jump = self.Jumps[Player]

	if Factor <= 0 and not Jump then
		self.Jumps[Player] = { Height = Humanoid.JumpHeight, Power = Humanoid.JumpPower }
		Humanoid.JumpHeight = 0
		Humanoid.JumpPower = 0
		return
	end

	if Factor > 0 and Jump then
		self.Jumps[Player] = nil
		Humanoid.JumpHeight = Jump.Height
		Humanoid.JumpPower = Jump.Power
	end
end

--> A named speed modifier, for Seconds or until cleared. Setting one that is already running
--> replaces it, so a second goo puddle restarts the slow rather than stacking it.
function StatusService:Set(Player: Player, Name: string, Factor: number, Seconds: number?)
	local Modifiers = self.Modifiers[Player]

	if not Modifiers then
		Modifiers = {}
		self.Modifiers[Player] = Modifiers
	end

	Modifiers[Name] = {
		Factor = math.max(Factor, 0),
		Until = if Seconds then os.clock() + Seconds else math.huge,
	}

	self:_Refresh(Player)
end

function StatusService:Clear(Player: Player, Name: string)
	local Modifiers = self.Modifiers[Player]

	if not Modifiers or not Modifiers[Name] then
		return
	end

	Modifiers[Name] = nil

	self:_Refresh(Player)
end

function StatusService:Freeze(Player: Player, Seconds: number)
	self:Set(Player, "Freeze", 0, Seconds)
end

--> Every part and decal of the character goes clear and the name over it goes too. Whatever is
--> put on afterwards, a tool drawn in the meantime, shows: that is the cloak's edge, not a bug.
function StatusService:Hide(Player: Player, Seconds: number)
	local Character = Player.Character
	local Humanoid = GetHumanoid(Player)
	local Existing = self.Hidden[Player]

	if not Character or not Humanoid then
		return
	end

	if Existing and Existing.Character == Character then
		Existing.Until = os.clock() + Seconds
		return
	end

	local Parts = {}

	for _, Descendant in Character:GetDescendants() do
		if Descendant.Name == "HumanoidRootPart" then
			continue
		end

		if Descendant:IsA("BasePart") or Descendant:IsA("Decal") then
			Parts[Descendant] = Descendant.Transparency
			Descendant.Transparency = 1
		end
	end

	self.Hidden[Player] = {
		Character = Character,
		Parts = Parts,
		Display = Humanoid.DisplayDistanceType,
		Until = os.clock() + Seconds,
	}

	Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	Player:SetAttribute(HiddenAttribute, true)
end

function StatusService:Reveal(Player: Player)
	local Hidden = self.Hidden[Player]

	if not Hidden then
		return
	end

	self.Hidden[Player] = nil
	Player:SetAttribute(HiddenAttribute, false)

	--> a character that has been replaced since is not the one these parts are on
	if Hidden.Character ~= Player.Character then
		return
	end

	for Part, Transparency in Hidden.Parts do
		if Part.Parent then
			(Part :: any).Transparency = Transparency
		end
	end

	local Humanoid = Hidden.Character:FindFirstChildOfClass("Humanoid")

	if Humanoid then
		Humanoid.DisplayDistanceType = Hidden.Display
	end
end

--> Every limb the ragdoll cut loose from the root is an assembly of its own, and left alone the
--> engine hands each to whoever is standing nearest, which is usually the one who swung. Their
--> client then simulates the victim's arms against the victim's own body and both jitter. Given
--> to the victim, so the whole flop is one client's physics.
local function OwnLimbs(Player: Player, Character: Model)
	for _, Part in Character:GetDescendants() do
		if Part:IsA("BasePart") and Part:CanSetNetworkOwnership() then
			Part:SetNetworkOwner(Player)
		end
	end
end

--> Throws the character, limp. The joints are the server's to break, so everyone sees the body
--> go loose, but the root stays with the victim's client and the throw is handed to it to apply:
--> a character the server owns is replicated to every other screen at the server's physics rate,
--> which is the five frames a second the flop used to be drawn at. PlatformStand stops the
--> humanoid standing through it.
function StatusService:Fling(Player: Player, Velocity: Vector3)
	local Character = Player.Character
	local Humanoid = GetHumanoid(Player)
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	if not Character or not Humanoid or not Root or not Root:IsA("BasePart") or Humanoid.Health <= 0 then
		return
	end

	local Stamp = os.clock()

	self.Flung[Player] = Stamp

	--> The client is the one moving the root now, so the checks are told the throw rather than
	--> told to look away: speed along it is allowed, anything across it is still a walk.
	AntiCheatService:Excuse(Player, FlingTime, Velocity)

	Humanoid.PlatformStand = true

	--> a second hit while still limp keeps the joints it already has
	local Restore = self.Limp[Player] or Ragdoll(Character, Humanoid)

	self.Limp[Player] = Restore
	OwnLimbs(Player, Character)
	NetworkingServer.Gears.Flung.Fire(Player, Velocity)

	task.delay(FlingTime, function()
		if self.Flung[Player] ~= Stamp then
			return
		end

		self.Flung[Player] = nil
		self.Limp[Player] = nil

		if not Root.Parent or not Humanoid.Parent then
			return
		end

		Restore()
		Humanoid.PlatformStand = false
	end)
end

function StatusService:_HandlePlayer(Player: Player)
	--> a new character is not hidden, frozen or flung, whatever the old one was
	Player.CharacterAdded:Connect(function()
		self.Hidden[Player] = nil
		self.Jumps[Player] = nil
		self.Flung[Player] = nil
		self.Limp[Player] = nil
		Player:SetAttribute(HiddenAttribute, false)

		self:_Refresh(Player)
	end)
end

function StatusService:Init()
	for _, Player in Players:GetPlayers() do
		self:_HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:_HandlePlayer(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self.Modifiers[Player] = nil
		self.Hidden[Player] = nil
		self.Jumps[Player] = nil
		self.Flung[Player] = nil
		self.Limp[Player] = nil
	end)
end

--> Timed statuses run out on their own; this is what notices.
function StatusService:Start()
	task.spawn(function()
		while true do
			task.wait(TickRate)

			local Now = os.clock()

			for Player, Modifiers in self.Modifiers do
				for _, Modifier in Modifiers do
					if Modifier.Until <= Now then
						self:_Refresh(Player)
						break
					end
				end
			end

			for Player, Hidden in self.Hidden do
				if Hidden.Until <= Now then
					self:Reveal(Player)
				end
			end
		end
	end)
end

return StatusService
