--!strict

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
