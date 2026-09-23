local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local NetworkingClient = require(Shared.Networking.networkingClient)
local DeskPickController = require(Shared.Controllers.DeskPickController)
local FloorsController = require(Shared.Controllers.FloorsController)
local SoundController = require(Shared.Controllers.SoundController)
local UIController = require(Shared.Controllers.UIController)
local DeskData = require(Shared.Utilities.DeskData)
local EmployeeConfigs = require(Shared.Configs.Employees)
local Format = require(Shared.Utilities.Format)
local PlayerData = require(Shared.PlayerData).client
local Revenue = require(Shared.Utilities.Revenue)
local Rolling = require(Shared.Utilities.Rolling)
local Store = require(Shared.Utilities.Store)
local Tiers = require(Shared.Utilities.Tiers)

--> What UIController files the screen under. It owns the blur, the pop and the X; this fills the
--> card in and works the sell button.
local Screen = "Employee"
local GuiName = "EmployeesUI"
local PanelPath = { "Root", "Panel" }

local FallbackModel = "Tie Guy"

--> The portrait camera: a little above eye level and turned off straight on, so the rig reads as
--> a person rather than a front elevation.
local FieldOfView = 30
local Framing = 1.15
local Pitch = math.rad(12)
local Yaw = math.rad(-30)

--> How often the time worked line ticks while the card is up.
local TickInterval = 1

local UnknownTime = "Unknown"

--> The outline on a worker under the mouse, and on the one being moved while a desk is picked.
--> Outline only, so the rig stays readable as whoever it is.
local HoverColor = Color3.fromRGB(255, 255, 255)
local FillTransparency = 1
local OutlineTransparency = 0

local BaseOdds = Rolling.Chances(EmployeeConfigs, 1)

type Seat = {
	Floor: number,
	Slot: number,
}

local EmployeeMenuController = {
	--> Whose card is up, nil while the screen is shut.
	Current = nil :: Seat?,

	--> One sale in flight at a time, or a double press sends a second that always comes back false.
	Selling = false,

	--> Bumped every time the card opens, so the ticker of a card that has since been shut and
	--> reopened on somebody else knows to stop.
	Tick = 0,

	--> Desks whose Changed is already being listened to, so reopening the same one does not stack
	--> another connection on it.
	Watched = {} :: { [string]: boolean },

	--> One outline for whatever is under the mouse and one for the worker being moved, re-hung
	--> rather than built per worker: every Highlight counts against the client's budget whether it
	--> is switched on or not.
	HoverHighlight = nil :: Highlight?,
	MoveHighlight = nil :: Highlight?,

	--> The rig sat at each seat, kept up to date by EmployeeController as seats fill and empty,
	--> so the outline on a worker being moved has something to hang on.
	Models = {} :: { [string]: Model },
}

local function SeatKey(Seat: Seat): string
	return `{Seat.Floor}-{Seat.Slot}`
end

local function BuildHighlight(Name: string): Highlight
	local Highlight = Instance.new("Highlight")
	Highlight.Name = Name
	Highlight.FillTransparency = FillTransparency
	Highlight.OutlineTransparency = OutlineTransparency
	Highlight.OutlineColor = HoverColor
	Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	Highlight.Enabled = false
	Highlight.Parent = workspace

	return Highlight
end

--> Only the floor being stood in is drawn, but a hidden floor's parts still answer the mouse, so
--> a worker upstairs would light up through the ceiling without this.
local function OnCurrentFloor(Floor: number): boolean
	return FloorsController.Inside ~= nil and tonumber(Floor) == FloorsController.Inside
end

--> "14d 5h 3m" down to whatever is left, and seconds only under a minute.
local function FormatDuration(Seconds: number): string
	local Total = math.max(math.floor(Seconds), 0)

	local Days = Total // 86400
	local Hours = (Total % 86400) // 3600
	local Minutes = (Total % 3600) // 60

	if Days > 0 then
		return `{Days}d {Hours}h {Minutes}m`
	end

	if Hours > 0 then
		return `{Hours}h {Minutes}m`
	end

	if Minutes > 0 then
		return `{Minutes}m`
	end

	return `{Total % 60}s`
end

local function GetOdds(Type: string): number
	local Chance = BaseOdds[Type]

	return if Chance and Chance > 0 then 1 / Chance else math.huge
end

local function GetModelTemplate(Type: string): Model
	local Folder = Assets:WaitForChild("Employees")
	local Template = Folder:FindFirstChild(Type) or Folder:WaitForChild(FallbackModel)

	return Template :: Model
end

--> A still of the rig in the square beside the name. Rebuilt on every open, because the square is
--> part of a ScreenGui that is thrown away and cloned again on respawn.
local function BuildPortrait(Frame: GuiObject, Type: string)
	local Existing = Frame:FindFirstChild("Viewport")

	if Existing then
		Existing:Destroy()
	end

	local Viewport = Instance.new("ViewportFrame")
	Viewport.Name = "Viewport"
	Viewport.Size = UDim2.fromScale(1, 1)
	Viewport.BackgroundTransparency = 1
	Viewport.Ambient = Color3.fromRGB(180, 180, 190)
	Viewport.LightColor = Color3.fromRGB(255, 255, 255)
	Viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)

	local Model = GetModelTemplate(Type):Clone()
	local Root = Model:FindFirstChild("HumanoidRootPart") or Model.PrimaryPart

	--> editor leftovers on the rig, cloned onto every card otherwise
	local AnimSaves = Model:FindFirstChild("AnimSaves")

	if AnimSaves then
		AnimSaves:Destroy()
	end

	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.Anchored = true
		end
	end

	Model.Parent = Viewport

	local Camera = Instance.new("Camera")
	Camera.FieldOfView = FieldOfView
	Camera.Parent = Viewport
	Viewport.CurrentCamera = Camera

	local BoxCFrame, BoxSize = Model:GetBoundingBox()
	local Center = BoxCFrame.Position
	local Distance = (BoxSize.Magnitude / 2) / math.tan(math.rad(FieldOfView) / 2) * Framing

	--> the rig's own front, turned by the yaw, so whichever way the template happens to be facing
	--> the card still looks it in the face
	local Facing = if Root and Root:IsA("BasePart") then Root.CFrame else BoxCFrame
	local Forward = (Facing * CFrame.Angles(0, Yaw, 0)).LookVector * Vector3.new(1, 0, 1)
	local Eye = Center + Forward.Unit * Distance * math.cos(Pitch) + Vector3.yAxis * Distance * math.sin(Pitch)

	Camera.CFrame = CFrame.lookAt(Eye, Center)

	Viewport.Parent = Frame
end

local function SetValue(Panel: Instance, Row: string, Text: string)
	local Frame = Panel:FindFirstChild(Row)
	local Label = Frame and Frame:FindFirstChild("ValueLabel")

	if Label and Label:IsA("TextLabel") then
		Label.Text = Text
	end
end

function EmployeeMenuController:GetPanel(): Frame?
	local Current: Instance? = UIController:GetGui(Screen)

	for _, Step in PanelPath do
		if not Current then
			return nil
		end

		Current = (Current :: Instance):FindFirstChild(Step)
	end

	return if Current and Current:IsA("Frame") then Current else nil
end

--> The record of who is sat there, or nil for an empty or missing desk.
function EmployeeMenuController:GetSeated(Seat: Seat): any?
	local Desk = DeskData.Get(PlayerData, Seat.Floor, Seat.Slot)
	local Components = Desk and Desk()
	local Employee = if type(Components) == "table" then Components.Employee else nil

	return if type(Employee) == "table" then Employee else nil
end

function EmployeeMenuController:RefreshTime()
	local Panel = self:GetPanel()
	local Seat = self.Current
	local Employee = Seat and self:GetSeated(Seat)

	if not Panel or not Employee then
		return
	end

	local HiredAt = Employee.HiredAt

	SetValue(
		Panel,
		"TimeWorkedRow",
		if type(HiredAt) == "number" then FormatDuration(os.time() - HiredAt) else UnknownTime
	)
end

--> Everything on the card, off the desk record and the configs. A seat that has emptied under an
--> open card -- sold, or cleared by a command -- shuts it rather than leaving a card for nobody.
function EmployeeMenuController:Refresh()
	local Seat = self.Current

	if not Seat then
		return
	end

	local Employee = self:GetSeated(Seat)

	if not Employee then
		UIController:Close(Screen, true)
		return
	end

	local Panel = self:GetPanel()

	if not Panel then
		return
	end

	local Type: string = Employee.Type
	local Config = EmployeeConfigs[Type]
	local Odds = GetOdds(Type)
	local TierName, TierColor = Tiers.FromOdds(Odds)

	local Desk = DeskData.Get(PlayerData, Seat.Floor, Seat.Slot)
	local Rate = math.floor(Revenue.DeskRate(Desk and Desk()) * Store.IncomeMultiplier(PlayerData, Players.LocalPlayer))

	local NameLabel = Panel:FindFirstChild("NameLabel") :: TextLabel?
	local Badge = Panel:FindFirstChild("RarityBadge")
	local RarityLabel = Badge and Badge:FindFirstChild("RarityLabel") :: TextLabel?
	local Portrait = Panel:FindFirstChild("Portrait") :: GuiObject?
	local SellButton = Panel:FindFirstChild("SellButton")
	local SellLabel = SellButton and SellButton:FindFirstChild("Label") :: TextLabel?
	local MoveButton = Panel:FindFirstChild("MoveButton") :: GuiObject?

	if NameLabel then
		NameLabel.Text = Employee.Name
	end

	if RarityLabel then
		RarityLabel.Text = TierName
		RarityLabel.TextColor3 = TierColor
	end

	if Portrait then
		BuildPortrait(Portrait, Type)
	end

	if SellLabel then
		SellLabel.Text = "Sell for " .. Format.Cash(Revenue.SellValue(Type))
	end

	if MoveButton then
		MoveButton.Visible = true
	end

	SetValue(Panel, "EarningsRow", Format.Rate(Rate))
	SetValue(Panel, "MultiplierRow", (if Config then Config.Value else 1) .. "x")
	SetValue(Panel, "TypeRow", Type)
	SetValue(Panel, "OddsRow", if Odds < math.huge then "1 in " .. math.floor(Odds + 0.5) else "1 in ???")
	SetValue(Panel, "DeskRow", `Floor {Seat.Floor}, Desk {Seat.Slot}`)

	self:RefreshTime()
end

--> Sitting down and selling both land on the desk record, so its Changed is the one thing worth
--> watching. One connection per desk for the life of the session, whichever card is up.
function EmployeeMenuController:Watch(Seat: Seat)
	local Key = SeatKey(Seat)

	if self.Watched[Key] then
		return
	end

	local Desk = DeskData.Get(PlayerData, Seat.Floor, Seat.Slot)

	if not Desk then
		return
	end

	self.Watched[Key] = true

	Desk.Changed(function()
		local Current = self.Current

		if Current and SeatKey(Current) == Key then
			self:Refresh()
		end
	end)
end

function EmployeeMenuController:Hover(Floor: number, Slot: number, Model: Model)
	local Highlight = self.HoverHighlight

	if not Highlight or not OnCurrentFloor(Floor) then
		return
	end

	--> the one being moved already wears its outline, and a second on top doubles the line
	local Source = DeskPickController.Source

	if Source and SeatKey(Source) == SeatKey({ Floor = Floor, Slot = Slot }) then
		return
	end

	Highlight.Adornee = Model
	Highlight.Enabled = true

	SoundController:Play("Hover")
end

function EmployeeMenuController:Unhover(Model: Model)
	local Highlight = self.HoverHighlight

	if Highlight and Highlight.Adornee == Model then
		Highlight.Adornee = nil
		Highlight.Enabled = false
	end
end

--> Keeps the outline on whoever is being moved, and takes it off when nobody is.
function EmployeeMenuController:RefreshMoveHighlight()
	local Highlight = self.MoveHighlight
	local Source = DeskPickController.Source

	if not Highlight then
		return
	end

	if not Source then
		Highlight.Adornee = nil
		Highlight.Enabled = false
		return
	end

	local Model = self.Models[SeatKey(Source)]

	Highlight.Adornee = Model
	Highlight.Enabled = Model ~= nil
end

--> Called by EmployeeController with the rig it built for a seat, and with nil when it goes.
function EmployeeMenuController:Register(Floor: number, Slot: number, Model: Model?)
	local Key = SeatKey({ Floor = Floor, Slot = Slot })

	self.Models[Key] = Model

	--> the seat being moved from just changed hands, so the outline follows or comes off
	local Source = DeskPickController.Source

	if Source and SeatKey(Source) == Key then
		self:RefreshMoveHighlight()
	end
end

function EmployeeMenuController:Show(Floor: number, Slot: number)
	local Seat: Seat = { Floor = Floor, Slot = Slot }

	if not OnCurrentFloor(Floor) or not self:GetSeated(Seat) then
		return
	end

	--> Clicking the worker being moved is the way out of a pick. Clicking any other worker lands
	--> the move on their seat instead, which swaps the two; their card stays shut.
	local Source = DeskPickController.Source

	if Source then
		if SeatKey(Source) == SeatKey(Seat) then
			DeskPickController:Cancel()
			self:RefreshMoveHighlight()
			SoundController:Play("Click")
			return
		end

		DeskPickController:Pick(Seat)
		return
	end

	self.Current = Seat
	self.Tick += 1

	self:Watch(Seat)
	self:Refresh()

	UIController:Open(Screen)

	--> Only the clock line moves on its own, so only that is redrawn each second.
	local Tick = self.Tick

	task.spawn(function()
		while self.Tick == Tick and UIController:IsOpen(Screen) do
			task.wait(TickInterval)
			self:RefreshTime()
		end
	end)
end

function EmployeeMenuController:Sell()
	local Seat = self.Current

	if self.Selling or not Seat then
		return
	end

	self.Selling = true

	NetworkingClient.Employees.Sell
		.Invoke({ Floor = Seat.Floor, Slot = Seat.Slot })
		:andThen(function(Sold: boolean)
			SoundController:Play(if Sold then "Sell" else "Error")

			if Sold then
				UIController:Close(Screen)
			end
		end)
		:catch(function(Problem)
			warn(`[EmployeeMenu] {Problem}`)
		end)
		:finally(function()
			self.Selling = false
		end)
end

--> Any other desk on any floor, since the pick follows the player between floors. One with
--> somebody at it still counts: landing there swaps the two.
local function HasOtherDesk(Source: Seat): boolean
	for _, Floor in DeskData.GetFloors(PlayerData) do
		for _, Slot in DeskData.GetSlots(PlayerData, Floor) do
			local Desk = DeskData.Get(PlayerData, Floor, Slot)
			local Components = Desk and Desk()

			local Other = type(Components) == "table" and SeatKey({ Floor = Floor, Slot = Slot }) ~= SeatKey(Source)

			if Other then
				return true
			end
		end
	end

	return false
end

--> The card comes down and the desks light up. Closed silently, since the click that lands on
--> a desk is the sound this is waiting for. With only the one desk there is nowhere to go, and a
--> pick that lights nothing reads as a button that did nothing, so it is refused up front.
function EmployeeMenuController:Move()
	local Seat = self.Current

	if not Seat then
		return
	end

	if not HasOtherDesk(Seat) then
		SoundController:Play("Error")
		return
	end

	UIController:Close(Screen, true)

	DeskPickController:Begin(Seat)
	self:RefreshMoveHighlight()

	SoundController:Play("Click")
end

local function BindButton(Panel: Instance, Name: string, Press: () -> ())
	local Button = Panel:FindFirstChild(Name)

	if not Button or not Button:IsA("GuiButton") then
		warn(`[EmployeeMenu] {GuiName} has no {Name}`)
		return
	end

	--> The mock ships these inactive, and an inactive GuiButton takes the press and fires nothing.
	Button.Active = true
	Button.Activated:Connect(Press)

	Button.MouseEnter:Connect(function()
		SoundController:Play("Hover")
	end)
end

--> The X is UIController's; sell and move are this screen's own.
function EmployeeMenuController:Bind(Gui: ScreenGui)
	local Root = Gui:FindFirstChild(PanelPath[1])
	local Panel = Root and Root:FindFirstChild(PanelPath[2])

	if not Panel then
		warn(`[EmployeeMenu] {GuiName} has no {table.concat(PanelPath, ".")}`)
		return
	end

	BindButton(Panel, "SellButton", function()
		self:Sell()
	end)

	BindButton(Panel, "MoveButton", function()
		self:Move()
	end)
end

function EmployeeMenuController:Start()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	self.HoverHighlight = BuildHighlight("EmployeeHover")
	self.MoveHighlight = BuildHighlight("EmployeeMoving")

	--> A pick ending any way but through here -- the desk clicked, the seat emptied, a screen
	--> opening -- still has to take the outline off.
	DeskPickController.Ended:Connect(function()
		self:RefreshMoveHighlight()
	end)

	self:Bind(PlayerGui:WaitForChild(GuiName) :: ScreenGui)

	--> Cloned again every respawn, and the copy has none of these connections.
	PlayerGui.ChildAdded:Connect(function(Child: Instance)
		if Child:IsA("ScreenGui") and Child.Name == GuiName then
			self:Bind(Child)
		end
	end)

	UIController.Closed:Connect(function(Name: string)
		if Name == Screen then
			self.Current = nil
		end
	end)
end

return EmployeeMenuController
