--> Which floor of a plot a point is standing in. The boxes are the ones PlotTemplate carries on
--> every floor, sized to cover the whole room, and they are the same boxes the client reads to
--> decide which of its own floors to hide, so the server and the client never disagree about what
--> counts as inside. The plot is pivoted into place, so the test runs in each box's own space.

local FloorsName = "Floors"
local BoundsName = "IsInFloor"

local PlotBounds = {}

function PlotBounds.FloorAt(Plot: Model, Position: Vector3): number?
	local Floors = Plot:FindFirstChild(FloorsName)

	if not Floors then
		return nil
	end

	for _, Folder in Floors:GetChildren() do
		local Floor = tonumber(Folder.Name)
		local Bounds = Folder:FindFirstChild(BoundsName)

		if not Floor or not Bounds or not Bounds:IsA("BasePart") then
			continue
		end

		local Local = Bounds.CFrame:PointToObjectSpace(Position)
		local Half = Bounds.Size / 2

		if math.abs(Local.X) <= Half.X and math.abs(Local.Y) <= Half.Y and math.abs(Local.Z) <= Half.Z then
			return Floor
		end
	end

	return nil
end

function PlotBounds.IsInside(Plot: Model, Position: Vector3): boolean
	return PlotBounds.FloorAt(Plot, Position) ~= nil
end

return PlotBounds
