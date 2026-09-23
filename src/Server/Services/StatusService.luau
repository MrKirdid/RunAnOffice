local Players = game:GetService("Players")

--> What the gears do to a player, all in one place: slowed, sped up, frozen, hidden or flung.
--> Nothing here takes health. Speed is handed to MonetizationService as one attribute on the
--> player, the product of every modifier running, so it can fold it into the walk speed it
--> already owns; a frozen player is that attribute at 0.

local SpeedAttribute = "SpeedFactor"

--> set on the player while the cloak has them, so the tag over their head, which is drawn on
--> every client rather than on the character, knows to go with the rest of them
local HiddenAttribute = "Hidden"

--> How long a flung character is left to fly before it is stood back up and given back to its
--> own client, and how often timed statuses are looked over for ones that have run out.
local FlingTime = 1.2
local TickRate = 0.25

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
}

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

--> Throws the character. The server has to own the assembly for the velocity to take, so it is
--> taken for the length of the throw and handed back after; PlatformStand is what makes them
--> tumble rather than stand through it.
function StatusService:Fling(Player: Player, Velocity: Vector3)
	local Character = Player.Character
	local Humanoid = GetHumanoid(Player)
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	if not Humanoid or not Root or not Root:IsA("BasePart") then
		return
	end

	local CanOwn = Root:CanSetNetworkOwnership()

	if not CanOwn then
		return
	end

	local Stamp = os.clock()

	self.Flung[Player] = Stamp

	Root:SetNetworkOwner(nil)
	Humanoid.PlatformStand = true
	Root.AssemblyLinearVelocity = Velocity

	task.delay(FlingTime, function()
		if self.Flung[Player] ~= Stamp then
			return
		end

		self.Flung[Player] = nil

		if not Root.Parent or not Humanoid.Parent then
			return
		end

		Humanoid.PlatformStand = false

		if Root:CanSetNetworkOwnership() then
			Root:SetNetworkOwnershipAuto()
		end
	end)
end

function StatusService:_HandlePlayer(Player: Player)
	--> a new character is not hidden, frozen or flung, whatever the old one was
	Player.CharacterAdded:Connect(function()
		self.Hidden[Player] = nil
		self.Jumps[Player] = nil
		self.Flung[Player] = nil
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
