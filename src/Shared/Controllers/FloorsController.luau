local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotController = require(Shared.Controllers.PlotController)
local PlayerData = require(Shared.PlayerData).client

local GuiName = "FloorsUI"
local PadName = "TeleportPad"
local PlacementsName = "Desk Placements"
local ContainerName = "PlotContainer"

--> The box PlotTemplate carries on every floor, sized to cover the whole room. Standing inside one
--> is what hides the floors stacked above it.
local BoundsName = "IsInFloor"

--> Written by PlotService. Attributes replicate on their own, so this is how the client learns
--> which floors somebody else has bought without asking the server for them.
local FloorsAttribute = "UnlockedFloors"

--> Same drop PlotService uses when it puts you on your plot, so arriving on a floor feels the same
--> as arriving at the plot.
local DropHeight = 5

--> Touched fires every frame a limb is on the pad; without this the menu reopens the moment it closes.
local PadCooldown = 1

local LocalPlayer = Players.LocalPlayer

local FloorsController = {
	Gui = nil :: ScreenGui?,

	--> What each part looked like before it was hidden, so showing a floor puts it back exactly
	--> rather than guessing at 0 and true.
	Restore = {} :: { [BasePart]: { Transparency: number, CanCollide: boolean } },

	--> Which floor of your own plot you are standing in, nil when you are outside every box. Cached
	--> so the sweep only runs when it changes rather than every heartbeat.
	Inside = nil :: number?,

	NextPad = 0,
	Bound = {} :: { [BasePart]: boolean },
	Watched = {} :: { [Player]: boolean },
}

local function GetContainer(): Instance?
	return workspace:FindFirstChild(ContainerName)
end

--> A save round trip turns numeric keys into strings, so match on the number either way.
local function LocalUnlocked(): { [number]: boolean }
	local Unlocked = {}

	for Floor in PlayerData.Floors() do
		local Number = tonumber(Floor)

		if Number then
			Unlocked[Number] = true
		end
	end

	return Unlocked
end

--> A list rather than a count, because an admin command can unlock floor 3 without floor 2 and a
--> count would quietly fill the gap back in.
local function AttributeUnlocked(Player: Player): { [number]: boolean }
	local Unlocked = {}
	local Raw = Player:GetAttribute(FloorsAttribute)

	if type(Raw) ~= "string" then
		return Unlocked
	end

	for Piece in string.gmatch(Raw, "%d+") do
		local Floor = tonumber(Piece)

		if Floor then
			Unlocked[Floor] = true
		end
	end

	return Unlocked
end

--> Your own floors come from your data rather than the attribute: it is already loaded by the time
--> anything here runs, so your base never flickers waiting on a replicated string.
local function UnlockedFor(Player: Player): { [number]: boolean }
	if Player == LocalPlayer then
		return LocalUnlocked()
	end

	return AttributeUnlocked(Player)
end

--> Which floor of a plot a point sits inside, or nil when it is outside every box. The plot is
--> pivoted into place, so the boxes are rotated with it: the test has to run in the box's own space
--> rather than comparing world axes.
local function FloorAt(Floors: Instance, Position: Vector3): number?
	for _, Folder in Floors:GetChildren() do
		local Floor = tonumber(Folder.Name)
		local Box = Folder:FindFirstChild(BoundsName)

		if not Floor or not Box or not Box:IsA("BasePart") then
			continue
		end

		local Offset = Box.CFrame:PointToObjectSpace(Position)
		local Half = Box.Size / 2

		local Within = math.abs(Offset.X) <= Half.X
			and math.abs(Offset.Y) <= Half.Y
			and math.abs(Offset.Z) <= Half.Z

		if Within then
			return Floor
		end
	end

	return nil
end

function FloorsController:GetGui(): ScreenGui?
	if self.Gui and self.Gui.Parent then
		return self.Gui
	end

	local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
	self.Gui = PlayerGui and PlayerGui:FindFirstChild(GuiName) :: ScreenGui?

	return self.Gui
end

function FloorsController:GetList(): ScrollingFrame?
	local Gui = self:GetGui()
	local Outer = Gui and Gui:FindFirstChild("MainBackground")
	local Inner = Outer and Outer:FindFirstChild("MainBackground")

	return Inner and Inner:FindFirstChild("ScrollingFrame") :: ScrollingFrame?
end

function FloorsController:Open()
	local Gui = self:GetGui()

	if Gui then
		self:RefreshList()
		Gui.Enabled = true
	end
end

function FloorsController:Close()
	local Gui = self:GetGui()

	if Gui then
		Gui.Enabled = false
	end
end

--> Rows for floors you do not own yet come out of the list entirely. UIListLayout skips hidden
--> children, so the remaining rows close the gap on their own.
function FloorsController:RefreshList()
	local List = self:GetList()

	if not List then
		return
	end

	local Unlocked = LocalUnlocked()

	for _, Row in List:GetChildren() do
		local Floor = tonumber(Row.Name)

		if Floor and Row:IsA("GuiObject") then
			Row.Visible = Unlocked[Floor] == true
		end
	end
end

--> Hidden rather than destroyed, because a floor has to be able to come straight back the moment
--> you buy it or step out of the room below it.
function FloorsController:SetShown(Folder: Instance, Show: boolean)
	for _, Part in Folder:GetDescendants() do
		if not Part:IsA("BasePart") then
			continue
		end

		--> Desk Placements are invisible markers the desk builder reads; leave them be.
		if Part.Parent ~= nil and Part.Parent.Name == PlacementsName then
			continue
		end

		--> The bounds box is a marker too. The template ships it half transparent so it can be seen
		--> while editing, and drawing it in game would drop a tinted cube over the whole room.
		if Part.Name == BoundsName then
			Part.Transparency = 1
			continue
		end

		if Show then
			local Original = self.Restore[Part]

			if Original then
				Part.Transparency = Original.Transparency
				Part.CanCollide = Original.CanCollide
				self.Restore[Part] = nil
			end
		elseif not self.Restore[Part] then
			self.Restore[Part] = { Transparency = Part.Transparency, CanCollide = Part.CanCollide }

			Part.Transparency = 1
			Part.CanCollide = false
		end
	end
end

--> Every plot in the world, not just your own: a floor somebody has not bought should not be
--> standing there on their base either. Nothing here touches the server, so what you see is yours
--> alone and nobody else's view changes with it.
function FloorsController:RefreshPlots()
	local Container = GetContainer()

	if not Container then
		return
	end

	for Player, Index in PlotController.Plots do
		local Plot = Container:FindFirstChild(tostring(Index))
		local Floors = Plot and Plot:FindFirstChild("Floors")

		if not Floors then
			continue
		end

		local Unlocked = UnlockedFor(Player)

		--> Only your own base reacts to where you are standing. Somebody else's plot shows every
		--> floor they own whatever floor they happen to be on, which keeps their base from
		--> flickering as they walk around it.
		local Ceiling = if Player == LocalPlayer then self.Inside else nil

		for _, Folder in Floors:GetChildren() do
			local Floor = tonumber(Folder.Name)

			if not Floor then
				continue
			end

			local Show = Unlocked[Floor] == true and (Ceiling == nil or Floor <= Ceiling)

			self:SetShown(Folder, Show)
		end
	end
end

function FloorsController:Step()
	local Container = GetContainer()
	local Index = PlotController.Plots[LocalPlayer]
	local Plot = Index and Container and Container:FindFirstChild(tostring(Index))
	local Floors = Plot and Plot:FindFirstChild("Floors")

	local Character = LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	local Inside: number? = nil

	if Floors and Root and Root:IsA("BasePart") then
		Inside = FloorAt(Floors, Root.Position)
	end

	if Inside ~= self.Inside then
		self.Inside = Inside
		self:RefreshPlots()
	end
end

function FloorsController:Teleport(Floor: number)
	local _, Plot = PlotController:GetPlot(LocalPlayer)
	local Positions = Plot and Plot:FindFirstChild("Positions")
	local Marker = Positions and Positions:FindFirstChild(`Floor{Floor}`) :: BasePart?

	local Character = LocalPlayer.Character

	if not Marker or not Character then
		return
	end

	Character:PivotTo(CFrame.new(Marker.Position + Vector3.new(0, DropHeight, 0)))

	--> Applied here rather than left to the next heartbeat: the floor you are landing on is still
	--> hidden and not collidable until the sweep runs, and a frame of that is a frame of falling
	--> straight through it.
	self.Inside = Floor
	self:RefreshPlots()
end

function FloorsController:BindRows()
	local List = self:GetList()

	if not List then
		return
	end

	for _, Row in List:GetChildren() do
		local Floor = tonumber(Row.Name)
		local Button = Floor and Row:FindFirstChild("GoButton")

		if Button and Button:IsA("ImageButton") then
			--> The mock ships these inactive, and an inactive GuiButton takes the click without ever
			--> firing Activated.
			Button.Active = true

			Button.Activated:Connect(function()
				self:Teleport(Floor :: number)
				self:Close()
			end)
		end
	end
end

function FloorsController:BindPads()
	local _, Plot = PlotController:GetPlot(LocalPlayer)
	local Floors = Plot and Plot:FindFirstChild("Floors")

	if not Floors then
		return
	end

	for _, Folder in Floors:GetChildren() do
		local Pad = Folder:FindFirstChild(PadName)

		if not Pad or not Pad:IsA("BasePart") or self.Bound[Pad] then
			continue
		end

		self.Bound[Pad] = true

		Pad.Touched:Connect(function(Hit: BasePart)
			local Character = LocalPlayer.Character

			if not Character or not Hit:IsDescendantOf(Character) then
				return
			end

			if os.clock() < self.NextPad then
				return
			end

			self.NextPad = os.clock() + PadCooldown

			self:Open()
		end)
	end
end

function FloorsController:BindClose()
	local Gui = self:GetGui()
	local Outer = Gui and Gui:FindFirstChild("MainBackground")
	local Inner = Outer and Outer:FindFirstChild("MainBackground")

	if not Inner then
		return
	end

	for _, Button in Inner:GetChildren() do
		if Button.Name == "CloseButton" and Button:IsA("ImageButton") then
			Button.Active = true

			Button.Activated:Connect(function()
				self:Close()
			end)
		end
	end
end

--> Buying a floor is the only thing that changes somebody else's attribute, so this is the whole
--> signal that their base needs redrawing.
function FloorsController:Watch(Player: Player)
	if self.Watched[Player] then
		return
	end

	self.Watched[Player] = true

	Player:GetAttributeChangedSignal(FloorsAttribute):Connect(function()
		self:RefreshPlots()
	end)
end

function FloorsController:Start()
	LocalPlayer:WaitForChild("PlayerGui"):WaitForChild(GuiName)

	self:Close()
	self:BindClose()
	self:BindRows()
	self:RefreshList()

	for _, Player in Players:GetPlayers() do
		self:Watch(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:Watch(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self.Watched[Player] = nil
	end)

	local Container = GetContainer()

	if Container then
		--> A plot is cloned in whole, every floor standing, so it needs sweeping the moment it
		--> lands. Deferred because PlotController has not been told who owns it yet.
		Container.ChildAdded:Connect(function()
			task.defer(function()
				self:RefreshPlots()
			end)
		end)
	end

	task.spawn(function()
		self:RefreshPlots()
		self:BindPads()
	end)

	RunService.Heartbeat:Connect(function()
		self:Step()
	end)

	--> Buying a floor adds its key, which is the only signal that anything changed.
	PlayerData.Floors.OnKeyAdded(function()
		self:RefreshList()
		self:RefreshPlots()
		self:BindPads()
	end)
end

return FloorsController
