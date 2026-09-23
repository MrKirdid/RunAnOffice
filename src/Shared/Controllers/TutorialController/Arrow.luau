local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Bounds = require(script.Parent.Bounds)

--> The arrow on the screen. Parked over a gui object it bobs above it; put on a part it hangs
--> over the part's box and turns to face it, and when the part is off the screen it sits on the
--> edge nearest to it, pointing the way to turn.

local MoveTween = TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local TrackTween = TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local TurnTween = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FadeTween = TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

--> The two loops: a slow bob up and down while parked, and a pulse of the scale that runs the
--> whole time it is out.
local BobTween = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, true)
local PulseTween = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out, -1, true)

local BobDistance = 0.01
local ParkedPulse = 1.175
local TrackingPulse = 1.35

--> How far above the box the arrow floats, in pixels, and how far the whole thing is lifted off
--> where it is aimed, as a fraction of the screen.
local Clearance = 12
local Lift = 0.03

local Arrow = {
	Image = nil :: ImageLabel?,
	Scale = nil :: UIScale?,

	--> The loops are the only tweens held: a loop never finishes on its own, and both have to be
	--> stopped before anything writes the property they are moving.
	Bob = nil :: Tween?,
	Pulse = nil :: Tween?,

	Target = nil :: PVInstance?,
	Connections = {} :: { RBXScriptConnection },

	--> Bumped by everything that brings the arrow out, so a Stop still fading it away when the next
	--> step put it back does not switch it off under that step.
	Generation = 0,
}

function Arrow:Attach(Image: ImageLabel)
	self.Image = Image
	self.Scale = Image:FindFirstChildOfClass("UIScale")
end

function Arrow:_StopLoops()
	if self.Bob then
		self.Bob:Cancel()
		self.Bob = nil
	end

	if self.Pulse then
		self.Pulse:Cancel()
		self.Pulse = nil
	end
end

function Arrow:_Untrack()
	self.Target = nil

	for _, Connection in self.Connections do
		Connection:Disconnect()
	end

	table.clear(self.Connections)

	self:_StopLoops()
end

function Arrow:_Pulse(To: number)
	local Scale = self.Scale

	if not Scale then
		return
	end

	if self.Pulse then
		self.Pulse:Cancel()
	end

	Scale.Scale = 1

	self.Pulse = TweenService:Create(Scale, PulseTween, { Scale = To })
	self.Pulse:Play()
end

--> Tweened rather than set: a Stop still fading the arrow out keeps driving the transparency
--> until it lands, and a value written under it is overwritten a frame later. A newer tween on
--> the same property takes it over.
function Arrow:_FadeIn()
	local Image = self.Image

	if not Image then
		return
	end

	TweenService:Create(Image, FadeTween, { ImageTransparency = 0 }):Play()
end

--> The parked loop: bobbing over wherever the arrow was left.
function Arrow:_Bob()
	local Image = self.Image

	if not Image then
		return
	end

	if self.Bob then
		self.Bob:Cancel()
	end

	local Position = Image.Position

	self.Bob = TweenService:Create(Image, BobTween, {
		Position = UDim2.fromScale(Position.X.Scale, Position.Y.Scale - BobDistance),
	})
	self.Bob:Play()

	self:_Pulse(ParkedPulse)
end

--> Brings the arrow out in the middle of the screen, pointing up, ready to be moved.
function Arrow:Show()
	local Image = self.Image

	if not Image then
		return
	end

	self:_Untrack()
	self.Generation += 1

	Image.Rotation = 0
	Image.Position = UDim2.fromScale(0.5, 0.5)
	Image.Visible = true

	self:_FadeIn()

	self:_Bob()
end

--> Slides the arrow to a point on the screen and parks it there.
function Arrow:Move(Position: UDim2, Rotation: number?)
	local Image = self.Image

	if not Image then
		return
	end

	self:_Untrack()
	self.Generation += 1

	Image.Visible = true

	self:_FadeIn()

	if Rotation then
		TweenService:Create(Image, TurnTween, { Rotation = Rotation }):Play()
	end

	local Move = TweenService:Create(Image, MoveTween, { Position = Position })

	Move.Completed:Once(function(State: Enum.PlaybackState)
		if State ~= Enum.PlaybackState.Completed or self.Target then
			return
		end

		self:_Bob()
	end)

	Move:Play()

	self:_Pulse(ParkedPulse)
end

--> Parks the arrow just above a gui object, pointing down at it. Measured off the object rather
--> than off a number written per button, so it lands on whichever hud was cloned this time.
function Arrow:Point(Holder: GuiObject)
	local Image = self.Image

	if not Image then
		return
	end

	local Container = Image.Parent :: GuiBase2d
	local Center = Holder.AbsolutePosition + Holder.AbsoluteSize / 2
	local Top = Holder.AbsolutePosition.Y - Image.AbsoluteSize.Y / 2 - Clearance
	local Relative = (Vector2.new(Center.X, Top) - Container.AbsolutePosition) / Container.AbsoluteSize

	--> the image points down at rest, so no turn at all is pointing at the button
	self:Move(UDim2.fromScale(Relative.X, Relative.Y), 0)
end

--> Where the arrow goes and which way it turns for a part: over its box when the part is on the
--> screen, on the nearest edge when it is not, and always clamped so it is whole.
function Arrow:_Aim(Part: PVInstance): (Vector2, number)
	local Image = self.Image :: ImageLabel
	local ViewportSize = workspace.CurrentCamera.ViewportSize
	local Box = Bounds.GetScreenBounds(Part)
	local Point = Bounds.GetScreenPoint(Part)

	local Position: Vector2

	if Box and Box.Visible then
		Position = Vector2.new(Box.Position.X, Box.Position.Y - Box.Size.Y / 2 - Image.AbsoluteSize.Y / 2 - Clearance)
	else
		Position = Bounds.GetEdgePosition(Point)
	end

	local Half = Image.AbsoluteSize / 2

	Position = Vector2.new(
		math.clamp(Position.X, Half.X, ViewportSize.X - Half.X),
		math.clamp(Position.Y, Half.Y, ViewportSize.Y - Half.Y)
	)

	local Direction = Point - Position
	local Rotation = Image.Rotation

	if Direction.Magnitude > 0.01 then
		Rotation = math.deg(math.atan2(Direction.Y, Direction.X)) - 90
	end

	return Position, Rotation
end

--> Hangs the arrow over a part and follows it. The first move is tweened; after that it is
--> written every frame.
function Arrow:TrackPart(Part: PVInstance)
	local Image = self.Image

	if not Image then
		return
	end

	self:_Untrack()
	self.Generation += 1

	self.Target = Part
	Image.Visible = true

	self:_FadeIn()

	local Camera = workspace.CurrentCamera
	local Position, Rotation = self:_Aim(Part)
	local ViewportSize = Camera.ViewportSize
	local Arrived = false

	local Move = TweenService:Create(Image, TrackTween, {
		Position = UDim2.fromScale(Position.X / ViewportSize.X, Position.Y / ViewportSize.Y - Lift),
	})

	Move.Completed:Once(function(State: Enum.PlaybackState)
		if State == Enum.PlaybackState.Completed and self.Target == Part then
			Arrived = true
		end
	end)

	TweenService:Create(Image, TurnTween, { Rotation = Rotation }):Play()
	Move:Play()

	self:_Pulse(TrackingPulse)

	table.insert(
		self.Connections,
		RunService.RenderStepped:Connect(function()
			if self.Target ~= Part then
				return
			end

			if not Part:IsDescendantOf(workspace) then
				self:_Untrack()
				return
			end

			if not Arrived then
				return
			end

			local Now, Turn = self:_Aim(Part)
			local Size = Camera.ViewportSize

			Image.Position = UDim2.fromScale(Now.X / Size.X, Now.Y / Size.Y - Lift)
			Image.Rotation = Turn
		end)
	)
end

--> Fades the arrow out and switches it off once it has gone.
function Arrow:Stop()
	local Image = self.Image

	if not Image then
		return
	end

	local Generation = self.Generation
	local Fade = TweenService:Create(Image, FadeTween, { ImageTransparency = 1 })

	Fade.Completed:Once(function(State: Enum.PlaybackState)
		if State ~= Enum.PlaybackState.Completed or self.Generation ~= Generation then
			return
		end

		self:_Untrack()
		Image.Visible = false
	end)

	Fade:Play()
end

return Arrow
