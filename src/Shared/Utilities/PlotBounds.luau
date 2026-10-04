--> Which floor of a plot a point is standing in. The boxes are the ones PlotTemplate carries on
--> every floor, sized to cover the whole room, and they are the same boxes the client reads to
--> decide which of its own floors to hide, so the server and the client never disagree about what
--> counts as inside. The plot is pivoted into place, so the test runs in each box's own space.

--> Owned leaves out the floors the owner has not bought. Those stand stacked on the server but are
--> hidden and walked through on every client, so the box of the floor above is just the air over
--> the roof, and standing on a roof is not being in the base.

local FloorsName = "Floors"
local BoundsName = "IsInFloor"

--> The one part of a floor's lid the builder gave a name to. The other six are laid flush with its
--> underside and left called Part, so this slab is what the rest are measured against rather than
--> something to go looking for by name.
local RoofName = "Roof"

--> How far under the slab still counts as the lid. The highest thing below it is the wall trim,
--> which starts 0.3 further down, so this leaves room for float error and reaches nothing else.
local RoofSlack = 0.05

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

local PlotBounds = {}

function PlotBounds.FloorAt(Plot: Model, Position: Vector3, Owned: { number }?): number?
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

		if Owned and not table.find(Owned, Floor) then
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

function PlotBounds.IsInside(Plot: Model, Position: Vector3, Owned: { number }?): boolean
	return PlotBounds.FloorAt(Plot, Position, Owned) ~= nil
end

--> Every part a floor's lid is made of: the slab named Roof and the ones laid flush with it, found by
--> height because only the slab carries a name. Empty for a floor with no slab, or one whose slab
--> has not replicated in yet. The client takes the lid off the floor its owner is standing in, and
--> the server has to know which parts that is, since they stay solid here.
function PlotBounds.RoofOf(Folder: Instance): { BasePart }
	local Roof = {}
	local Slab = nil :: BasePart?

	for _, Object in Folder:GetDescendants() do
		if Object.Name == RoofName and Object:IsA("BasePart") then
			Slab = Object
			break
		end
	end

	if not Slab then
		return Roof
	end

	local Line = -Slab.Size.Y / 2 - RoofSlack

	for _, Object in Folder:GetDescendants() do
		if Object:IsA("BasePart") and Underside(Slab.CFrame, Object) >= Line then
			table.insert(Roof, Object)
		end
	end

	return Roof
end

return PlotBounds
