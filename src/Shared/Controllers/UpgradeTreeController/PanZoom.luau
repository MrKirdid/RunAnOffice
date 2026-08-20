--> Panning and zooming for a canvas frame that sits behind a smaller window frame.
--> The UIDragDetector is not used: its bounding can only hold a small frame inside a big one, and
--> with ResponseStyle set to Offset it tracks its own idea of where the canvas is, so clamping the
--> canvas behind its back made the drag drift further every time it hit an edge.
--> Both the centre and the zoom are Fusion springs, so the canvas trails the pointer slightly,
--> glides on after a flick, and eases into the edges instead of stopping dead.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Fusion = require(Shared.Packages.Fusion)

local Peek = Fusion.peek

local MinZoom = 0.3
local MaxZoom = 2

--> multiplier per wheel notch
local WheelStep = 1.15

--> a press that travels further than this is a pan, not a click on a node
local DragThreshold = 12

local PanSpeed = 32
local PanDamping = 1
local ZoomSpeed = 18
local ZoomDamping = 0.85

--> how far a flick keeps travelling after the finger leaves, in seconds of its last speed
local GlideTime = 0.22
local MaxGlideSpeed = 6000

local ZoomActionName = "UpgradeTreeZoom"

--> above the camera scripts, so a wheel over the tree does not also pull the camera in
local ZoomActionPriority = Enum.ContextActionPriority.High.Value + 1000

export type Handle = {
	SetZoom: (Zoom: number) -> (),
	GetZoom: () -> number,
	HasPanned: () -> boolean,
	FitTo: (Min: Vector2, Max: Vector2) -> (),
}

--> share of the window the fitted content is allowed to fill
local FitMargin = 0.92

--> both cases are the same clamp: a canvas larger than the window may travel until an edge lines
--> up, a canvas smaller than the window may travel until it would leave. the pixel of slack that
--> is given back covers UDim offsets being whole numbers.
local function ClampAxis(Center: number, Half: number, WindowCenter: number, WindowHalf: number): number
	local Slack = math.max(math.abs(Half - WindowHalf) - 1, 0)

	return math.clamp(Center, WindowCenter - Slack, WindowCenter + Slack)
end

local function GetMidpoint(Points: { Vector2 }): Vector2
	local Total = Vector2.zero

	for _, Point in Points do
		Total += Point
	end

	return Total / #Points
end

local PanZoom = {}

function PanZoom.Apply(Scope: any, Canvas: GuiObject, Window: GuiObject): Handle
	local Space = Canvas.Parent :: GuiObject
	local Screen = Canvas:FindFirstAncestorWhichIsA("ScreenGui")
	local BaseScale = Vector2.new(Canvas.Size.X.Scale, Canvas.Size.Y.Scale)

	local DragInput: InputObject? = nil
	local LastPoint = Vector2.zero
	local LastMoveClock = 0
	local Velocity = Vector2.zero
	local PinchZoom: number? = nil
	local Travelled = 0
	local HoverPoint = Vector2.zero
	local CameraZoomRange: Vector2? = nil

	local function GetWindowCenter(): Vector2
		return Window.AbsolutePosition + Window.AbsoluteSize / 2
	end

	local ZoomGoal = Scope:Value(1)
	local ZoomSpring = Scope:Spring(ZoomGoal, ZoomSpeed, ZoomDamping)
	local CenterGoal = Scope:Value(GetWindowCenter())
	local CenterSpring = Scope:Spring(CenterGoal, PanSpeed, PanDamping)

	--> a screen that ignores the inset shares its coordinates with the mouse; one that does not is
	--> pushed down by the top bar and has to be corrected for
	local function GetInset(): Vector2
		if Screen and Screen.IgnoreGuiInset then
			return Vector2.zero
		end

		return GuiService:GetGuiInset()
	end

	local function GetCanvasSize(Zoom: number): Vector2
		return BaseScale * Zoom * Space.AbsoluteSize
	end

	local function Clamp(Center: Vector2, Zoom: number): Vector2
		local CanvasSize = GetCanvasSize(Zoom)
		local WindowSize = Window.AbsoluteSize
		local WindowCenter = GetWindowCenter()

		return Vector2.new(
			ClampAxis(Center.X, CanvasSize.X / 2, WindowCenter.X, WindowSize.X / 2),
			ClampAxis(Center.Y, CanvasSize.Y / 2, WindowCenter.Y, WindowSize.Y / 2)
		)
	end

	--> the spring output is clamped as well as the goal, so an overshoot can never carry the canvas
	--> past an edge
	local function Render()
		local Zoom = math.clamp(Peek(ZoomSpring), MinZoom, MaxZoom)
		local CanvasSize = GetCanvasSize(Zoom)
		local Center = Clamp(Peek(CenterSpring), Zoom)
		local SpaceSize = Space.AbsoluteSize
		local Position = Canvas.Position

		local Anchor = Center - (Vector2.new(0.5, 0.5) - Canvas.AnchorPoint) * CanvasSize - Space.AbsolutePosition

		Canvas.Size = UDim2.fromScale(BaseScale.X * Zoom, BaseScale.Y * Zoom)
		Canvas.Position = UDim2.new(
			Position.X.Scale,
			Anchor.X - Position.X.Scale * SpaceSize.X,
			Position.Y.Scale,
			Anchor.Y - Position.Y.Scale * SpaceSize.Y
		)
	end

	local function SetCenter(Center: Vector2)
		CenterGoal:set(Clamp(Center, Peek(ZoomGoal)))
	end

	--> zooms around a point, so whatever sits under the cursor or between the fingers stays put
	local function SetZoom(Target: number, Focus: Vector2)
		local Current = Peek(ZoomGoal)
		local Next = math.clamp(Target, MinZoom, MaxZoom)

		if Next == Current then
			return
		end

		ZoomGoal:set(Next)
		SetCenter(Focus + (Peek(CenterGoal) - Focus) * (Next / Current))
	end

	local function IsActive(): boolean
		return (Screen == nil or Screen.Enabled) and Window.AbsoluteSize.X > 0
	end

	local function IsInsideWindow(Point: Vector2): boolean
		local Min = Window.AbsolutePosition
		local Max = Min + Window.AbsoluteSize

		return Point.X >= Min.X and Point.X <= Max.X and Point.Y >= Min.Y and Point.Y <= Max.Y
	end

	local function GetPoint(Input: InputObject): Vector2
		return Vector2.new(Input.Position.X, Input.Position.Y) - GetInset()
	end

	--> sinking the wheel through ContextActionService only covers the input paths that reach it, so
	--> the camera is pinned to the distance it is already at while the pointer sits over the tree
	local function SetCameraLocked(Locked: boolean)
		local Player = Players.LocalPlayer
		local Saved = CameraZoomRange

		if Locked == (Saved ~= nil) then
			return
		end

		if not Locked then
			Player.CameraMinZoomDistance = (Saved :: Vector2).X
			Player.CameraMaxZoomDistance = (Saved :: Vector2).Y
			CameraZoomRange = nil
			return
		end

		local Camera = workspace.CurrentCamera

		if not Camera then
			return
		end

		CameraZoomRange = Vector2.new(Player.CameraMinZoomDistance, Player.CameraMaxZoomDistance)

		local Distance = math.clamp(
			(Camera.CFrame.Position - Camera.Focus.Position).Magnitude,
			Player.CameraMinZoomDistance,
			Player.CameraMaxZoomDistance
		)

		Player.CameraMinZoomDistance = Distance
		Player.CameraMaxZoomDistance = Distance
	end

	table.insert(
		Scope,
		UserInputService.InputBegan:Connect(function(Input: InputObject)
			local IsPointer = Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch

			if not IsPointer or PinchZoom or not IsActive() then
				return
			end

			local Point = GetPoint(Input)

			if not IsInsideWindow(Point) then
				return
			end

			DragInput = Input
			LastPoint = Point
			LastMoveClock = os.clock()
			Travelled = 0
			Velocity = Vector2.zero

			--> catch the canvas wherever the spring had drifted to, so grabbing it feels immediate
			SetCenter(Peek(CenterSpring))
		end)
	)

	--> this action only swallows the wheel before the camera scripts reach it -- the zoom itself is
	--> driven from InputChanged below, because not every input path reaches ContextActionService
	ContextActionService:BindActionAtPriority(ZoomActionName, function(): Enum.ContextActionResult
		if not IsActive() or not IsInsideWindow(HoverPoint) then
			return Enum.ContextActionResult.Pass
		end

		return Enum.ContextActionResult.Sink
	end, false, ZoomActionPriority, Enum.UserInputType.MouseWheel)

	table.insert(
		Scope,
		UserInputService.InputChanged:Connect(function(Input: InputObject)
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				HoverPoint = GetPoint(Input)
				SetCameraLocked(IsActive() and IsInsideWindow(HoverPoint))
			end

			if Input.UserInputType == Enum.UserInputType.MouseWheel then
				local Focus = GetPoint(Input)

				if not IsActive() or not IsInsideWindow(Focus) then
					return
				end

				SetZoom(Peek(ZoomGoal) * (if Input.Position.Z > 0 then WheelStep else 1 / WheelStep), Focus)
				return
			end

			local Dragging = DragInput

			if not Dragging or PinchZoom then
				return
			end

			local IsSameInput = Input == Dragging
				or (
					Dragging.UserInputType == Enum.UserInputType.MouseButton1
					and Input.UserInputType == Enum.UserInputType.MouseMovement
				)

			if not IsSameInput then
				return
			end

			local Point = GetPoint(Input)
			local Delta = Point - LastPoint
			local Clock = os.clock()
			local Elapsed = math.max(Clock - LastMoveClock, 1 / 240)

			Travelled += Delta.Magnitude
			LastPoint = Point
			LastMoveClock = Clock
			Velocity = Velocity:Lerp(Delta / Elapsed, 0.65)

			SetCenter(Peek(CenterGoal) + Delta)
		end)
	)

	table.insert(
		Scope,
		UserInputService.InputEnded:Connect(function(Input: InputObject)
			local Dragging = DragInput

			if not Dragging or Input.UserInputType ~= Dragging.UserInputType then
				return
			end

			DragInput = nil

			--> a flick keeps gliding; a slow release just stops where it is
			if os.clock() - LastMoveClock > 0.1 or Velocity.Magnitude < 100 then
				return
			end

			local Speed = math.min(Velocity.Magnitude, MaxGlideSpeed)

			SetCenter(Peek(CenterGoal) + Velocity.Unit * Speed * GlideTime)
		end)
	)

	--> two fingers on a phone
	table.insert(
		Scope,
		UserInputService.TouchPinch:Connect(function(TouchPositions: { Vector2 }, Scale: number, _Velocity, State)
			if not IsActive() then
				return
			end

			if State == Enum.UserInputState.Begin then
				PinchZoom = Peek(ZoomGoal)
				DragInput = nil
				return
			end

			local Started = PinchZoom

			if not Started then
				return
			end

			SetZoom(Started * Scale, GetMidpoint(TouchPositions) - GetInset())

			if State == Enum.UserInputState.End or State == Enum.UserInputState.Cancel then
				PinchZoom = nil
			end
		end)
	)

	--> trackpad pinch; the wheel arrives through InputChanged already
	table.insert(
		Scope,
		UserInputService.PointerAction:Connect(function(_Wheel: number, _Pan: Vector2, Pinch: number)
			local Focus = UserInputService:GetMouseLocation() - GetInset()

			if Pinch == 0 or not IsActive() or not IsInsideWindow(Focus) then
				return
			end

			SetZoom(Peek(ZoomGoal) * (1 + Pinch / 10), Focus)
		end)
	)

	local function Recenter()
		SetCenter(Peek(CenterGoal))
		Render()
	end

	table.insert(Scope, function()
		ContextActionService:UnbindAction(ZoomActionName)
		SetCameraLocked(false)
	end)

	if Screen then
		Screen:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not Screen.Enabled then
				SetCameraLocked(false)
			end
		end)
	end

	--> an active frame swallows the input it sits under, so dragging the tree cannot also swing the
	--> camera around on touch
	Canvas.Active = true

	Scope:Observer(CenterSpring):onChange(Render)
	Scope:Observer(ZoomSpring):onChange(Render)

	Space:GetPropertyChangedSignal("AbsoluteSize"):Connect(Recenter)
	Window:GetPropertyChangedSignal("AbsoluteSize"):Connect(Recenter)

	Recenter()

	return {
		SetZoom = function(Target: number)
			SetZoom(Target, GetWindowCenter())
		end,

		--> Min and Max are the content's corners in canvas scale. the zoom that makes it fill the
		--> window is applied at once rather than sprung, since this runs as the tree opens.
		FitTo = function(Min: Vector2, Max: Vector2)
			local Extent = (Max - Min) * GetCanvasSize(1)

			if Extent.X <= 0 or Extent.Y <= 0 then
				return
			end

			local Room = Window.AbsoluteSize * FitMargin
			local Next = math.clamp(math.min(Room.X / Extent.X, Room.Y / Extent.Y), MinZoom, MaxZoom)

			ZoomGoal:set(Next)
			ZoomSpring:setPosition(Next)

			SetCenter(GetWindowCenter() + (Vector2.new(0.5, 0.5) - (Min + Max) / 2) * GetCanvasSize(Next))
			CenterSpring:setPosition(Peek(CenterGoal))

			Render()
		end,

		GetZoom = function(): number
			return Peek(ZoomGoal)
		end,

		HasPanned = function(): boolean
			return Travelled > DragThreshold
		end,
	}
end

return PanZoom
