local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local AntiCheatService = require(script.Parent.AntiCheatService)
local BaseLockingService = require(script.Parent.BaseLockingService)
local DeskData = require(Shared.Utilities.DeskData)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local EmployeeService = require(script.Parent.EmployeeService)
local Items = require(Shared.Utilities.Items)
local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local PlotService = require(script.Parent.PlotService)
local VisitService = require(script.Parent.VisitService)

--> Lifting an employee off somebody else's desk and carrying them home. Every fact the theft rests
--> on is the server's: whose base the thief is standing in comes from VisitService's sweep, whether
--> the door was shut on them from BaseLockingService, and how far they are from the desk from the
--> character the server holds. The client only says which desk. Until the thief is seen inside
--> their own base the employee is still the victim's, and getting caught -- dying, leaving, and
--> whatever a punch turns into -- sends them straight back to the desk they were taken from. Parts
--> are never stolen: they stay on the desk.

--> How far from the desk's own pivot the thief's root may be. The prompt reaches ten studs from
--> the chair, and the chair stands a few studs off the desk's middle; the rest is for lag.
local StealReach = 16

--> Thefts closer together than this are refused. One is a hold on a prompt; a dozen a second is a
--> script emptying an office.
local StealCooldown = 0.5

type Held = {
	Name: string?,
	Type: string?,
	StolenFrom: number?,
	StolenFloor: number?,
	StolenSlot: number?,
}

type Target = {
	Owner: Player,
	Floor: number,
	Slot: number,
}

local function GetRoot(Player: Player): BasePart?
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	return if Root and Root:IsA("BasePart") then Root else nil
end

--> Either kind: a part in the arms fills the hands as much as an employee does.
local function IsHeld(Item: any): boolean
	return Items.IsHeld(Item)
end

--> Only an employee is ever stolen, so only an employee carries the tag.
local function IsStolen(Item: any): boolean
	return Items.IsEmployee(Item) and type(Item.StolenFrom) == "number"
end

local StealingService = {
	Name = "StealingService",

	--> When each player last took something, for the cooldown. Cleared on the way out.
	LastSteal = {} :: { [Player]: number },
}

--> Sits a stolen employee back down: the same chair if it is still empty, otherwise the victim's
--> lowest empty one, and failing that they go into the victim's inventory. False when the victim
--> has gone or has no room anywhere, in which case the employee is simply lost -- which is still
--> the thief losing them.
function StealingService:Return(Held: Held): boolean
	local Victim = Players:GetPlayerByUserId(Held.StolenFrom :: number)
	local Data = Victim and PlayerData[Victim]
	local Name = Held.Name :: string
	local Type = Held.Type :: string

	--> A victim whose session was ended under them is still in the data table but writing to a
	--> save that will never be stored, so the profile is what says they can be given anything.
	if not Victim or not Data or not PlayerData.Service:getProfile(Victim) then
		return false
	end

	local Floor, Slot = Held.StolenFloor, Held.StolenSlot
	local Desk = if Floor and Slot then DeskData.Get(Data, Floor, Slot) else nil
	local Components = Desk and Desk()

	if type(Components) ~= "table" or Components.Employee ~= nil then
		Floor, Slot = DeskData.GetFreeSeat(Data)
	end

	if Floor and Slot and EmployeeService:SeatAt(Data, Floor, Slot, Name, Type) then
		return true
	end

	local Inventory = table.clone(Data.Inventory())

	if #Inventory >= Items.MaxInventory then
		return false
	end

	table.insert(Inventory, { Name = Name, Type = Type })
	Data.Inventory(Inventory)

	return true
end

--> The thief got caught. Whoever is in their arms that is not theirs goes back, and their hands
--> are emptied. Nothing happens to an employee that was already secured or that was theirs to
--> begin with. Public, so a punch has one thing to call.
function StealingService:Caught(Player: Player): boolean
	local Data = PlayerData[Player]

	if not Data then
		return false
	end

	local Held = Data.Holding()

	if not IsStolen(Held) then
		return false
	end

	self:Return(Held)
	Data.Holding({})

	return true
end

--> The thief made it home. The employee is theirs now: the tag comes off and it is an ordinary
--> carried employee, to be seated or put away.
function StealingService:Secure(Player: Player)
	local Data = PlayerData[Player]
	local Held = Data and Data.Holding()

	if not IsStolen(Held) then
		return
	end

	Data.Holding(Items.Strip(Held))
end

--> Whoever is carrying somebody of a leaver's keeps them. There is no desk left to send them back to.
function StealingService:Forfeit(Victim: Player)
	for _, Other in Players:GetPlayers() do
		local Data = PlayerData[Other]
		local Held = Data and Data.Holding()

		if IsStolen(Held) and Held.StolenFrom == Victim.UserId then
			Data.Holding(Items.Strip(Held))
		end
	end
end

function StealingService:Steal(Player: Player, Target: Target): { Name: string, Type: string }
	local Data = PlayerData[Player]
	assert(Data, `No loaded data for {Player.Name}`)

	local Owner = Target.Owner
	assert(Owner ~= Player, `{Player.Name} tried to steal from themselves`)

	local OwnerData = PlayerData[Owner]
	assert(OwnerData, `{Player.Name} tried to steal from {Owner.Name}, who has no loaded data`)

	assert(not IsHeld(Data.Holding()), `{Player.Name} tried to steal with full hands`)

	local Now = os.clock()
	local Last = self.LastSteal[Player]
	assert(not Last or Now - Last >= StealCooldown, `{Player.Name} is stealing too fast`)

	--> Whose base they are in is the sweep's word, not theirs. Refused rather than struck: the
	--> prompt reaches ten studs and the room boxes stop at the walls, so a hold finished from a
	--> doorway is an honest miss, and the sweep can move them out mid hold.
	assert(
		VisitService:GetVisiting(Player) == Owner,
		`{Player.Name} tried to steal from {Owner.Name}'s base while not in it`
	)

	--> Inside a locked base without having been there when it shut means they came through the
	--> wall. The lock's own sweep is already throwing them out; this makes sure they leave empty
	--> handed.
	if BaseLockingService:IsLocked(Owner) and not BaseLockingService:IsGuest(Owner, Player) then
		AntiCheatService:Flag(Player, "steal")
		error(`{Player.Name} tried to steal from {Owner.Name}'s locked base`)
	end

	local Desk = DeskData.Get(OwnerData, Target.Floor, Target.Slot)
	assert(Desk, `{Owner.Name} has no desk at floor {Target.Floor} slot {Target.Slot}`)

	local Components = Desk()
	assert(type(Components) == "table", `{Owner.Name}'s desk at {Target.Floor}/{Target.Slot} is empty`)

	local Employee = Components.Employee
	assert(Items.IsEmployee(Employee), `{Owner.Name}'s desk at {Target.Floor}/{Target.Slot} has nobody at it to take`)

	local Root = GetRoot(Player)
	assert(Root, `{Player.Name} has no character to steal with`)

	local Plot = PlotService:GetPlot(Owner)
	local DeskCFrame = Plot and DeskPlacements.GetCFrame(Plot, Target.Floor, Target.Slot)
	assert(DeskCFrame, `{Owner.Name}'s plot has no placement at floor {Target.Floor} slot {Target.Slot}`)

	assert(
		(DeskCFrame.Position - Root.Position).Magnitude <= StealReach,
		`{Player.Name} is too far from {Owner.Name}'s desk at {Target.Floor}/{Target.Slot} to steal from it`
	)

	--> Nothing above here yields, so what was checked is what is being taken. Spent only now, so a
	--> refused call cannot eat the cooldown a real one needs.
	self.LastSteal[Player] = Now

	local Taken = table.clone(Components)
	Taken.Employee = nil

	Desk(Taken)

	Data.Holding({
		Name = Employee.Name,
		Type = Employee.Type,
		StolenFrom = Owner.UserId,
		StolenFloor = Target.Floor,
		StolenSlot = Target.Slot,
	})

	--> the victim hears about it the moment it happens, wherever they are
	NetworkingServer.Notices.Stolen.Fire(Owner, { Thief = Player, Name = Employee.Name, Type = Employee.Type })

	return { Name = Employee.Name, Type = Employee.Type }
end

function StealingService:HandlePlayer(Player: Player)
	--> A save that comes back tagged is one the server lost before the thief was caught or made
	--> it home. The victim got theirs back on the way out, or never will; either way the tag now
	--> points at nothing, so the hands come back empty rather than holding somebody else's worker.
	task.spawn(function()
		local Data = PlayerData.Service:waitForData(Player)

		if Data and Player.Parent == Players and IsStolen(Data.Holding()) then
			Data.Holding({})
		end
	end)

	--> Dying is being caught. For now that is what a punch will end in as well.
	Player.CharacterAdded:Connect(function(Character: Model)
		local Humanoid = Character:WaitForChild("Humanoid", 10)

		if not Humanoid or not Humanoid:IsA("Humanoid") then
			return
		end

		Humanoid.Died:Connect(function()
			self:Caught(Player)
		end)
	end)
end

function StealingService:Init()
	NetworkingServer.Stealing.Steal.On(function(Player, Target)
		return self:Steal(Player, Target)
	end)

	VisitService.Changed:Connect(function(Player: Player, Owner: Player?)
		if Owner == Player then
			self:Secure(Player)
		end
	end)

	for _, Player in Players:GetPlayers() do
		self:HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:HandlePlayer(Player)
	end)

	--> Runs off the data service rather than PlayerRemoving, which fires after the save has
	--> already been let go of. Here the raw save is still in hand: a thief leaving mid chase hands
	--> the employee back before it is written, and a victim leaving hands theirs over.
	PlayerData.Service:addPlayerRemovingCallback(function(Player: Player, Raw: any)
		local Held = type(Raw) == "table" and Raw.Holding

		if IsStolen(Held) then
			self:Return(Held)
			Raw.Holding = {}
		end

		self:Forfeit(Player)
	end)

	--> Forfeited here as well: a player kicked because their profile session ended never reaches
	--> the data service's removal callbacks, and a thief left tagged against nobody would lose
	--> the employee the next time they were caught.
	Players.PlayerRemoving:Connect(function(Player: Player)
		self:Forfeit(Player)
		self.LastSteal[Player] = nil
	end)
end

return StealingService
