local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskController = require(Shared.Controllers.DeskController)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlotController = require(Shared.Controllers.PlotController)
local Signal = require(Shared.Packages.Fastsignal)
local PlayerData = require(Shared.PlayerData).client

local GuiName = "FloorsUI"
local PadName = "TeleportPad"
local PlacementsName = "Desk Placements"
local ContainerName = "PlotContainer"

--> The box PlotTemplate carries on every floor, sized to cover the whole room. Standing inside one
--> is what hides the floors stacked above it.
local BoundsName = "IsInFloor"

--> The one part of a floor's lid the builder gave a name to. The other six are laid flush with its
--> underside and left called Part, so this slab is what the rest are measured against rather than
--> something to go looking for by name.
local RoofName = "Roof"

--> How far under the slab still counts as the lid. The highest thing below it is the wall trim,
--> which starts 0.3 further down, so this leaves room for float error and reaches nothing else.
local RoofSlack = 0.05

--> A desk is built into a folder of its own rather than into the floor it was placed on, and so is
--> the person sitting at it, so sweeping the plot reaches neither.
local LooseNames = { "Desks", "Employees" }

--> Written by PlotService. Attributes replicate on their own, so this is how the client learns
--> which floors somebody else has bought without asking the server for them.
local FloorsAttribute = "UnlockedFloors"

--> How long a floor asked for is held shown while the server's move is on its way. Well past any
--> round trip; if the root has not turned up by then, the move was refused or lost.
local PendingSeconds = 3

--> Touched fires every frame a limb is on the pad; without this the menu reopens the moment it closes.
local PadCooldown = 1

local LocalPlayer = Players.LocalPlayer

--> Only the fields that were actually changed are written down, so putting a ceiling back does not
--> also hand it a CanCollide it never lost.
type Recorded = {
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	Enabled: boolean?,
}

local FloorsController = {
	Gui = nil :: ScreenGui?,

	--> What each thing looked like before it was hidden, so showing a floor puts it back exactly
	--> rather than guessing at 0 and true.
	--> Held strongly, and emptied by hand when a plot goes. Weak keys look like the tidy answer and
	--> are not: an Instance key is kept alive only by its Lua handle, and that is collected long
	--> before the instance is, so the record of how to put a part back disappears while the part is
	--> still standing there hidden. A floor left alone long enough never came back.
	Restore = {} :: { [Instance]: Recorded },

	--> Each floor's lid, worked out once from the geometry and kept.
	Roofs = {} :: { [Instance]: { Instance } },

	--> Which floor of your own plot you are standing in, nil when you are outside every box. Cached
	--> so the sweep only runs when it changes rather than every heartbeat.
	Inside = nil :: number?,

	--> The floor asked for and not yet stood on, and when to stop waiting for it.
	Pending = nil :: number?,
	PendingUntil = 0,

	--> Fired with the new Inside whenever it changes, walking or teleporting, so anything keyed to
	--> the floor being stood on -- the desk picker -- follows without polling.
	FloorChanged = Signal.new(),

	--> Set when a desk, an employee or a rebuilt set of components turns up, because whatever
	--> arrived is standing there at full size on a floor that may well be hidden. Read once a frame
	--> rather than swept on the spot: a desk lands a moment before the things that go on it.
	Dirty = false,

	NextPad = 0,
	Bound = {} :: { [BasePart]: boolean },
	Watched = {} :: { [Player]: boolean },

	--> Floor folders already being watched for late arrivals, so the connection is made once.
	Growing = {} :: { [Instance]: boolean },
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

		local Within = math.abs(Offset.X) <= Half.X and math.abs(Offset.Y) <= Half.Y and math.abs(Offset.Z) <= Half.Z

		if Within then
			return Floor
		end
	end

	return nil
end

--> A part at Transparency 1 is not gone. It still draws every Texture stuck to its faces, still
--> floats its billboards, still answers its prompts, still throws its light and still runs whatever
--> is emitting off it, which is why the floors overhead used to come away and leave their wallpaper
--> hanging in the air.
--> Everything below either takes a Transparency or takes an Enabled, and every one of them draws on
--> its own account rather than with the part it hangs off, so the list has to be the whole set
--> rather than the ones that happened to turn up. Texture is a Decal and the three lights are all
--> Light, so those two checks cover five classes between them.
local function Hideable(Object: Instance): boolean
	return Object:IsA("BasePart")
		or Object:IsA("Decal")
		or Object:IsA("BillboardGui")
		or Object:IsA("SurfaceGui")
		or Object:IsA("ProximityPrompt")
		or Object:IsA("Light")
		or Object:IsA("ParticleEmitter")
		or Object:IsA("Beam")
		or Object:IsA("Trail")
		or Object:IsA("Fire")
		or Object:IsA("Smoke")
		or Object:IsA("Sparkles")
		or Object:IsA("Highlight")
end

--> How far the underside of a part sits above Frame's origin, along Frame's own up. Measured this
--> way rather than against world Y because a plot is pivoted into place and everything standing on
--> it is turned with it. The reach is the part's own three half extents projected onto that up,
--> which is the lowest corner of the box however it is rotated.
local function Underside(Frame: CFrame, Part: BasePart): number
	local Up = Frame.UpVector
	local Half = Part.Size / 2

	local Reach = math.abs(Part.CFrame.RightVector:Dot(Up)) * Half.X
		+ math.abs(Part.CFrame.UpVector:Dot(Up)) * Half.Y
		+ math.abs(Part.CFrame.LookVector:Dot(Up)) * Half.Z

	return Frame:PointToObjectSpace(Part.Position).Y - Reach
end

--> Only what is about to change is written down, so a reveal puts back exactly that and nothing
--> else. A prompt has no transparency and a texture has no collision.
local function Snapshot(Object: Instance): Recorded
	if Object:IsA("BasePart") then
		return { Transparency = Object.Transparency, CanCollide = Object.CanCollide, CanQuery = Object.CanQuery }
	end

	if Object:IsA("Decal") then
		return { Transparency = Object.Transparency }
	end

	return { Enabled = (Object :: any).Enabled }
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
--> you buy it or step out of the room below it. Solid is for the ceiling over your own head, which
--> goes invisible but stays in the way: take its collision as well and a jump puts you up through
--> it into the floor above, which is hidden and not collidable either, so you land inside it.
function FloorsController:Conceal(Object: Instance, Solid: boolean)
	local Recorded = self.Restore[Object]

	if not Recorded then
		Recorded = Snapshot(Object)
		self.Restore[Object] = Recorded
	end

	--> the mouse goes through it too: a hidden floor or ceiling over the camera would otherwise
	--> catch every click and hover meant for what is under it
	if Object:IsA("BasePart") then
		Object.Transparency = 1
		Object.CanCollide = Solid and Recorded.CanCollide == true
		Object.CanQuery = false

		return
	end

	if Object:IsA("Decal") then
		Object.Transparency = 1
		return
	end

	--> a billboard, a surface gui or a prompt: whatever is left has an Enabled and nothing else
	local Switchable = Object :: any
	Switchable.Enabled = false
end

function FloorsController:Reveal(Object: Instance)
	local Recorded = self.Restore[Object]

	if not Recorded then
		return
	end

	self.Restore[Object] = nil

	--> Compared against nil rather than tested for truth, because the CanCollide being put back is
	--> very often false and would be skipped.
	if Recorded.Transparency ~= nil then
		(Object :: any).Transparency = Recorded.Transparency
	end

	if Recorded.CanCollide ~= nil then
		(Object :: any).CanCollide = Recorded.CanCollide
	end

	if Recorded.CanQuery ~= nil then
		(Object :: any).CanQuery = Recorded.CanQuery
	end

	if Recorded.Enabled ~= nil then
		(Object :: any).Enabled = Recorded.Enabled
	end
end

function FloorsController:SetShown(Root: Instance, Show: boolean)
	for _, Object in Root:GetDescendants() do
		if not Hideable(Object) then
			continue
		end

		--> Desk Placements are invisible markers the desk builder reads; leave them be.
		if Object:FindFirstAncestor(PlacementsName) then
			continue
		end

		--> The bounds box is a marker too. The template ships it half transparent so it can be seen
		--> while editing, and drawing it in game would drop a tinted cube over the whole room.
		if Object.Name == BoundsName then
			(Object :: BasePart).Transparency = 1
			continue
		end

		if Show then
			self:Reveal(Object)
			continue
		end

		self:Conceal(Object, false)
	end
end

--> Everything a floor's lid is made of: the slab named Roof, the six more laid flush with it that
--> were left called Part, and whatever is stuck to any of them. Found by height rather than by name
--> because only one of the seven carries one, and worked out once and kept -- but only until the
--> floor grows, which is what WatchFloor is for: the answer cannot change once the plot is standing,
--> and the plot is not standing for the first few frames of it replicating in.
function FloorsController:GetRoof(Folder: Instance): { Instance }
	local Cached = self.Roofs[Folder]

	if Cached then
		return Cached
	end

	local Roof = {}
	local Slab = nil :: BasePart?

	for _, Object in Folder:GetDescendants() do
		if Object.Name == RoofName and Object:IsA("BasePart") then
			Slab = Object
			break
		end
	end

	self.Roofs[Folder] = Roof

	--> A floor with nothing named Roof keeps its ceiling: better a room you cannot see out of the
	--> top of than a guess at which parts to take away. Silent, unlike it used to be -- a plot
	--> replicates in pieces and the first sweep almost always runs before the slab has landed, so
	--> the warning fired on every plot that loaded slowly and said nothing about the one case it
	--> was for. WatchFloor drops this answer the moment anything else arrives, which is what turns
	--> an early nil into the real lid rather than into a permanent one.
	if not Slab then
		return Roof
	end

	local Line = -Slab.Size.Y / 2 - RoofSlack

	for _, Object in Folder:GetDescendants() do
		if not Object:IsA("BasePart") or Underside(Slab.CFrame, Object) < Line then
			continue
		end

		table.insert(Roof, Object)

		for _, Attached in Object:GetDescendants() do
			if Hideable(Attached) then
				table.insert(Roof, Attached)
			end
		end
	end

	return Roof
end

--> A plot arrives in pieces and a floor keeps filling in after the first sweep has run over it, so
--> the lid worked out from what was there at the time goes stale. Dropped rather than patched: it
--> is seven parts to measure and it is only rebuilt when something actually lands on the floor.
--> Marked dirty as well, because a part that turned up on a hidden floor is standing there at full
--> size until the next sweep, and there is no other signal that it did.
function FloorsController:WatchFloor(Folder: Instance)
	if self.Growing[Folder] then
		return
	end

	self.Growing[Folder] = true

	Folder.DescendantAdded:Connect(function(Object: Instance)
		if not Object:IsA("BasePart") then
			return
		end

		self.Roofs[Folder] = nil
		self.Dirty = true
	end)
end

function FloorsController:SetRoofShown(Folder: Instance, Show: boolean)
	for _, Object in self:GetRoof(Folder) do
		if Show then
			self:Reveal(Object)
			continue
		end

		self:Conceal(Object, true)
	end
end

--> A desk stands in a folder of its own rather than in the floor it was placed on, and so does the
--> person sitting at it, which is what left the desks upstairs hanging in the air over a floor that
--> had been taken away. Nothing writes down which floor a desk is on, and nothing needs to: the box
--> that decides which floor you are standing in decides which floor a desk is standing on.
--> Your own plot only, because these are only ever built for your own plot.
function FloorsController:RefreshLoose(Floors: Instance)
	for _, Name in LooseNames do
		local Container = workspace:FindFirstChild(Name)

		if not Container then
			continue
		end

		for _, Model in Container:GetChildren() do
			if not Model:IsA("PVInstance") then
				continue
			end

			--> Outside every box -- an employee still walking in off the street -- belongs to no
			--> floor and is left alone. Those are the only ones here that move, and one hidden on
			--> the way past would stay hidden until you next changed floor.
			local Floor = FloorAt(Floors, Model:GetPivot().Position)
			local Show = Floor == nil or self.Inside == nil or Floor <= self.Inside

			self:SetShown(Model, Show)
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

			self:WatchFloor(Folder)
			self:SetShown(Folder, Show)

			--> The lid comes off the floor you are standing in and off no other. Over your head
			--> there is nothing behind it to see, since everything above is hidden anyway, and it
			--> is the one piece of the room between you and the sky. Anywhere else it is the
			--> underside of the floor above you, which nobody ever looks at.
			if Show then
				self:SetRoofShown(Folder, Ceiling ~= Floor)
			end
		end

		if Player == LocalPlayer then
			self:RefreshLoose(Floors)
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

	--> Held on the floor being travelled to until the root turns up there: the server's move is a
	--> round trip away, and the room has to be solid before the character drops into it. Let go
	--> on arrival, or after long enough that the move is not coming.
	if self.Pending then
		if Inside == self.Pending or os.clock() > self.PendingUntil then
			self.Pending = nil
		else
			Inside = self.Pending
		end
	end

	if Inside ~= self.Inside or self.Dirty then
		local Changed = Inside ~= self.Inside

		self.Inside = Inside
		self.Dirty = false

		self:RefreshPlots()

		if Changed then
			self.FloorChanged:Fire(Inside)
		end
	end
end

--> Marked rather than swept on the spot: a desk lands a frame or two before the components that go
--> on it, and an employee arrives carrying a couple of thousand descendants.
function FloorsController:WatchLoose(Container: Instance?)
	if not Container then
		return
	end

	Container.ChildAdded:Connect(function()
		self.Dirty = true
	end)
end

--> The move is the server's: it checks the floor is owned and pivots the character itself, which
--> is what keeps a client teleporting on its own from looking like this. The floor is shown
--> ahead of the answer, because the character lands there before the answer does and the room
--> has to be solid by then; a refusal just lets the sweep go back to reading the root.
function FloorsController:Teleport(Floor: number)
	self.Pending = Floor
	self.PendingUntil = os.clock() + PendingSeconds
	self.Dirty = true

	NetworkingClient.Floors.Travel.Invoke(Floor):andThen(function(Moved: boolean)
		if not Moved then
			self.Pending = nil
			self.Dirty = true
		end
	end)
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

		--> A plot goes when its owner leaves. Anything of it still written down here would hold the
		--> instances alive for the rest of the server, so its entries go with it.
		Container.ChildRemoved:Connect(function(Child: Instance)
			for _, Object in Child:GetDescendants() do
				self.Restore[Object] = nil
				self.Roofs[Object] = nil
				self.Growing[Object] = nil
			end
		end)
	end

	--> Anything arriving later arrives at full size on a floor that may well be hidden: a desk
	--> bought upstairs, the employee who sits at it, or new components swapped onto a desk that was
	--> already standing there.
	for _, Name in LooseNames do
		self:WatchLoose(workspace:FindFirstChild(Name))
	end

	workspace.ChildAdded:Connect(function(Child: Instance)
		if table.find(LooseNames, Child.Name) then
			self:WatchLoose(Child)
		end
	end)

	DeskController.ComponentsChanged:Connect(function()
		self.Dirty = true
	end)

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
