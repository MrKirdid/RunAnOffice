local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotController = require(Shared.Controllers.PlotController)
local SoundController = require(Shared.Controllers.SoundController)

local LocalPlayer = Players.LocalPlayer

--> Everything here is drawn off this one attribute, which BaseLockingService writes as server
--> time. Whether the door is solid is the server's; what it looks like and what it says is ours.
local LockedAttribute = "LockedUntil"

local ContainerName = "PlotContainer"
local LasersName = "Lasers"
local BeamName = "Beam"
local WallName = "InvisibleWall"
local ButtonName = "LockBase"
local MarkerName = "LockBaseMoveToBreifForButtonClick"

--> The beams when the door is shut, and the label's shape. The wall itself never shows.
local BeamShown = 0.5
local BeamFade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LabelFormat = "Cooldown: %ds"

--> The button spring. Value is how far pressed it is, 0 resting on the wall and 1 all the way in
--> to the marker; the size shrinks with it. Loose enough that letting go overshoots back out of
--> the wall and swells before it settles, which is the whole of the bounce.
local Stiffness = 520
local Damping = 11
local Shrink = 0.14

--> The kick given to the spring on a press, and how long it is held in before it is let go. The
--> hold is what makes it a press rather than a twitch: without it the spring has turned around
--> before the button has visibly moved.
local Punch = 14
local HoldSeconds = 0.09
local HoverValue = -0.12

--> A frame this long is a tab that was in the background, and integrating it in one step throws
--> the spring somewhere it cannot recover from.
local MaxStep = 1 / 30

--> How long to wait for the plot and its button to replicate before giving up on the button.
local BindTimeout = 30

type Door = {
	Plot: Model,
	Beams: { BasePart },
	Label: TextLabel?,
	Wall: BasePart?,
	--> nil until the first paint, so the first refresh always paints whichever way it is
	Locked: boolean?,
}

type Button = {
	Part: BasePart,
	Rest: CFrame,
	Pressed: CFrame,
	Size: Vector3,
	Value: number,
	Velocity: number,
	Goal: number,
	Hovered: boolean,
	ReleaseAt: number,
}

local BaseLockingController = {
	Doors = {} :: { [Model]: Door },
	Button = nil :: Button?,
}

local function GetUntil(Plot: Model): number
	local Until = Plot:GetAttribute(LockedAttribute)

	return if typeof(Until) == "number" then Until else 0
end

local function SecondsLeft(Until: number): number
	return math.max(0, math.ceil(Until - workspace:GetServerTimeNow()))
end

--> The beams fade rather than flick, and the sound comes from the door rather than the head:
--> everyone near enough hears which base just shut.
function BaseLockingController:SetShown(Door: Door, Shown: boolean, Announce: boolean)
	Door.Locked = Shown

	local Goal = if Shown then BeamShown else 1

	for _, Beam in Door.Beams do
		TweenService:Create(Beam, BeamFade, { Transparency = Goal }):Play()
	end

	if Door.Label then
		Door.Label.Text = if Shown then string.format(LabelFormat, SecondsLeft(GetUntil(Door.Plot))) else ""
	end

	if Announce and Door.Wall then
		SoundController:PlayAt(if Shown then "Lock" else "Unlock", Door.Wall.Position)
	end
end

function BaseLockingController:Refresh(Door: Door, Announce: boolean)
	local Shown = GetUntil(Door.Plot) > workspace:GetServerTimeNow()

	if Shown ~= Door.Locked then
		self:SetShown(Door, Shown, Announce)
	end
end

function BaseLockingController:WatchPlot(Plot: Model)
	if self.Doors[Plot] then
		return
	end

	local Lasers = Plot:WaitForChild(LasersName, 10)

	if not Lasers or self.Doors[Plot] then
		return
	end

	local Door: Door = {
		Plot = Plot,
		Beams = {},
		Label = nil,
		Wall = nil,
		Locked = nil,
	}

	--> The lasers arrive a piece at a time for a player who joins after the plot was made, so
	--> the beams and the label are taken as they come rather than read once and missed: a beam
	--> read too early was one that never lit, and a label never found was a countdown nobody saw.
	local function Adopt(Object: Instance)
		if Object.Name == BeamName and Object:IsA("BasePart") and Object.Parent == Lasers then
			table.insert(Door.Beams, Object)

			if Door.Locked ~= nil then
				Object.Transparency = if Door.Locked then BeamShown else 1
			end

			return
		end

		if Object.Name == WallName and Object:IsA("BasePart") and Object.Parent == Lasers then
			Door.Wall = Object
			return
		end

		if Object:IsA("TextLabel") and not Door.Label and Door.Wall and Object:IsDescendantOf(Door.Wall) then
			Door.Label = Object

			if Door.Locked then
				Object.Text = string.format(LabelFormat, SecondsLeft(GetUntil(Plot)))
			end
		end
	end

	for _, Object in Lasers:GetDescendants() do
		Adopt(Object)
	end

	Lasers.DescendantAdded:Connect(Adopt)

	self.Doors[Plot] = Door
	self:Refresh(Door, false)

	Plot:GetAttributeChangedSignal(LockedAttribute):Connect(function()
		self:Refresh(Door, true)
	end)
end

--> The press. What the server does with it is its own business; this is the button giving under
--> the finger, and the sound of it, before anything comes back. Already locked is a different
--> noise, so the second press is not left wondering.
function BaseLockingController:Press()
	local Button = self.Button
	local _, Plot = PlotController:GetPlot(LocalPlayer)
	local Door = Plot and self.Doors[Plot]

	if not Button then
		return
	end

	Button.Velocity += Punch
	Button.Goal = 1
	Button.ReleaseAt = os.clock() + HoldSeconds

	if Door and Door.Locked then
		SoundController:Play("Error")
	else
		SoundController:Play("Press")
	end
end

--> The plot arrives from the server a piece at a time, so the button is waited for rather than
--> looked for once and given up on.
function BaseLockingController:BindButton()
	local Index = PlotController:GetPlot(LocalPlayer)
	local Container = workspace:WaitForChild(ContainerName)
	local Plot = Container:WaitForChild(tostring(Index), BindTimeout)
	local Deadline = os.clock() + BindTimeout

	local Part, Marker, Detector

	while Plot and os.clock() < Deadline do
		Part = Plot:FindFirstChild(ButtonName, true)
		Marker = Plot:FindFirstChild(MarkerName, true)
		Detector = Part and Part:FindFirstChildOfClass("ClickDetector")

		if Part and Marker and Detector then
			break
		end

		task.wait(0.25)
	end

	if not Part or not Part:IsA("BasePart") or not Marker or not Marker:IsA("BasePart") or not Detector then
		warn("[BaseLocking] own plot has no lock button, marker and click detector")
		return
	end

	local Button: Button = {
		Part = Part,
		Rest = Part.CFrame,
		Pressed = CFrame.new(Marker.Position) * Part.CFrame.Rotation,
		Size = Part.Size,
		Value = 0,
		Velocity = 0,
		Goal = 0,
		Hovered = false,
		ReleaseAt = 0,
	}

	self.Button = Button

	Detector.MouseClick:Connect(function()
		self:Press()
	end)

	Detector.MouseHoverEnter:Connect(function()
		Button.Hovered = true
		SoundController:Play("Hover")
	end)

	Detector.MouseHoverLeave:Connect(function()
		Button.Hovered = false
	end)
end

function BaseLockingController:Step(Delta: number, Clock: number)
	local Button = self.Button

	if Button then
		--> Held in until the hold is up, then wherever the cursor says it should rest.
		if Button.Goal ~= 1 or Clock >= Button.ReleaseAt then
			Button.Goal = if Button.Hovered then HoverValue else 0
		end

		local Step = math.min(Delta, MaxStep)

		Button.Velocity += (-Stiffness * (Button.Value - Button.Goal) - Damping * Button.Velocity) * Step
		Button.Value += Button.Velocity * Step

		Button.Part.CFrame = Button.Rest:Lerp(Button.Pressed, Button.Value)
		Button.Part.Size = Button.Size * (1 - Button.Value * Shrink)
	end

	--> The countdown, once a second's worth of change rather than every frame: the text only
	--> moves when the number does, and a label rewritten sixty times a second is a label that
	--> costs sixty times what it says.
	for _, Door in self.Doors do
		if Door.Locked and Door.Label then
			local Text = string.format(LabelFormat, SecondsLeft(GetUntil(Door.Plot)))

			if Door.Label.Text ~= Text then
				Door.Label.Text = Text
			end
		end
	end
end

function BaseLockingController:Init()
	local Container = workspace:WaitForChild(ContainerName)

	--> Spawned, because watching waits on the lasers turning up and Init is not the place to wait.
	for _, Plot in Container:GetChildren() do
		if Plot:IsA("Model") then
			task.spawn(function()
				self:WatchPlot(Plot)
			end)
		end
	end

	Container.ChildAdded:Connect(function(Plot)
		if Plot:IsA("Model") then
			task.spawn(function()
				self:WatchPlot(Plot)
			end)
		end
	end)

	Container.ChildRemoved:Connect(function(Plot)
		self.Doors[Plot] = nil
	end)
end

function BaseLockingController:Start()
	self:BindButton()

	RunService.RenderStepped:Connect(function(Delta: number)
		self:Step(Delta, os.clock())
	end)
end

return BaseLockingController
