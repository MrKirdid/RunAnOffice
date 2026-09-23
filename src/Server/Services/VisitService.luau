local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared

local DeskData = require(Shared.Utilities.DeskData)
local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local PlotBounds = require(Shared.Utilities.PlotBounds)
local PlotService = require(script.Parent.PlotService)
local Signal = require(Shared.Packages.Fastsignal)

--> Somebody else's desks are only ever drawn on a client standing inside that base. What is sent is
--> decided here, off where the server sees each character, and never off anything the client says
--> about where it is: walking in gets you the desks and whoever is sat at them, walking out takes
--> them away, and while you are in, every change to one of them is pushed as it happens. Nothing
--> about the roll pads goes out at all, and nothing goes to anyone standing in the street.

--> How often every character is checked against every base.
local SweepInterval = 0.2

local ContainerName = "PlotContainer"

--> The three part slots a visitor is shown.
local Slots = { "Computer", "Keyboard", "Monitor" }

type Desk = {
	Floor: number,
	Slot: number,
	Computer: string?,
	Keyboard: string?,
	Monitor: string?,
	Employee: string?,
	EmployeeName: string?,
}

local function GetRoot(Player: Player): BasePart?
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	return if Root and Root:IsA("BasePart") then Root else nil
end

--> One desk as a visitor is allowed to see it: the parts standing on it, and the employee sat at
--> it by type and name, which is what the thief's prompt and the card over their head both want.
--> A slot never rolled comes out as nothing.
local function Summarise(Floor: number, Slot: number, Components: any): Desk
	local Summary: Desk = { Floor = Floor, Slot = Slot }

	if type(Components) ~= "table" then
		return Summary
	end

	for _, Name in Slots do
		local Variant = Components[Name]

		if DeskData.IsPart(Variant) then
			(Summary :: any)[Name] = Variant
		end
	end

	local Employee = Components.Employee

	if type(Employee) == "table" and type(Employee.Type) == "string" then
		Summary.Employee = Employee.Type
		Summary.EmployeeName = if type(Employee.Name) == "string" then Employee.Name else Employee.Type
	end

	return Summary
end

local VisitService = {
	Name = "VisitService",

	--> Whose base each player is standing in, their own included; nil out in the street. Written
	--> only by the sweep, so a claim from a client never reaches it.
	Visiting = {} :: { [Player]: Player },

	--> Everyone standing in each player's base other than the owner: who a desk change is sent to.
	Visitors = {} :: { [Player]: { [Player]: boolean } },

	--> Fired with the player and the owner of the base they are now in, or nil, whenever it
	--> changes. StealingService rides it to know when a thief has made it home.
	Changed = Signal.new(),
}

--> The owner of whichever base a point is inside, or nil. Plots are walked rather than indexed
--> because there are eight of them and the answer has to come off the same boxes the lock reads.
function VisitService:FindOwner(Position: Vector3): Player?
	local Container = workspace:FindFirstChild(ContainerName)

	if not Container then
		return nil
	end

	for Owner, Index in PlotService.Plots do
		local Plot = Container:FindFirstChild(tostring(Index))

		if Plot and Plot:IsA("Model") and PlotBounds.IsInside(Plot, Position) then
			return Owner
		end
	end

	return nil
end

--> Whose base the server last saw this player standing in.
function VisitService:GetVisiting(Player: Player): Player?
	return self.Visiting[Player]
end

function VisitService:Snapshot(Owner: Player): { Desk }
	local Data = PlayerData[Owner]
	local Desks = {}

	if not Data then
		return Desks
	end

	for _, Floor in DeskData.GetFloors(Data) do
		for _, Slot in DeskData.GetSlots(Data, Floor) do
			local Desk = DeskData.Get(Data, Floor, Slot)

			table.insert(Desks, Summarise(Floor, Slot, Desk and Desk()))
		end
	end

	return Desks
end

--> One desk of one base, to everyone standing in it. Read fresh off the save rather than off what
--> the callback was handed: a floor being taken away fires its desks with stale values, and what
--> matters is only what is standing there now.
function VisitService:Push(Owner: Player, Floor: number, Slot: number)
	local Visitors = self.Visitors[Owner]

	if not Visitors or next(Visitors) == nil then
		return
	end

	local Data = PlayerData[Owner]

	if not Data then
		return
	end

	local Desk = DeskData.Get(Data, Floor, Slot)
	local Components = Desk and Desk()
	local List = {}

	for Visitor in Visitors do
		table.insert(List, Visitor)
	end

	NetworkingServer.Visiting.DeskChanged.FireList(List, {
		Owner = Owner,
		Desk = Summarise(Floor, Slot, Components),
		Removed = type(Components) ~= "table",
	})
end

--> The player has crossed into a different base, or out of one. The old owner's visitors lose
--> them and they are told so; the new owner's gain them and they are handed the desks.
function VisitService:Move(Player: Player, Owner: Player?)
	local Previous = self.Visiting[Player]

	self.Visiting[Player] = Owner

	if Previous and Previous ~= Player then
		local Visitors = self.Visitors[Previous]

		if Visitors then
			Visitors[Player] = nil
		end

		if Player.Parent == Players then
			NetworkingServer.Visiting.Left.Fire(Player, Previous)
		end
	end

	if Owner and Owner ~= Player then
		local Visitors = self.Visitors[Owner]

		if not Visitors then
			Visitors = {}
			self.Visitors[Owner] = Visitors
		end

		Visitors[Player] = true

		NetworkingServer.Visiting.Entered.Fire(Player, {
			Owner = Owner,
			Desks = self:Snapshot(Owner),
		})
	end

	self.Changed:Fire(Player, Owner)
end

function VisitService:Sweep()
	for _, Player in Players:GetPlayers() do
		local Root = GetRoot(Player)
		local Owner = if Root then self:FindOwner(Root.Position) else nil

		if Owner ~= self.Visiting[Player] then
			self:Move(Player, Owner)
		end
	end
end

--> Every desk of one save, watched the way the owner's own client watches it: a floor opening or
--> closing, a desk being bought or sold, and a desk's parts changing under it. Whatever fires,
--> Push reads the desk again and sends what it finds.
function VisitService:WatchOwner(Owner: Player)
	local Data = PlayerData.Service:waitForData(Owner)

	if not Data or Owner.Parent ~= Players then
		return
	end

	local function WatchDesk(FloorKey: any, SlotKey: any)
		Data.Floors[FloorKey].Desks[SlotKey].Changed(function()
			self:Push(Owner, tonumber(FloorKey) :: number, tonumber(SlotKey) :: number)
		end)
	end

	local function WatchFloor(FloorKey: any)
		local Desks = Data.Floors[FloorKey].Desks

		for SlotKey in Desks() do
			WatchDesk(FloorKey, SlotKey)
		end

		Desks.OnKeyAdded(function(SlotKey: any)
			WatchDesk(FloorKey, SlotKey)
			self:Push(Owner, tonumber(FloorKey) :: number, tonumber(SlotKey) :: number)
		end)
	end

	for FloorKey in Data.Floors() do
		WatchFloor(FloorKey)
	end

	Data.Floors.OnKeyAdded(function(FloorKey: any)
		WatchFloor(FloorKey)
	end)

	--> A floor going takes every desk on it, and the desks themselves are not told cleanly. The
	--> record that was removed says which slots stood there; Push finds each of them gone.
	Data.Floors.OnKeyRemoved(function(FloorKey: any, Previous: any)
		local Desks = type(Previous) == "table" and Previous.Desks

		if type(Desks) ~= "table" then
			return
		end

		for SlotKey in Desks do
			self:Push(Owner, tonumber(FloorKey) :: number, tonumber(SlotKey) :: number)
		end
	end)

	--> The plot is handed out before the save arrives, so anyone already standing in it was sent
	--> an empty base. Nothing above fires for desks that were in the save all along; they are
	--> sent again now, whole.
	local Visitors = self.Visitors[Owner]

	if Visitors then
		for Visitor in Visitors do
			NetworkingServer.Visiting.Entered.Fire(Visitor, {
				Owner = Owner,
				Desks = self:Snapshot(Owner),
			})
		end
	end
end

function VisitService:HandlePlayer(Player: Player)
	task.spawn(function()
		self:WatchOwner(Player)
	end)
end

function VisitService:Init()
	for _, Player in Players:GetPlayers() do
		self:HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:HandlePlayer(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self:Move(Player, nil)

		--> The base goes with its owner, and the ground under anyone stood in it goes too, so they
		--> are sent home rather than left to fall through where it was.
		local Visitors = self.Visitors[Player]

		if Visitors then
			for Visitor in Visitors do
				self:Move(Visitor, nil)

				task.spawn(function()
					PlotService:TeleportPlayerToPlot(Visitor)
				end)
			end
		end

		self.Visitors[Player] = nil
		self.Visiting[Player] = nil
	end)
end

function VisitService:Start()
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

return VisitService
