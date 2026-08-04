--!strict
--[[
	Desk placement CFrames for one floor of PlotTemplate, captured 2026-08-02.

	Each CFrame is the *Table* MeshPart's center (not the table+chair bounding-box
	pivot, which sits ~1.58 studs -X of it). Rotation is significant: the layout
	mixes 90deg, 180deg and 0deg desk orientations.

	These are floor 1 values. Floors are stacked at exactly 12 studs (slab tops
	at Y = 8.1 / 20.1 / 32.1 / 44.1), so floor N = base + Vector3.new(0, 12 * (N - 1), 0).
	Desks sit 1.9685 studs above their slab.

	Kept in source control because workspace geometry is not synced by Rojo and
	this machine has no Studio autosaves -- if the markers are lost, these rebuild them.
]]

local FLOOR_HEIGHT = 12

local DeskPlacements = {}

DeskPlacements.FloorHeight = FLOOR_HEIGHT

DeskPlacements.Base = {
	CFrame.new(186.499969, 10.068466, 27.019447, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	CFrame.new(186.912781, 10.068466, 37.819450, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	CFrame.new(169.668869, 10.068466, 20.286987, -1, 0, 0, 0, 1, 0, 0, 0, -1),
	CFrame.new(169.668869, 10.068466, 33.286987, -1, 0, 0, 0, 1, 0, 0, 0, -1),
	CFrame.new(169.668869, 10.068466, 46.286987, -1, 0, 0, 0, 1, 0, 0, 0, -1),
	CFrame.new(203.819626, 10.068466, 46.286987, 1, 0, 0, 0, 1, 0, 0, 0, 1),
	CFrame.new(203.819626, 10.068466, 33.286987, 1, 0, 0, 0, 1, 0, 0, 0, 1),
	CFrame.new(203.819626, 10.068466, 20.286987, 1, 0, 0, 0, 1, 0, 0, 0, 1),
} :: { CFrame }

-- Desk CFrames for the given floor number (1-4).
function DeskPlacements.forFloor(floor: number): { CFrame }
	local dy = Vector3.new(0, FLOOR_HEIGHT * (floor - 1), 0)
	local result = table.create(#DeskPlacements.Base)
	for i, cf in ipairs(DeskPlacements.Base) do
		result[i] = cf + dy
	end
	return result
end

return DeskPlacements
