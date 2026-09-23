local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Items = require(Shared.Utilities.Items)
local Parts = require(Assets.Parts)

local ContainerName = "Carried"
local EmployeesName = "Employees"
local RootName = "HumanoidRootPart"

local CardDrop = 2

--> Written by ItemService in the form Items.Carry gives while a player has something in hand.
--> Every client draws every other player's carry off it, and its own after a respawn, when the
--> model that was picked up off the pad has gone with the old character.
local CarryAttribute = "Carrying"

local Held = CFrame.new(0, 0, -2) * CFrame.Angles(0, math.rad(90), 0)

local Offsets: { [string]: CFrame } = {
	Keyboard = CFrame.new(0, 0.75, -2) * CFrame.Angles(0, math.rad(90), 0),
	Monitor = CFrame.new(0, 0.75, -2) * CFrame.Angles(0, math.rad(90), 0),
	Computer = CFrame.new(0, 0, -2) * CFrame.Angles(0, math.rad(180), 0),
}

--> An employee rides in front of the chest, upright and facing the way the carrier is, held by
--> the root. The rig's root sits at its hips, a little above the carrier's own.
local EmployeeHold = CFrame.new(0, 0.4, -2.6)

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

type Carry = {
	Model: Model,
	Posing: RBXScriptConnection,
}

local CarryController = {
	--> The model the local player picked up, carried over from the pad or the desk it came off
	--> with its card. Nil while nothing is in hand or while the attribute is drawing it instead.
	Model = nil :: Model?,
	Posing = nil :: RBXScriptConnection?,

	--> What everyone is seen carrying, the local player included once their own model is gone.
	Others = {} :: { [Player]: Carry },
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

--> An employee rig out of the assets, pivoted on its root so it can be held the way a part is.
--> The editor's keyframes come off the clone, as they do everywhere else a rig is built.
local function BuildEmployee(Type: string): Model?
	local Folder = Assets:FindFirstChild(EmployeesName)
	local Template = Folder and Folder:FindFirstChild(Type)

	if not Template or not Template:IsA("Model") then
		warn(`[Carry] No employee model named {Type}`)
		return nil
	end

	local Model = Template:Clone()
	local Root = Model:FindFirstChild(RootName) or Model.PrimaryPart

	if not Root or not Root:IsA("BasePart") then
		Model:Destroy()
		return nil
	end

	local AnimSaves = Model:FindFirstChild("AnimSaves")

	if AnimSaves then
		AnimSaves:Destroy()
	end

	Model.PrimaryPart = Root
	Model.WorldPivot = Root.CFrame

	return Model
end

--> The model for whatever the attribute says is carried, and where it rides.
local function BuildCarried(Entry: Items.Entry): (Model?, CFrame)
	if Items.IsEmployee(Entry) then
		return BuildEmployee(Entry.Type :: string), EmployeeHold
	end

	local Component = Entry.Component :: string

	return Parts(Component, Entry.Variant), Offsets[Component] or Held
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

--> Puts the model in the character's arms and holds the arms up for as long as both are there.
--> Stepped, not RenderStepped: the animator evaluates after it and would overwrite the pose. The
--> same pose drives every character, since Transform is written on the client for other players'
--> rigs just as it is for its own.
function CarryController:_Attach(
	Model: Model,
	Character: Model,
	Root: BasePart,
	Core: BasePart,
	Offset: CFrame
): RBXScriptConnection
	Model.Parent = GetContainer()
	Model:PivotTo(Root.CFrame * Offset)

	Bind(Model, Root, Core, Offset)

	local Joints = self:GetArmPose(Character)

	return RunService.Stepped:Connect(function()
		if not Root.Parent or not Model.Parent then
			return
		end

		for Joint, Target in Joints do
			(Joint :: any).Transform = Target
		end
	end)
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

	self:ClearOther(Players.LocalPlayer)
end

function CarryController:Hold(Model: Model, Component: string?, Card: BasePart?)
	local Character = Players.LocalPlayer.Character
	local Root = Character and Character:FindFirstChild(RootName) :: BasePart?
	local Core = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true)

	if not Character or not Root or not Core then
		Model:Destroy()
		return
	end

	self:Clear()

	local Offset = Offsets[Component or ""] or Held

	local Framing = if Card then Model:GetPivot():ToObjectSpace(Card.CFrame) else nil

	Model.Parent = GetContainer()
	Model:PivotTo(Root.CFrame * Offset)

	if Card and Framing then
		Card.CFrame = Model:GetPivot() * Framing

		local Readout = Card:FindFirstChildOfClass("BillboardGui")

		if Readout then
			Readout.StudsOffsetWorldSpace = Vector3.new(0, -CardDrop, 0)
		end

		Card.Parent = Model
	end

	self.Model = Model
	self.Posing = self:_Attach(Model, Character, Root, Core, Offset)
end

function CarryController:ClearOther(Player: Player)
	local Carry = self.Others[Player]

	if not Carry then
		return
	end

	self.Others[Player] = nil
	Carry.Posing:Disconnect()
	Carry.Model:Destroy()
end

--> Draws what the attribute says a player is carrying, in their arms. The local player's own
--> pickup keeps the exact model it took off the pad, card and all, so the attribute only draws
--> for them once that model is gone -- which is a respawn, or a part equipped out of the inventory.
function CarryController:RenderOther(Player: Player)
	self:ClearOther(Player)

	if Player == Players.LocalPlayer and self.Model then
		return
	end

	local Entry = Items.ReadCarry(Player:GetAttribute(CarryAttribute))
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild(RootName)

	if not Entry or not Character or not Root or not Root:IsA("BasePart") then
		return
	end

	local Model, Offset = BuildCarried(Entry)
	local Core = Model and (Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true))

	if not Model then
		return
	end

	if not Core then
		Model:Destroy()
		return
	end

	self.Others[Player] = {
		Model = Model,
		Posing = self:_Attach(Model, Character, Root, Core, Offset),
	}
end

function CarryController:Watch(Player: Player)
	Player:GetAttributeChangedSignal(CarryAttribute):Connect(function()
		self:RenderOther(Player)
	end)

	--> The rig arrives a piece at a time, and the arms have to be there to be posed.
	Player.CharacterAdded:Connect(function(Character: Model)
		Character:WaitForChild(RootName, 10)
		Character:WaitForChild("Humanoid", 10)

		if Player.Character == Character then
			self:RenderOther(Player)
		end
	end)

	Player.CharacterRemoving:Connect(function()
		self:ClearOther(Player)
	end)

	if Player.Character then
		self:RenderOther(Player)
	end
end

function CarryController:Start()
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		self:Clear()
	end)

	for _, Player in Players:GetPlayers() do
		self:Watch(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:Watch(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self:ClearOther(Player)
	end)
end

return CarryController
