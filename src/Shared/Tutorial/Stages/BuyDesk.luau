local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotController = require(Shared.Controllers.PlotController)

--> The beam from the player's feet to the green button on the buy board. The server sees the
--> desk stand.

local BoardPath = { "Boards", "BuyDesk", "Main" }
local ButtonPath = { "BuyUI", "BuyDesk", "GoButton" }
local BoardWait = 15
local SpotName = "TutorialButtonSpot"

--> How long to wait for the board's gui to be laid out before settling for the board's middle.
local LayoutWait = 2

--> Where a point on a surface gui lands on its part, in the part's own space, by the face the gui
--> is on. Across runs left to right and Down top to bottom as a player facing that face reads
--> them, both from -0.5 to 0.5.
local Faces: { [Enum.NormalId]: (Size: Vector3, Across: number, Down: number) -> Vector3 } = {
	[Enum.NormalId.Front] = function(Size, Across, Down)
		return Vector3.new(-Size.X * Across, -Size.Y * Down, -Size.Z / 2)
	end,
	[Enum.NormalId.Back] = function(Size, Across, Down)
		return Vector3.new(Size.X * Across, -Size.Y * Down, Size.Z / 2)
	end,
	[Enum.NormalId.Left] = function(Size, Across, Down)
		return Vector3.new(-Size.X / 2, -Size.Y * Down, Size.Z * Across)
	end,
	[Enum.NormalId.Right] = function(Size, Across, Down)
		return Vector3.new(Size.X / 2, -Size.Y * Down, -Size.Z * Across)
	end,
}

--> The board is on the plot the player is stood on, so it is found rather than remembered.
local function FindBoard(): BasePart?
	local _, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local Current: Instance = Plot

	for _, Step in BoardPath do
		local Next = Current:WaitForChild(Step, BoardWait)

		if not Next then
			return nil
		end

		Current = Next
	end

	return if Current:IsA("BasePart") then Current else nil
end

--> An attachment on the board over its green button, worked out off where the button is drawn on
--> the board's gui, so the beam ends on the thing to press rather than in the middle of the
--> board. The board itself if the button or its face cannot be read.
local function FindButton(Board: BasePart): BasePart | Attachment
	local Current: Instance? = Board

	for _, Step in ButtonPath do
		Current = Current and Current:FindFirstChild(Step)
	end

	local Gui = Board:FindFirstChild(ButtonPath[1])

	if not Current or not Current:IsA("GuiObject") or not Gui or not Gui:IsA("SurfaceGui") then
		return Board
	end

	local Place = Faces[Gui.Face]

	if not Place then
		return Board
	end

	local Started = os.clock()

	while Gui.AbsoluteSize.X <= 0 and os.clock() - Started < LayoutWait do
		task.wait()
	end

	local Canvas = Gui.AbsoluteSize

	if Canvas.X <= 0 or Canvas.Y <= 0 then
		return Board
	end

	local Center = Current.AbsolutePosition + Current.AbsoluteSize / 2

	local Spot = Instance.new("Attachment")
	Spot.Name = SpotName
	Spot.Position = Place(Board.Size, Center.X / Canvas.X - 0.5, Center.Y / Canvas.Y - 0.5)
	Spot.Parent = Board

	return Spot
end

local Stage = {
	Connections = {} :: { RBXScriptConnection },
	Spot = nil :: Attachment?,
}

function Stage.Start(Tutorial: any)
	local Board = FindBoard()

	if not Board then
		warn("[Tutorial] the plot has no buy board to point at")
		return
	end

	local Target = FindButton(Board)

	Stage.Spot = if Target:IsA("Attachment") then Target else nil

	Tutorial.Follow:Start(Target)

	--> a respawn takes the beam's near end with the old character, so it is run again to the new one
	table.insert(
		Stage.Connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			Tutorial.Follow:Start(Target)
		end)
	)
end

function Stage.Cleanup(Tutorial: any)
	for _, Connection in Stage.Connections do
		Connection:Disconnect()
	end

	table.clear(Stage.Connections)

	Tutorial.Follow:Stop()

	if Stage.Spot then
		Stage.Spot:Destroy()
		Stage.Spot = nil
	end
end

return Stage
