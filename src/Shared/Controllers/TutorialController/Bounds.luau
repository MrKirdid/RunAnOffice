--> Where things are on the screen, for the highlight and the arrow: a gui object measured against
--> the tutorial's own screen, and a part or a model in the world projected through the camera.

--> How far in from the edge the arrow sits when what it points at is off the screen, as a fraction
--> of the viewport.
local EdgePadding = 0.08

export type ScreenBounds = {
	Visible: boolean,
	Position: Vector2,
	Size: Vector2,
}

local Bounds = {}

--> The box a thing in the world fills: a part's own, a model's bounding box.
function Bounds.GetBox(Target: PVInstance): (CFrame, Vector3)
	if Target:IsA("Model") then
		return Target:GetBoundingBox()
	end

	local Part = Target :: BasePart

	return Part.CFrame, Part.Size
end

--> A gui object's centre and size as fractions of a container, so a box in one ScreenGui can be
--> drawn around something in another. Both are read in screen pixels, which is the one space the
--> two share.
function Bounds.GetScaleRelativeTo(Holder: GuiObject, Container: GuiBase2d): (Vector2, Vector2)
	local ContainerPosition = Container.AbsolutePosition
	local ContainerSize = Container.AbsoluteSize

	local HolderCenter = Holder.AbsolutePosition + Holder.AbsoluteSize / 2
	local RelativeCenter = HolderCenter - ContainerPosition

	return RelativeCenter / ContainerSize, Holder.AbsoluteSize / ContainerSize
end

--> The box on the screen a thing fills, off the eight corners of its box. Nil when every corner
--> is behind the camera; Visible false when it is in front but off the sides.
function Bounds.GetScreenBounds(Target: PVInstance): ScreenBounds?
	local Camera = workspace.CurrentCamera
	local BoxCFrame, BoxSize = Bounds.GetBox(Target)
	local HalfSize = BoxSize / 2

	local MinX, MaxX = math.huge, -math.huge
	local MinY, MaxY = math.huge, -math.huge
	local HasFrontCorner = false

	for X = -1, 1, 2 do
		for Y = -1, 1, 2 do
			for Z = -1, 1, 2 do
				local Corner = Vector3.new(HalfSize.X * X, HalfSize.Y * Y, HalfSize.Z * Z)
				local ScreenPosition = Camera:WorldToViewportPoint(BoxCFrame:PointToWorldSpace(Corner))

				if ScreenPosition.Z <= 0 then
					continue
				end

				HasFrontCorner = true

				MinX = math.min(MinX, ScreenPosition.X)
				MaxX = math.max(MaxX, ScreenPosition.X)
				MinY = math.min(MinY, ScreenPosition.Y)
				MaxY = math.max(MaxY, ScreenPosition.Y)
			end
		end
	end

	if not HasFrontCorner then
		return nil
	end

	local ViewportSize = Camera.ViewportSize
	local OnScreen = MaxX > 0 and MinX < ViewportSize.X and MaxY > 0 and MinY < ViewportSize.Y

	if not OnScreen then
		return {
			Visible = false,
			Position = Vector2.new((MinX + MaxX) / 2, (MinY + MaxY) / 2),
			Size = Vector2.zero,
		}
	end

	local ClampedMinX = math.clamp(MinX, 0, ViewportSize.X)
	local ClampedMaxX = math.clamp(MaxX, 0, ViewportSize.X)
	local ClampedMinY = math.clamp(MinY, 0, ViewportSize.Y)
	local ClampedMaxY = math.clamp(MaxY, 0, ViewportSize.Y)

	return {
		Visible = true,
		Position = Vector2.new((ClampedMinX + ClampedMaxX) / 2, (ClampedMinY + ClampedMaxY) / 2),
		Size = Vector2.new(ClampedMaxX - ClampedMinX, ClampedMaxY - ClampedMinY),
	}
end

--> Where a thing's centre lands on the screen, in pixels. A point behind the camera is mirrored
--> through the middle of the screen, so an arrow aimed at it still points the way to turn.
function Bounds.GetScreenPoint(Target: PVInstance): Vector2
	local Camera = workspace.CurrentCamera
	local ScreenPosition = Camera:WorldToViewportPoint(Target:GetPivot().Position)
	local Point = Vector2.new(ScreenPosition.X, ScreenPosition.Y)

	return if ScreenPosition.Z < 0 then Camera.ViewportSize - Point else Point
end

--> The point on the edge of the screen in the direction of somewhere off it, padded in from the
--> border so the arrow is whole.
function Bounds.GetEdgePosition(ScreenPosition: Vector2): Vector2
	local ViewportSize = workspace.CurrentCamera.ViewportSize
	local Center = ViewportSize / 2
	local Direction = ScreenPosition - Center

	if Direction.Magnitude <= 0.001 then
		Direction = Vector2.new(0, 1)
	end

	Direction = Direction.Unit

	local HalfWidth = ViewportSize.X / 2 - ViewportSize.X * EdgePadding
	local HalfHeight = ViewportSize.Y / 2 - ViewportSize.Y * EdgePadding

	local ScaleX = if math.abs(Direction.X) > 0.001 then HalfWidth / math.abs(Direction.X) else math.huge
	local ScaleY = if math.abs(Direction.Y) > 0.001 then HalfHeight / math.abs(Direction.Y) else math.huge

	return Center + Direction * math.min(ScaleX, ScaleY)
end

return Bounds
