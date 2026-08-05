--> Standalone showcase: builds every Variant/Component model out at DemoOrigin with a
--> billboard render floating over each one. Nothing builds it on startup, it goes up on
--> demand through the `partsdemo` console command.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local Renders = require(Shared.Configs.Renders)
local PartConfigs = require(Shared.Configs.Parts)

local DemoOrigin = Vector3.new(0, 1000, 0)
local DemoName = "PartsDemo"

--> Cheapest to priciest, so each row reads left to right as a value ramp.
local ComponentOrder = { "Keyboard", "Monitor", "Computer" }

local VariantsPerRow = 4
local ComponentSpacing = 11
local GroupSpacingX = 40
local GroupSpacingZ = 17

local PedestalSize = Vector3.new(8, 1, 8)
local PedestalColor = Color3.fromRGB(48, 52, 60)
local FloorPadding = 16
local FloorThickness = 2
local FloorColor = Color3.fromRGB(30, 32, 38)

local BillboardStuds = 6
local BillboardGap = 1.5
local BillboardMaxDistance = 300

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
	Pedestal.Size = PedestalSize
	Pedestal.CFrame = CFrame.new(Position - Vector3.new(0, PedestalSize.Y / 2, 0))
	Pedestal.Anchored = true
	Pedestal.CanCollide = true
	Pedestal.Material = Enum.Material.SmoothPlastic
	Pedestal.Color = PedestalColor
	Pedestal.TopSurface = Enum.SurfaceType.Smooth
	Pedestal.BottomSurface = Enum.SurfaceType.Smooth
	Pedestal.Parent = Parent

	return Pedestal
end

local function BuildBillboard(Adornee: BasePart, Image: string, Label: string, Height: number)
	local Billboard = Instance.new("BillboardGui")
	Billboard.Name = "Render"
	Billboard.Size = UDim2.fromScale(BillboardStuds, BillboardStuds * 1.2)
	Billboard.SizeOffset = Vector2.new(0, 0.5) --> sit fully above the offset point
	Billboard.StudsOffsetWorldSpace = Vector3.new(0, Height + BillboardGap, 0)
	Billboard.MaxDistance = BillboardMaxDistance
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
	Floor.Size = Vector3.new(Width + FloorPadding * 2, FloorThickness, Depth + FloorPadding * 2)
	Floor.CFrame = CFrame.new(DemoOrigin - Vector3.new(0, PedestalSize.Y + FloorThickness / 2, 0))
	Floor.Anchored = true
	Floor.CanCollide = true
	Floor.Material = Enum.Material.SmoothPlastic
	Floor.Color = FloorColor
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
	local Existing = self.Container or workspace:FindFirstChild(DemoName)
	if Existing then
		Existing:Destroy()
	end

	self.Container = nil
end

function PartsDemoController:Build(): Model
	local Parts = GetPartsModule()

	self:Clear()

	local Container = Instance.new("Model")
	Container.Name = DemoName

	local Variants = GetVariantOrder()
	local Columns = math.min(#Variants, VariantsPerRow)
	local Rows = math.ceil(#Variants / VariantsPerRow)

	local GridWidth = (Columns - 1) * GroupSpacingX + (#ComponentOrder - 1) * ComponentSpacing
	local GridDepth = (Rows - 1) * GroupSpacingZ
	local StartX = -GridWidth / 2
	local StartZ = -GridDepth / 2

	BuildFloor(GridWidth, GridDepth, Container)

	for VariantIndex, Variant in Variants do
		local GroupX = (VariantIndex - 1) % VariantsPerRow
		local GroupZ = math.floor((VariantIndex - 1) / VariantsPerRow)

		local Group = Instance.new("Folder")
		Group.Name = Variant
		Group.Parent = Container

		for ComponentIndex, Component in ComponentOrder do
			local Render = Renders.Components[Variant][Component]
			if not Render then
				warn(`[PartsDemo] No render for {Variant}.{Component}`)
				continue
			end

			local Position = DemoOrigin
				+ Vector3.new(
					StartX + GroupX * GroupSpacingX + (ComponentIndex - 1) * ComponentSpacing,
					0,
					StartZ + GroupZ * GroupSpacingZ
				)

			local Pedestal = BuildPedestal(Position, Group)
			Pedestal.Name = `{Variant}_{Component}`

			local Success, Model = pcall(Parts, Component, Variant)
			if not Success or not Model then
				warn(`[PartsDemo] Failed to load {Variant}.{Component}: {Model}`)
				BuildBillboard(Pedestal, Render, `{Variant} {Component}\n(missing model)`, PedestalSize.Y)
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

	Character:PivotTo(CFrame.new(DemoOrigin + Vector3.new(0, 5, -35)) * CFrame.Angles(0, math.pi, 0))
end

return PartsDemoController
