--!strict
--[[
	Desk slots are authored in the plot, not in source. Every floor folder holds a
	"Desk Placements" folder of markers named 1..N, so the layout and the slot count
	both come from the instances and stay correct when the template changes.

	Everything takes a Plot model rather than reading the template, since each
	player's plot sits at its own spot in PlotContainer.
]]

local FolderName = "Desk Placements"

local DeskPlacements = {}

function DeskPlacements.GetFolder(Plot: Model, Floor: number): Folder?
	local Floors = Plot:FindFirstChild("Floors")
	local FloorFolder = Floors and Floors:FindFirstChild(tostring(Floor))

	return FloorFolder and FloorFolder:FindFirstChild(FolderName) :: Folder?
end

function DeskPlacements.GetCount(Plot: Model, Floor: number): number
	local Folder = DeskPlacements.GetFolder(Plot, Floor)

	return if Folder then #Folder:GetChildren() else 0
end

function DeskPlacements.GetCFrame(Plot: Model, Floor: number, Slot: number): CFrame?
	local Folder = DeskPlacements.GetFolder(Plot, Floor)
	local Marker = Folder and Folder:FindFirstChild(tostring(Slot))

	return if Marker then (Marker :: PVInstance):GetPivot() else nil
end

return DeskPlacements
