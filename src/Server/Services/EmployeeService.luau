local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local Employees = require(Shared.Configs.Employees)
local NameList = require(Shared.Configs.NameList)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local DeskData = require(Shared.Utilities.DeskData)
local Tiers = require(Shared.Utilities.Tiers)
local PlayerData = require(Shared.PlayerData).server
local Offsets = require(Shared.Configs.Offsets)
local Revenue = require(Shared.Utilities.Revenue)
local Rolling = require(Shared.Utilities.Rolling)
local Store = require(Shared.Utilities.Store)
local PlotService = require(script.Parent.PlotService)

local NameRandom = Random.new()

--> Odds never move with luck for a readout, so the whole table is worth one pass at require time
local BaseOdds = Rolling.Chances(Employees, 1)

type Employee = {
	Name: string,
	Type: string,
	UID: number,
	Cost: number,
}

type Seat = {
	Floor: number,
	Slot: number,
}

type Tracked = {
	LastBoughtBy: Player?,
	Employee: Employee,
	--> The desk this one is walking to, claimed at purchase so two bought back to back cannot
	--> both head for the last free one. Held here rather than written into the desk, so a server
	--> that dies mid walk leaves the seat free rather than half filled.
	Seat: Seat?,
	TargetVector: Vector3,
	--> Legs still to walk after the current one. Empty means TargetVector is the last stop.
	Path: { Vector3 },
	Position: Vector3,
	Velocity: Vector3,
}

local MoveSpeed = 8
local TurnRate = 5
local ArriveDistance = 0.5

local TickRate = 1 / 10
local BatchSize = 255

local GroundLift = 6
local GroundDrop = 60
local MaxGroundHits = 4

local MarkerNames = { EmployeeSpawn = true, EmployeeEnd = true }
local WaypointName = "EmployeeHaveToGoTo"

local NextUID = 0

--> Multiplies the luck every employee spawn rolls at, for the whole server. Deliberately scoped to
--> employees and not persisted: a general server luck that stacks on top of every other roll is a
--> separate thing, and this one resets when the server does.
local SpawnLuck = 1

local GroundParams: RaycastParams? = nil

--> What the employee branch of the upgrade tree scales. Only a bought employee has an owner, so an
--> unsold one always walks at the base speed no matter who is on the server.
local function SpeedFor(Owner: Player?): number
	local Data = if Owner then PlayerData[Owner] else nil

	return if Data then Data.Multipliers.EmployeeSpeed() else 1
end

local EmployeeService = {
	Employees = {} :: { [number]: Tracked },
}

local Spawned: { { UID: number, Name: string, Type: string, Cost: number, Position: Vector3, Owner: Player? } } = {}
local Moved: { { UID: number, Position: Vector3 } } = {}
local Removed: { number } = {}
local OwnerChanged: { { UID: number, Owner: Player? } } = {}

local function PickName(): string
	return NameList[NameRandom:NextInteger(1, #NameList)]
end

local function GetMarker(Name: string): BasePart
	return workspace:WaitForChild("Map"):WaitForChild(Name) :: BasePart
end

local function GetGroundParams(): RaycastParams
	if not GroundParams then
		local Map = workspace:WaitForChild("Map")

		local Params = RaycastParams.new()
		Params.FilterType = Enum.RaycastFilterType.Include
		Params.FilterDescendantsInstances = { Map }

		GroundParams = Params
	end

	return GroundParams :: RaycastParams
end

--> The spawn and end markers have decorative pads sitting under them, and those pads are floor as
--> far as a downward cast is concerned. Landing on one puts the employee a couple of studs above
--> the walkway and it drops off the edge on its first step, which reads as a jump.
local function IsMarkerDecor(Hit: BasePart): boolean
	local Current: Instance? = Hit

	while Current and Current ~= workspace do
		if MarkerNames[Current.Name] then
			return true
		end

		Current = Current.Parent
	end

	return false
end

--> Casts past the markers rather than switching them off, so they keep whatever collision the
--> map gave them.
local function Ground(Position: Vector3): Vector3
	local Params = GetGroundParams()
	local Top = Position.Y + GroundLift
	local Bottom = Position.Y - GroundDrop
	local Height = Top

	for _ = 1, MaxGroundHits do
		local Reach = Bottom - Height

		if Reach >= 0 then
			return Position
		end

		local Origin = Vector3.new(Position.X, Height, Position.Z)
		local Result = workspace:Raycast(Origin, Vector3.new(0, Reach, 0), Params)

		if not Result then
			return Position
		end

		if not IsMarkerDecor(Result.Instance) then
			return Vector3.new(Position.X, Result.Position.Y, Position.Z)
		end

		--> Just under what was hit, so the next cast starts below the pad instead of on it
		Height = Result.Position.Y - 0.05
	end

	return Position
end

--> Where an employee headed for this seat ends up. A desk on the ground floor is walked to
--> directly; anything higher up is walked to the ground floor's pad instead, and the employee is
--> taken off the map there and reappears already sat down.
local function GetSeatTarget(Plot: Model, Seat: Seat): Vector3?
	if Seat.Floor == 1 then
		local DeskCFrame = DeskPlacements.GetCFrame(Plot, Seat.Floor, Seat.Slot)

		return DeskCFrame and (DeskCFrame * Offsets.EmployeeDeskOffset).Position
	end

	local Floors = Plot:FindFirstChild("Floors")
	local GroundFloor = Floors and Floors:FindFirstChild("1")
	local Pad = GroundFloor and GroundFloor:FindFirstChild("TeleportPad")

	return Pad and (Pad :: BasePart).Position
end

--> Every bought employee routes through the plot's own waypoint before its seat, so they all
--> enter the building the same way instead of cutting whatever line is shortest.
local function GetSeatPath(Player: Player, Seat: Seat): { Vector3 }?
	local Plot = PlotService:GetPlot(Player)
	local Target = Plot and GetSeatTarget(Plot, Seat)

	if not Plot or not Target then
		return nil
	end

	local Positions = Plot:FindFirstChild("Positions")
	local Waypoint = Positions and Positions:FindFirstChild(WaypointName)

	if Waypoint then
		return { (Waypoint :: BasePart).Position, Target }
	end

	return { Target }
end

--> Seats already promised to an employee on its way over, which are not free to promise again.
local function GetClaimed(Player: Player): { [string]: boolean }
	local Claimed = {}

	for _, Tracked in EmployeeService.Employees do
		local Seat = Tracked.Seat

		if Seat and Tracked.LastBoughtBy == Player then
			Claimed[`{Seat.Floor}-{Seat.Slot}`] = true
		end
	end

	return Claimed
end

local function ToSpawn(Employee: Tracked)
	return {
		UID = Employee.Employee.UID,
		Name = Employee.Employee.Name,
		Type = Employee.Employee.Type,
		Cost = Employee.Employee.Cost,
		Position = Employee.Position,
		Owner = Employee.LastBoughtBy,
	}
end

local function FlushBatch<T>(FireAll: ({ T }) -> (), Batch: { T })
	local Count = #Batch

	if Count == 0 then
		return
	end

	for Start = 1, Count, BatchSize do
		FireAll(table.move(Batch, Start, math.min(Start + BatchSize - 1, Count), 1, {}))
	end

	table.clear(Batch)
end

function EmployeeService:NewEmployee(EmployeeData: Employee): Tracked
	local Employee: Tracked = {
		LastBoughtBy = nil,
		Employee = EmployeeData,
		TargetVector = Ground(GetMarker("EmployeeEnd").Position),
		Path = {},
		Position = Ground(GetMarker("EmployeeSpawn").Position),
		Velocity = Vector3.new(0, 0, 0),
	}

	EmployeeService.Employees[EmployeeData.UID] = Employee
	table.insert(Spawned, ToSpawn(Employee))

	return Employee
end

function EmployeeService:RemoveEmployee(UID: number)
	if not EmployeeService.Employees[UID] then
		return
	end

	EmployeeService.Employees[UID] = nil
	table.insert(Removed, UID)
end

function EmployeeService:SetOwner(UID: number, Owner: Player?)
	local Employee = EmployeeService.Employees[UID]

	if not Employee or Employee.LastBoughtBy == Owner then
		return
	end

	Employee.LastBoughtBy = Owner
	table.insert(OwnerChanged, { UID = UID, Owner = Owner })
end

--> Sitting down is a write into the owner's desk and nothing else: the walking copy is dropped on
--> the spot, and from here on the seat in their data is the only record the employee exists.
function EmployeeService:SeatAt(Data: any, Floor: number, Slot: number, Name: string, Type: string): boolean
	local Desk = DeskData.Get(Data, Floor, Slot)
	local Components = Desk and Desk()

	if not Desk or type(Components) ~= "table" then
		return false
	end

	local Seated = table.clone(Components)
	Seated.Employee = { Name = Name, Type = Type, HiredAt = os.time() }

	Desk(Seated)

	return true
end

--> The reverse of SeatAt: the seat is emptied and half the hire price comes back. Floor and Slot
--> are the client's word, so the desk is looked up in the caller's own data and nowhere else,
--> which is what keeps this from selling anyone off somebody else's desk.
function EmployeeService:Sell(Player: Player, Floor: number, Slot: number): boolean
	local Data = PlayerData[Player]
	local Desk = Data and DeskData.Get(Data, Floor, Slot)
	local Components = Desk and Desk()

	if not Desk or type(Components) ~= "table" then
		return false
	end

	local Employee = Components.Employee

	if type(Employee) ~= "table" or type(Employee.Type) ~= "string" then
		return false
	end

	local Refund = Revenue.SellValue(Employee.Type)

	local Emptied = table.clone(Components)
	Emptied.Employee = nil

	Desk(Emptied)

	Data.Cash(function(Current: number)
		return Current + Refund
	end)

	return true
end

--> Both seats are looked up in the caller's own data, so the four numbers can say anything and
--> still only ever move the caller's own worker between the caller's own desks. A target with
--> somebody already sat at it is a swap: the two change places. A seat promised to one still
--> walking over counts as taken, or the walker would arrive to find it filled.
function EmployeeService:Move(Player: Player, From: Seat, To: Seat): boolean
	if From.Floor == To.Floor and From.Slot == To.Slot then
		return false
	end

	local Data = PlayerData[Player]

	if not Data then
		return false
	end

	local Source = DeskData.Get(Data, From.Floor, From.Slot)
	local Target = DeskData.Get(Data, To.Floor, To.Slot)
	local SourceParts = Source and Source()
	local TargetParts = Target and Target()

	if not Source or not Target or type(SourceParts) ~= "table" or type(TargetParts) ~= "table" then
		return false
	end

	local Employee = SourceParts.Employee

	if type(Employee) ~= "table" then
		return false
	end

	if GetClaimed(Player)[`{To.Floor}-{To.Slot}`] then
		return false
	end

	local Other = TargetParts.Employee

	local Filled = table.clone(TargetParts)
	Filled.Employee = table.clone(Employee)

	local Emptied = table.clone(SourceParts)
	Emptied.Employee = if type(Other) == "table" then table.clone(Other) else nil

	Target(Filled)
	Source(Emptied)

	return true
end

function EmployeeService:Arrived(Employee: Tracked, Owner: Player)
	local Seat = Employee.Seat
	local Data = Seat and PlayerData[Owner]

	--> The desk can be gone by now, which loses the employee. Only admin tooling clears one.
	if not Seat or not Data then
		return
	end

	self:SeatAt(Data, Seat.Floor, Seat.Slot, Employee.Employee.Name, Employee.Employee.Type)
end

--> Buying is a redirect rather than a claim: one already walking to somebody's plot is still for
--> sale, and buying it just points it at a different desk. Nothing checks whether it is owned
--> already, only that it is not owned by the buyer.
function EmployeeService:Buy(Player: Player, UID: number): boolean
	local Employee = EmployeeService.Employees[UID]

	if not Employee or Employee.LastBoughtBy == Player then
		return false
	end

	local Data = PlayerData[Player]

	if not Data then
		return false
	end

	local Cost = Employee.Employee.Cost

	if Data.Cash() < Cost then
		return false
	end

	local Floor, Slot = DeskData.GetFreeSeat(Data, GetClaimed(Player))

	if not Floor or not Slot then
		return false
	end

	local Seat: Seat = { Floor = Floor, Slot = Slot }
	local Path = GetSeatPath(Player, Seat)

	if not Path then
		return false
	end

	--> Every reason to turn this down is out of the way, so the charge lands with the redirect
	Data.Cash(function(Current: number)
		return math.max(Current - Cost, 0)
	end)

	self:SetOwner(UID, Player)

	Employee.Seat = Seat
	Employee.TargetVector = table.remove(Path, 1) :: Vector3
	Employee.Path = Path

	return true
end

function EmployeeService:GetCost(Type: string): number
	return Revenue.HireCost(Type)
end

--> One line of console readout. Odds come off the plain table rather than whatever luck the roll
--> ran at, so the tier printed is the one the employee will carry around on its card.
function EmployeeService:Describe(Employee: Employee): string
	local Config = Employees[Employee.Type]
	local Chance = BaseOdds[Employee.Type]
	local Odds = if Chance and Chance > 0 then 1 / Chance else math.huge
	local Tier = Tiers.FromOdds(Odds)

	local Multiplier = if Config then Config.Value else 1
	local Rarity = if Odds < math.huge then `1 in {math.floor(Odds + 0.5)}` else "1 in ???"

	return `{Employee.Name} the {Employee.Type} — {Tier}, {Multiplier}x, ${Employee.Cost}, {Rarity}`
end

function EmployeeService:GetSpawnLuck(): number
	return SpawnLuck
end

function EmployeeService:SetSpawnLuck(Value: number): number
	SpawnLuck = math.max(Value, 0)

	return SpawnLuck
end

--> Force names the type outright and skips the roll, which is how the console spawns a specific one.
function EmployeeService:RollEmployee(Luck: number?, Force: string?): Employee
	--> the console's spawn luck and the bought server luck both lift every spawn in the server
	local Type = Force or Rolling.Pick(Employees, (Luck or 1) * SpawnLuck * Store.ServerLuck())

	NextUID += 1

	return {
		Name = PickName(),
		Type = Type,
		UID = NextUID,
		Cost = self:GetCost(Type),
	}
end

function EmployeeService:Start()
	local SpawnRate = 5

	NetworkingServer.Employees.GetAll.On(function()
		local All = {}

		for _, Employee in EmployeeService.Employees do
			table.insert(All, ToSpawn(Employee))
		end

		return All
	end)

	NetworkingServer.Employees.Buy.On(function(Player: Player, UID: number)
		return self:Buy(Player, UID)
	end)

	NetworkingServer.Employees.Sell.On(function(Player: Player, Seat: { Floor: number, Slot: number })
		return self:Sell(Player, Seat.Floor, Seat.Slot)
	end)

	NetworkingServer.Employees.Move.On(
		function(Player: Player, Seats: { FromFloor: number, FromSlot: number, ToFloor: number, ToSlot: number })
			return self:Move(
				Player,
				{ Floor = Seats.FromFloor, Slot = Seats.FromSlot },
				{ Floor = Seats.ToFloor, Slot = Seats.ToSlot }
			)
		end
	)

	task.spawn(function()
		while true do
			task.wait(SpawnRate)
			self:NewEmployee(self:RollEmployee())
		end
	end)

	task.spawn(function()
		local LastTick = os.clock()

		while true do
			task.wait(TickRate)

			local Now = os.clock()
			local DeltaTime = Now - LastTick
			LastTick = Now

			for _, Employee in EmployeeService.Employees do
				--> Flat, because a desk sits at whatever height its floor is and the walk is
				--> grounded separately. Measuring the drop as distance means never arriving.
				local ToTarget = (Employee.TargetVector - Employee.Position) * Vector3.new(1, 0, 1)
				local Distance = ToTarget.Magnitude

				if Distance < ArriveDistance then
					local Next = table.remove(Employee.Path, 1)

					--> A stop along the way, so pick the next leg up and keep walking
					if Next then
						Employee.TargetVector = Next
						continue
					end

					local Owner = Employee.LastBoughtBy

					if Owner then
						self:Arrived(Employee, Owner)
					end

					self:RemoveEmployee(Employee.Employee.UID)
					continue
				end

				local Desired = ToTarget.Unit * (MoveSpeed * SpeedFor(Employee.LastBoughtBy))

				local Blend = 1 - math.exp(-TurnRate * DeltaTime)
				Employee.Velocity = Employee.Velocity:Lerp(Desired, Blend)

				local Step = Employee.Velocity * DeltaTime

				if Step.Magnitude >= Distance then
					Employee.Position = Employee.TargetVector
					Employee.Velocity = Vector3.zero
				else
					Employee.Position += Step
				end

				Employee.Position = Ground(Employee.Position)

				table.insert(Moved, { UID = Employee.Employee.UID, Position = Employee.Position })
			end

			FlushBatch(NetworkingServer.Employees.Added.FireAll, Spawned)
			FlushBatch(NetworkingServer.Employees.OwnerChanged.FireAll, OwnerChanged)
			FlushBatch(NetworkingServer.Employees.Moved.FireAll, Moved)
			FlushBatch(NetworkingServer.Employees.Removed.FireAll, Removed)
		end
	end)
end

return EmployeeService
