local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Assets = ReplicatedStorage.Assets

local PlotTemplate = Assets.Templates.PlotTemplate

local AntiCheatService = require(script.Parent.AntiCheatService)
local NetworkingServer = require(Shared.Networking.networkingServer)
local GameConfigs = require(Shared.Configs.GameConfigs)
local DeskData = require(Shared.Utilities.DeskData)
local PlotBounds = require(Shared.Utilities.PlotBounds)
local PlayerData = require(Shared.PlayerData).server
local PlotContainer = require(workspace.PlotContainer)

--> Published on the Player rather than sent over the wire. Attributes replicate to everyone on
--> their own, which is what lets a client hide the floors somebody else has not bought yet.
local FloorsAttribute = "UnlockedFloors"
local PadsAttribute = "RollPads"

--> How far above a marker a player is dropped, arriving at the plot or at one of its floors alike.
local DropHeight = 5

--> Arriving at the plot, the player is stood this much further out than the spawn marker, along
--> the line from the building to it, and turned to face the building: the first thing seen is the
--> office and the pads in front of it, not the street behind.
local SpawnSetback = 14

--> Floor moves closer together than this are refused. Every move gives the anti-cheat a moment
--> off, and a client asking for one every frame would never be looked at.
local TravelCooldown = 1

--> The upgrade tree used to be drawn twice, once as a screen and once on the face of this board.
--> It is a screen now, so the board comes off the copy before anyone can see it rather than being
--> left standing dead on every plot. The template still carries it; take it out of the template
--> and this finds nothing and does nothing.
local BoardName = "Upgrade Tree"

local function RemoveBoard(Plot: Model)
	local Boards = Plot:FindFirstChild("Boards")
	local Board = Boards and Boards:FindFirstChild(BoardName)

	if Board then
		Board:Destroy()
	end
end

--> The volume the first floor fills, which the arrival is measured off.
local function GetFloorVolume(Plot: Model, Floor: number): BasePart?
	local Floors = Plot:FindFirstChild("Floors")
	local Folder = Floors and Floors:FindFirstChild(tostring(Floor))
	local Volume = Folder and Folder:FindFirstChild("IsInFloor")

	return if Volume and Volume:IsA("BasePart") then Volume else nil
end

--> Where a player lands arriving at the plot: set back from the marker, facing the building. The
--> marker alone if the plot has no first floor volume to face.
local function GetArrival(Plot: Model): CFrame
	local Marker = (Plot:FindFirstChild("Positions") :: Folder):FindFirstChild("SpawnPosition") :: BasePart
	local Spawn = Marker.Position
	local Volume = GetFloorVolume(Plot, 1)
	local Away = if Volume then (Spawn - Volume.Position) * Vector3.new(1, 0, 1) else Vector3.zero

	if Away.Magnitude < 0.01 then
		return CFrame.new(Spawn + Vector3.new(0, DropHeight, 0))
	end

	local Spot = Spawn + Away.Unit * SpawnSetback + Vector3.new(0, DropHeight, 0)

	return CFrame.lookAt(Spot, Spot - Away.Unit)
end

local PlotService = {
	Plots = {} :: { [Player]: number },
	LastTravel = {} :: { [Player]: number },
	--> Which floors of each plot were last handed to the anti-cheat as hidden. Data changes every
	--> second with the cash, and the floors almost never, so the casts are only rebuilt on a change.
	Hidden = {} :: { [Model]: string },
}

--> A list rather than a count, because a command can unlock floor 3 without floor 2 and a count
--> would quietly hand the player the gap as well.
--> Data is looked up here rather than passed in. Holding the table handed over at join means
--> reading a snapshot that stops moving, so the attribute freezes on whatever floors the player
--> owned the moment they joined.
local function PublishFloors(Player: Player)
	local Data = PlayerData[Player]

	if not Data then
		return
	end

	local Text = {}

	for _, Floor in DeskData.GetFloors(Data) do
		table.insert(Text, tostring(Floor))
	end

	local Value = table.concat(Text, ",")

	--> Changed fires for anything under Floors, a desk being built included, so most calls here have
	--> nothing new to say. Writing the attribute anyway would replicate the same string to everyone
	--> every time somebody bought a desk.
	if Player:GetAttribute(FloorsAttribute) ~= Value then
		Player:SetAttribute(FloorsAttribute, Value)
	end
end

--> How many roll pads the player has, so every client can show the right ones on their plot and
--> not just on its own.
local function PublishPads(Player: Player)
	local Data = PlayerData[Player]

	if not Data then
		return
	end

	local Value = Data.RerollPads()

	if Player:GetAttribute(PadsAttribute) ~= Value then
		Player:SetAttribute(PadsAttribute, Value)
	end
end

function PlotService:NewPlot(Player: Player)
	local Taken = {}
	for _, Plot in self.Plots do
		Taken[Plot] = true
	end

	for Index = 1, GameConfigs.PlotAmount do
		if not Taken[Index] then
			self.Plots[Player] = Index
			break
		end
	end

	local PlotIndex = self.Plots[Player]
	local PlotLocation = PlotContainer[PlotIndex]

	local Plot = PlotTemplate:Clone()

	RemoveBoard(Plot)

	Plot.Parent = workspace.PlotContainer
	Plot.Name = PlotIndex

	Plot:PivotTo(PlotLocation)

	self:RefreshFloors(Player, Plot)

	return Plot
end

--> The floors a player owns, ascending. Floor 1 before their data has loaded, which is what every
--> save starts with. The one answer to "is this floor theirs" the base checks and the hidden floors
--> both read.
function PlotService:GetFloors(Player: Player): { number }
	local Data = PlayerData[Player]

	return if Data then DeskData.GetFloors(Data) else { 1 }
end

--> Every client hides the floors of a plot its owner has not bought, and walks through them, but
--> they stand solid on the server. The anti-cheat is told to look through them as well, so the
--> roof of a base is somewhere to stand rather than a wall to be put back out of.
--> The ceilings of the floors they do own go to the anti-cheat as well: the owner's client takes
--> the collision off the one over their head, so a jump or a fling can carry them up through it.
function PlotService:RefreshFloors(Player: Player, Plot: Model?)
	local Floors = Plot and Plot:FindFirstChild("Floors")

	if not Plot or not Floors then
		return
	end

	local Owned = self:GetFloors(Player)
	local Hidden = {}
	local Names = {}
	local Bought = {}

	for _, Folder in Floors:GetChildren() do
		local Floor = tonumber(Folder.Name)

		if not Floor then
			continue
		end

		if table.find(Owned, Floor) then
			table.insert(Bought, Folder)
			continue
		end

		table.insert(Hidden, Folder)
		table.insert(Names, Folder.Name)
	end

	table.sort(Names)

	local Key = table.concat(Names, ",")

	if self.Hidden[Plot] == Key then
		return
	end

	local Ceilings = {}

	for _, Folder in Bought do
		local Roof = PlotBounds.RoofOf(Folder)

		table.move(Roof, 1, #Roof, #Ceilings + 1, Ceilings)
	end

	self.Hidden[Plot] = Key
	AntiCheatService:SetHidden(Plot, Hidden)
	AntiCheatService:SetPassable(Player, Ceilings)
end

function PlotService:GetPlot(Player: Player): Model?
	local PlotIndex = self.Plots[Player]

	return PlotIndex and workspace.PlotContainer:FindFirstChild(tostring(PlotIndex))
end

--> The plot goes with its owner: the index is free again and the model comes down, so the next
--> player handed that index gets a fresh copy rather than a second one under the same name. It is
--> renamed at once, so nothing looking the index up finds it, and destroyed a frame later, so
--> everything else listening to the leave -- the lock coming off, the visitors being put out --
--> still has the model to read.
function PlotService:ReleasePlot(Player: Player)
	local Plot = self:GetPlot(Player)

	self.Plots[Player] = nil
	self.LastTravel[Player] = nil

	if not Plot then
		return
	end

	Plot.Name = "Released"
	self.Hidden[Plot] = nil
	AntiCheatService:SetHidden(Plot, {})

	task.defer(function()
		Plot:Destroy()
	end)
end

function PlotService:TeleportPlayerToPlot(Player: Player)
	--> Waited on rather than skipped: at join the plot is assigned before the character exists.
	if not Player.Character then
		Player.CharacterAdded:Wait()
	end

	local Plot = self:GetPlot(Player)

	if Plot then
		AntiCheatService:Teleport(Player, GetArrival(Plot))
	end
end

--> The floor has to be one the player owns and one the plot has a marker for; anything else is
--> refused and the character stays put. The move goes through the anti-cheat so it is not read
--> as the client having teleported.
function PlotService:TeleportPlayerToFloor(Player: Player, Floor: number): boolean
	local Data = PlayerData[Player]
	local Plot = self:GetPlot(Player)

	if not Data or not Plot or not Player.Character then
		return false
	end

	--> A thief carrying somebody else's employee walks it home. Travel works from anywhere, the
	--> hud's Home button included, so without this a steal would end in a teleport to safety.
	if Data.Holding().StolenFrom ~= nil then
		return false
	end

	local Now = os.clock()
	local Last = self.LastTravel[Player]

	if Last and Now - Last < TravelCooldown then
		return false
	end

	self.LastTravel[Player] = Now

	if not table.find(DeskData.GetFloors(Data), Floor) then
		return false
	end

	local Positions = Plot:FindFirstChild("Positions")
	local Marker = Positions and Positions:FindFirstChild(`Floor{Floor}`)

	if not Marker or not Marker:IsA("BasePart") then
		return false
	end

	AntiCheatService:Teleport(Player, CFrame.new(Marker.Position + Vector3.new(0, DropHeight, 0)))

	return true
end

function PlotService:Init()
	NetworkingServer.Plot.GetPlots.On(function()
		local Plots = self.Plots
		return Plots
	end)

	NetworkingServer.Floors.Travel.On(function(Player, Floor)
		return self:TeleportPlayerToFloor(Player, Floor)
	end)

	local function HandlePlayer(Player: Player)
		self:NewPlot(Player)
		NetworkingServer.Plot.UpdatePlots.FireAll(self.Plots)

		--> Spawned because the data is not loaded yet at join, and the plot itself must not wait
		--> on it: the player is standing on the plot either way.
		task.spawn(function()
			local Data = PlayerData.Service:waitForData(Player)

			self:RefreshFloors(Player, self:GetPlot(Player))
			PublishFloors(Player)
			PublishPads(Player)

			--> Bound to the root, which fires for anything underneath it, and re-reads the data
			--> every time rather than trusting the value it was handed.
			Data.Changed(function()
				PublishFloors(Player)
				PublishPads(Player)
				self:RefreshFloors(Player, self:GetPlot(Player))
			end)
		end)

		self:TeleportPlayerToPlot(Player)

		Player.CharacterAdded:Connect(function()
			self:TeleportPlayerToPlot(Player)
		end)
	end

	for _, Player in Players:GetPlayers() do
		task.spawn(HandlePlayer, Player)
	end

	Players.PlayerAdded:Connect(HandlePlayer)

	Players.PlayerRemoving:Connect(function(Player)
		self:ReleasePlot(Player)
		NetworkingServer.Plot.UpdatePlots.FireAll(self.Plots)
	end)
end

return PlotService
