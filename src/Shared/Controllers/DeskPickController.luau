local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local NetworkingClient = require(Shared.Networking.networkingClient)
local DeskController = require(Shared.Controllers.DeskController)
local FloorsController = require(Shared.Controllers.FloorsController)
local SoundController = require(Shared.Controllers.SoundController)
local UIController = require(Shared.Controllers.UIController)
local DeskData = require(Shared.Utilities.DeskData)
local Signal = require(Shared.Packages.Fastsignal)
local PlayerData = require(Shared.PlayerData).client

--> Outline only, no fill: the desk has to stay readable as the desk it is. An empty desk is lit
--> green; one with somebody at it is lit amber, since landing there swaps the two.
local FreeColor = Color3.fromRGB(88, 255, 128)
local SwapColor = Color3.fromRGB(255, 190, 70)
local HoverColor = Color3.fromRGB(255, 255, 255)
local OutlineTransparency = 0
local FillTransparency = 1

--> A desk is clicked from wherever it can be seen, not walked up to.
local ClickDistance = 60

--> A press that travels further than this before it lets go is the camera being dragged, not a
--> click on nothing.
local ClickTravel = 8

--> How long after the button comes up a desk or a worker has to claim the click. Their detectors
--> fire off the same release, and nothing says in which order.
local ClickGrace = 0.1

export type Seat = {
	Floor: number,
	Slot: number,
}

type Marked = {
	Highlight: Highlight,
	Detector: ClickDetector,
}

--> Picking a desk for a worker to move to. Begin lights every other desk on the floor being
--> stood on, empty or not; walking to another floor lights that floor's instead, and the pick
--> stays open until a desk is clicked, the worker is clicked again, or another screen opens.
local DeskPickController = {
	--> The seat being moved from, nil while nothing is being picked.
	Source = nil :: Seat?,

	--> The desks currently lit, by desk id, with what was hung on them to light them.
	Marked = {} :: { [string]: Marked },

	--> Which floor the marks were built for, so a floor change is the only thing that rebuilds them.
	Floor = nil :: number?,

	--> One move in flight at a time, or two clicks send two moves and the second always fails.
	Moving = false,

	--> Whether the click being released landed on a desk or a worker. One that lands on neither is
	--> a click on nothing, which is the other way out of a pick.
	Handled = false,
	PressPoint = nil :: Vector2?,

	--> Fired whenever a pick ends, however it ended, for whatever was drawn against it.
	Ended = Signal.new(),
}

local function SeatKey(Seat: Seat): string
	return `{Seat.Floor}-{Seat.Slot}`
end

local function IsPointer(Input: InputObject): boolean
	return Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch
end

local function BuildHighlight(Desk: Model, Color: Color3): Highlight
	local Highlight = Instance.new("Highlight")
	Highlight.Name = "Pick"
	Highlight.Adornee = Desk
	Highlight.FillTransparency = FillTransparency
	Highlight.OutlineTransparency = OutlineTransparency
	Highlight.OutlineColor = Color
	Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	Highlight.Parent = Desk

	return Highlight
end

local function BuildDetector(Desk: Model): ClickDetector
	local Detector = Instance.new("ClickDetector")
	Detector.Name = "Pick"
	Detector.MaxActivationDistance = ClickDistance
	Detector.Parent = Desk

	return Detector
end

--> Standing and not the seat being moved from. The second value is whether somebody is already
--> sat there, which makes landing on it a swap rather than a move.
local function IsTarget(Seat: Seat, Source: Seat): (boolean, boolean)
	if SeatKey(Seat) == SeatKey(Source) then
		return false, false
	end

	local Desk = DeskData.Get(PlayerData, Seat.Floor, Seat.Slot)
	local Components = Desk and Desk()

	if type(Components) ~= "table" then
		return false, false
	end

	return true, Components.Employee ~= nil
end

function DeskPickController:IsPicking(): boolean
	return self.Source ~= nil
end

function DeskPickController:Clear()
	for _, Mark in self.Marked do
		Mark.Highlight:Destroy()
		Mark.Detector:Destroy()
	end

	table.clear(self.Marked)
	self.Floor = nil
end

--> Marks the other desks on one floor. Every floor but the one being stood in is hidden, so
--> lighting anything on the others would be lighting things that are not there.
function DeskPickController:Mark(Floor: number)
	local Source = self.Source

	self:Clear()

	if not Source then
		return
	end

	self.Floor = Floor

	for _, Slot in DeskData.GetSlots(PlayerData, Floor) do
		local Seat: Seat = { Floor = Floor, Slot = Slot }
		local Desk = DeskController.Desks[DeskController:GetDeskID(Floor, Slot)]
		local Allowed, Swap = IsTarget(Seat, Source)

		if not Desk or not Allowed then
			continue
		end

		local Color = if Swap then SwapColor else FreeColor
		local Highlight = BuildHighlight(Desk, Color)
		local Detector = BuildDetector(Desk)

		Detector.MouseHoverEnter:Connect(function()
			Highlight.OutlineColor = HoverColor
			SoundController:Play("Hover")
		end)

		Detector.MouseHoverLeave:Connect(function()
			Highlight.OutlineColor = Color
		end)

		Detector.MouseClick:Connect(function()
			self:Pick(Seat)
		end)

		self.Marked[SeatKey(Seat)] = { Highlight = Highlight, Detector = Detector }
	end
end

--> Rebuilt rather than patched: a desk being sat at or emptied is rare next to how cheap
--> sixteen highlights are, and a rebuild cannot leave a stale one behind.
function DeskPickController:Refresh()
	local Source = self.Source

	if not Source then
		return
	end

	--> The seat being moved from emptied under the pick: sold, or cleared by a command. Nothing
	--> left to move.
	local Desk = DeskData.Get(PlayerData, Source.Floor, Source.Slot)
	local Components = Desk and Desk()

	if type(Components) ~= "table" or Components.Employee == nil then
		self:Cancel()
		return
	end

	local Floor = FloorsController.Inside

	if not Floor then
		self:Clear()
		return
	end

	self:Mark(Floor)
end

function DeskPickController:Begin(Source: Seat)
	self.Source = Source
	self.Moving = false

	self:Refresh()
end

function DeskPickController:Cancel()
	if not self.Source then
		return
	end

	self.Source = nil
	self.Moving = false

	self:Clear()
	self.Ended:Fire()
end

--> The move itself, on a desk or on the worker sat at one. A target with somebody at it swaps the
--> two; the server decides that, this only sends the seats.
function DeskPickController:Pick(Target: Seat)
	local Source = self.Source

	self.Handled = true

	if not Source or self.Moving then
		return
	end

	self.Moving = true

	NetworkingClient.Employees.Move
		.Invoke({
			FromFloor = Source.Floor,
			FromSlot = Source.Slot,
			ToFloor = Target.Floor,
			ToSlot = Target.Slot,
		})
		:andThen(function(Moved: boolean)
			SoundController:Play(if Moved then "Confirm" else "Error")

			if Moved then
				self:Cancel()
			end
		end)
		:catch(function(Problem)
			warn(`[DeskPick] {Problem}`)
		end)
		:finally(function()
			self.Moving = false
		end)
end

function DeskPickController:Start()
	--> Fires for every desk that changes, which covers a seat filling, a seat emptying and a desk
	--> being bought or sold under the pick.
	DeskController.ComponentsChanged:Connect(function()
		if self.Source then
			self:Refresh()
		end
	end)

	--> A screen opening over the pick is the player doing something else now.
	UIController.Opened:Connect(function()
		self:Cancel()
	end)

	--> Clicking on nothing is the other way out. Empty floor answers nobody, so the release is
	--> given a moment for a desk or a worker to claim it, and the pick is dropped if none did.
	UserInputService.InputBegan:Connect(function(Input: InputObject, Processed: boolean)
		if Processed or not IsPointer(Input) or not self.Source then
			return
		end

		self.Handled = false
		self.PressPoint = Vector2.new(Input.Position.X, Input.Position.Y)
	end)

	UserInputService.InputEnded:Connect(function(Input: InputObject)
		local Pressed = self.PressPoint

		if not Pressed or not IsPointer(Input) then
			return
		end

		self.PressPoint = nil

		local Travel = (Vector2.new(Input.Position.X, Input.Position.Y) - Pressed).Magnitude

		if Travel > ClickTravel then
			return
		end

		task.delay(ClickGrace, function()
			if self.Source and not self.Handled then
				SoundController:Play("Click")
				self:Cancel()
			end
		end)
	end)

	--> Walking or teleporting to another floor lights that floor's desks instead.
	FloorsController.FloorChanged:Connect(function()
		if self.Source then
			self:Refresh()
		end
	end)
end

return DeskPickController
