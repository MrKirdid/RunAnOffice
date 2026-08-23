local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ContainerName = "Carried"

local CardDrop = 2

local Held = CFrame.new(0, 0, -2) * CFrame.Angles(0, math.rad(90), 0)

local Offsets: { [string]: CFrame } = {
	Keyboard = CFrame.new(0, 0.75, -2) * CFrame.Angles(0, math.rad(90), 0),
	Monitor = CFrame.new(0, 0.75, -2) * CFrame.Angles(0, math.rad(90), 0),
	Computer = CFrame.new(0, 0, -2) * CFrame.Angles(0, math.rad(180), 0),
}

local Pose: { [string]: CFrame } = {
	RightShoulder = CFrame.Angles(math.rad(90), 0, 0),
	LeftShoulder = CFrame.Angles(math.rad(90), 0, 0),
	RightElbow = CFrame.identity,
	LeftElbow = CFrame.identity,
	RightWrist = CFrame.identity,
	LeftWrist = CFrame.identity,
	Waist = CFrame.identity,
	Root = CFrame.identity,

	["Right Shoulder"] = CFrame.Angles(0, 0, math.rad(90)),
	["Left Shoulder"] = CFrame.Angles(0, 0, math.rad(-90)),
	RootJoint = CFrame.identity,
}

local CarryController = {
	Model = nil :: Model?,
	Posing = nil :: RBXScriptConnection?,
}

local function GetContainer(): Folder
	local Existing = workspace:FindFirstChild(ContainerName)

	if Existing then
		return Existing :: Folder
	end

	local Container = Instance.new("Folder")
	Container.Name = ContainerName
	Container.Parent = workspace

	return Container
end

function CarryController:GetArmPose(Character: Model): { [Instance]: CFrame }
	local Joints = {}

	for _, Descendant in Character:GetDescendants() do
		local Target = Pose[Descendant.Name]

		if Target and (Descendant:IsA("Motor6D") or Descendant:IsA("AnimationConstraint")) then
			Joints[Descendant] = Target
		end
	end

	return Joints
end

local function Bind(Model: Model, Root: BasePart, Core: BasePart, Offset: CFrame)
	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") and Descendant ~= Core then
			local Joint = Instance.new("WeldConstraint")
			Joint.Part0 = Core
			Joint.Part1 = Descendant
			Joint.Parent = Core
		end
	end

	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.Anchored = false
			Descendant.CanCollide = false
			Descendant.CanQuery = false
			Descendant.CanTouch = false
			Descendant.Massless = true
		end
	end

	local Hold = Instance.new("Weld")
	Hold.Name = "CarryWeld"
	Hold.Part0 = Root
	Hold.Part1 = Core
	Hold.C0 = Offset * Model:GetPivot():ToObjectSpace(Core.CFrame)
	Hold.Parent = Core
end

function CarryController:Clear()
	if self.Posing then
		self.Posing:Disconnect()
		self.Posing = nil
	end

	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
end

function CarryController:Hold(Model: Model, Component: string?, Card: BasePart?)
	local Character = Players.LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local Core = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true)

	if not Character or not Root or not Core then
		Model:Destroy()
		return
	end

	self:Clear()

	local Offset = Offsets[Component or ""] or Held

	Model.Parent = GetContainer()

	local Framing = if Card then Model:GetPivot():ToObjectSpace(Card.CFrame) else nil

	Model:PivotTo(Root.CFrame * Offset)

	if Card and Framing then
		Card.CFrame = Model:GetPivot() * Framing

		local Readout = Card:FindFirstChildOfClass("BillboardGui")

		if Readout then
			Readout.StudsOffsetWorldSpace = Vector3.new(0, -CardDrop, 0)
		end

		Card.Parent = Model
	end

	Bind(Model, Root, Core, Offset)

	self.Model = Model

	local Joints = self:GetArmPose(Character)

	--> Stepped, not RenderStepped: the animator evaluates after it and would overwrite the pose.
	self.Posing = RunService.Stepped:Connect(function()
		if not Root.Parent or not Model.Parent then
			self:Clear()
			return
		end

		for Joint, Target in Joints do
			(Joint :: any).Transform = Target
		end
	end)
end

function CarryController:Start()
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		self:Clear()
	end)
end

return CarryController
