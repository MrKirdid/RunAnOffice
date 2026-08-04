--> Standalone showcase: builds every Variant/Component model out at DEMO_ORIGIN with a
--> billboard render floating over each one. Nothing else requires this, call it by hand:
--> require(Shared.Controllers.PartsDemoController):Init()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local Renders = require(Shared.Configs.Renders)
local PartConfigs = require(Shared.Configs.Parts)

local DEMO_ORIGIN = Vector3.new(0, 1000, 0)
local DEMO_NAME = "PartsDemo"

--> Cheapest to priciest, so each row reads left to right as a value ramp.
local COMPONENT_ORDER = { "Keyboard", "Monitor", "Computer" }

local VARIANTS_PER_ROW = 4
local COMPONENT_SPACING = 11
local GROUP_SPACING_X = 40
local GROUP_SPACING_Z = 17

local PEDESTAL_SIZE = Vector3.new(8, 1, 8)
local PEDESTAL_COLOR = Color3.fromRGB(48, 52, 60)
local FLOOR_PADDING = 16
local FLOOR_THICKNESS = 2
local FLOOR_COLOR = Color3.fromRGB(30, 32, 38)

local BILLBOARD_STUDS = 6
local BILLBOARD_GAP = 1.5
local BILLBOARD_MAX_DISTANCE = 300

local PartsDemoController = {
	Container = nil :: Model?,
}

local PartsModule: ((string, string) -> Model)?

local function GetPartsModule(): (string, string) -> Model
	if PartsModule then
		return PartsModule
	end

	local Module = Assets:WaitForChild("Parts", 10)
	assert(
		Module,
		"[PartsDemo] ReplicatedStorage.Assets.Parts is missing. The loader module currently sits at Workspace.Parts, move it under Assets."
	)

	PartsModule = require(Module) :: any
	return PartsModule :: any
end

--> Renders keys are the source of truth for what gets shown, ordered by variant value so
--> the grid walks from common to rare.
local function GetVariantOrder(): { string }
	local Variants = {}

	for VariantName in Renders.Components do
		table.insert(Variants, VariantName)
	end

	table.sort(Variants, function(A, B)
		local ValueA = PartConfigs.Variants[A] and PartConfigs.Variants[A].Value or math.huge
		local ValueB = PartConfigs.Variants[B] and PartConfigs.Variants[B].Value or math.huge

		if ValueA == ValueB then
			return A < B
		end
		return ValueA < ValueB
	end)

	return Variants
end

local function BuildPedestal(Position: Vector3, Parent: Instance): Part
	local Pedestal = Instance.new("Part")
	Pedestal.Name = "Pedestal"
	Pedestal.Size = PEDESTAL_SIZE
	Pedestal.CFrame = CFrame.new(Position - Vector3.new(0, PEDESTAL_SIZE.Y / 2, 0))
	Pedestal.Anchored = true
	Pedestal.CanCollide = true
	Pedestal.Material = Enum.Material.SmoothPlastic
	Pedestal.Color = PEDESTAL_COLOR
	Pedestal.TopSurface = Enum.SurfaceType.Smooth
	Pedestal.BottomSurface = Enum.SurfaceType.Smooth
	Pedestal.Parent = Parent

	return Pedestal
end

local function BuildBillboard(Adornee: BasePart, Image: string, Label: string, Height: number)
	local Billboard = Instance.new("BillboardGui")
	Billboard.Name = "Render"
	Billboard.Size = UDim2.fromScale(BILLBOARD_STUDS, BILLBOARD_STUDS * 1.2)
	Billboard.SizeOffset = Vector2.new(0, 0.5) --> sit fully above the offset point
	Billboard.StudsOffsetWorldSpace = Vector3.new(0, Height + BILLBOARD_GAP, 0)
	Billboard.MaxDistance = BILLBOARD_MAX_DISTANCE
	Billboard.LightInfluence = 0
	Billboard.ResetOnSpawn = false
	Billboard.Adornee = Adornee
	Billboard.Parent = Adornee

	local Render = Instance.new("ImageLabel")
	Render.Name = "Icon"
	Render.Size = UDim2.fromScale(1, 0.78)
	Render.BackgroundTransparency = 1
	Render.Image = Image
	Render.ScaleType = Enum.ScaleType.Fit
	Render.Parent = Billboard

	local Title = Instance.new("TextLabel")
	Title.Name = "Title"
	Title.Position = UDim2.fromScale(0, 0.78)
	Title.Size = UDim2.fromScale(1, 0.22)
	Title.BackgroundTransparency = 1
	Title.Text = Label
	Title.TextColor3 = Color3.fromRGB(255, 255, 255)
	Title.TextStrokeTransparency = 0.4
	Title.TextScaled = true
	Title.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	Title.Parent = Billboard
end

local function BuildFloor(Width: number, Depth: number, Parent: Instance)
	local Floor = Instance.new("Part")
	Floor.Name = "Floor"
	Floor.Size = Vector3.new(Width + FLOOR_PADDING * 2, FLOOR_THICKNESS, Depth + FLOOR_PADDING * 2)
	Floor.CFrame = CFrame.new(DEMO_ORIGIN - Vector3.new(0, PEDESTAL_SIZE.Y + FLOOR_THICKNESS / 2, 0))
	Floor.Anchored = true
	Floor.CanCollide = true
	Floor.Material = Enum.Material.SmoothPlastic
	Floor.Color = FLOOR_COLOR
	Floor.TopSurface = Enum.SurfaceType.Smooth
	Floor.BottomSurface = Enum.SurfaceType.Smooth
	Floor.Parent = Parent
end

--> Drops the model so its bounding-box bottom lands on Position, orientation untouched.
local function PlaceOnGround(Model: Model, Position: Vector3): number
	local BoxCFrame, BoxSize = Model:GetBoundingBox()
	local BottomCenter = BoxCFrame.Position - Vector3.new(0, BoxSize.Y / 2, 0)

	Model:PivotTo(Model:GetPivot() + (Position - BottomCenter))

	return BoxSize.Y
end

function PartsDemoController:Clear()
	local Existing = self.Container or workspace:FindFirstChild(DEMO_NAME)
	if Existing then
		Existing:Destroy()
	end

	self.Container = nil
end

function PartsDemoController:Build(): Model
	local Parts = GetPartsModule()

	self:Clear()

	local Container = Instance.new("Model")
	Container.Name = DEMO_NAME

	local Variants = GetVariantOrder()
	local Columns = math.min(#Variants, VARIANTS_PER_ROW)
	local Rows = math.ceil(#Variants / VARIANTS_PER_ROW)

	local GridWidth = (Columns - 1) * GROUP_SPACING_X + (#COMPONENT_ORDER - 1) * COMPONENT_SPACING
	local GridDepth = (Rows - 1) * GROUP_SPACING_Z
	local StartX = -GridWidth / 2
	local StartZ = -GridDepth / 2

	BuildFloor(GridWidth, GridDepth, Container)

	for VariantIndex, Variant in Variants do
		local GroupX = (VariantIndex - 1) % VARIANTS_PER_ROW
		local GroupZ = math.floor((VariantIndex - 1) / VARIANTS_PER_ROW)

		local Group = Instance.new("Folder")
		Group.Name = Variant
		Group.Parent = Container

		for ComponentIndex, Component in COMPONENT_ORDER do
			local Render = Renders.Components[Variant][Component]
			if not Render then
				warn(`[PartsDemo] No render for {Variant}.{Component}`)
				continue
			end

			local Position = DEMO_ORIGIN
				+ Vector3.new(
					StartX + GroupX * GROUP_SPACING_X + (ComponentIndex - 1) * COMPONENT_SPACING,
					0,
					StartZ + GroupZ * GROUP_SPACING_Z
				)

			local Pedestal = BuildPedestal(Position, Group)
			Pedestal.Name = `{Variant}_{Component}`

			local Success, Model = pcall(Parts, Component, Variant)
			if not Success or not Model then
				warn(`[PartsDemo] Failed to load {Variant}.{Component}: {Model}`)
				BuildBillboard(Pedestal, Render, `{Variant} {Component}\n(missing model)`, PEDESTAL_SIZE.Y)
				continue
			end

			for _, Descendant in Model:GetDescendants() do
				if Descendant:IsA("BasePart") then
					Descendant.Anchored = true
					Descendant.CanCollide = false
					Descendant.CanQuery = false
					Descendant.CanTouch = false
				end
			end

			Model.Name = Component
			Model.Parent = Group

			local Height = PlaceOnGround(Model, Position)
			BuildBillboard(Pedestal, Render, `{Variant} {Component}`, Height)
		end
	end

	Container.Parent = workspace
	self.Container = Container

	return Container
end

--> Convenience for poking at it in Studio, drops you on the demo floor.
function PartsDemoController:Teleport()
	local Character = Players.LocalPlayer.Character
	if not Character then
		return
	end

	Character:PivotTo(CFrame.new(DEMO_ORIGIN + Vector3.new(0, 5, -35)) * CFrame.Angles(0, math.pi, 0))
end

function PartsDemoController:Init(): Model
	return self:Build()
end

return PartsDemoController
