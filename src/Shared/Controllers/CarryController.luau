--> Holding a rolled part out in front of you. The arms are posed by writing their joints every
--> frame rather than by playing an animation, so the pose sits on top of the walk cycle instead of
--> taking turns with it. The part itself is welded rather than moved each frame, because a part
--> that is placed once a frame is always placed where the player was, not where they are.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ContainerName = "Carried"

--> Studs to bring the readout down once the part is in hand. It was framed for a part lying on a
--> pad, and that same framing floats way over the head of one held at chest height.
local CardDrop = 2

--> Out in front and turned side on, measured off the root rather than the torso so the part does
--> not sway with the walk cycle. Each shape needs its own framing: the flat ones sit low enough
--> without a lift that they read as floating rather than held, and the tower reads back to front
--> at the angle the other two want.
local Held = CFrame.new(0, 0, -2) * CFrame.Angles(0, math.rad(90), 0)

local Offsets: { [string]: CFrame } = {
	Keyboard = CFrame.new(0, 0.75, -2) * CFrame.Angles(0, math.rad(90), 0),
	Monitor = CFrame.new(0, 0.75, -2) * CFrame.Angles(0, math.rad(90), 0),
	Computer = CFrame.new(0, 0, -2) * CFrame.Angles(0, math.rad(180), 0),
}

--> The shoulders swing the arms forward, everything below them is pinned straight so the walk
--> cycle stops bending the elbows, and the torso is pinned too. The torso matters: the arms hang
--> off it, so any lean it keeps is a lean the arms inherit, and the part is placed off the root
--> rather than the torso. Left leaning, the arms miss what they are holding by about fifteen
--> degrees. Pinned, they line up exactly.
--> Both rigs are listed together rather than picked between, because their joint names never
--> collide: a rig only ever answers to one half of this table. They do not share an axis either.
--> An R15 shoulder sits square to the torso, so forward is a turn about X. An R6 shoulder carries
--> a quarter turn in its own C0, which leaves forward a turn about Z, mirrored between the arms.
local Pose: { [string]: CFrame } = {
	--> R15
	RightShoulder = CFrame.Angles(math.rad(90), 0, 0),
	LeftShoulder = CFrame.Angles(math.rad(90), 0, 0),
	RightElbow = CFrame.identity,
	LeftElbow = CFrame.identity,
	RightWrist = CFrame.identity,
	LeftWrist = CFrame.identity,
	Waist = CFrame.identity,
	Root = CFrame.identity,

	--> R6, whose arm is a single part and so has no elbow or wrist to straighten, and whose torso
	--> hangs off the root directly with no waist in between
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

--> Every arm joint on this character paired with what it should be held at, whichever rig it
--> turned out to be. Found by name and not by class, because an R15 joints with Motor6Ds in some
--> places and AnimationConstraints in others, and both drive the limb through the same Transform.
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

--> A model is a loose pile of parts until something holds it together, so the pile is bound to one
--> of its own before that one is bound to the player. Anchored parts ignore welds entirely, and an
--> anchored part inside the character's assembly would nail the player to the spot.
local function Bind(Model: Model, Root: BasePart, Core: BasePart, Offset: CFrame)
	--> Every weld first, while the pile is still standing in the shape it should keep. A
	--> WeldConstraint records the gap between its two parts the moment it has both.
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

	--> The offset is where the model's pivot should sit, but a weld drives a part, so the core's
	--> own place within the model rides along in C0.
	local Hold = Instance.new("Weld")
	Hold.Name = "CarryWeld"
	Hold.Part0 = Root
	Hold.Part1 = Core
	Hold.C0 = Offset * Model:GetPivot():ToObjectSpace(Core.CFrame)
	--> Parented to the part it carries, so dropping the model takes the weld with it
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

	--> Nothing to put back: the animator writes Transform again the moment it stops being overruled
end

--> Whatever was already in hand is dropped for the new one, so the prompts never need to know
--> whether the player has their hands full. Card is the readout the roll put over the part, and
--> it comes along so the player can still read what they are carrying.
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

	--> Out of the roll's container, which the next roll throws away wholesale
	Model.Parent = GetContainer()

	--> The card is standing where the part used to be, so it is carried across to where the part
	--> is going before anything gets welded to anything.
	local Framing = if Card then Model:GetPivot():ToObjectSpace(Card.CFrame) else nil

	Model:PivotTo(Root.CFrame * Offset)

	if Card and Framing then
		Card.CFrame = Model:GetPivot() * Framing

		local Readout = Card:FindFirstChildOfClass("BillboardGui")

		if Readout then
			Readout.StudsOffsetWorldSpace = Vector3.new(0, -CardDrop, 0)
		end

		--> Inside the model, so Bind welds and unanchors it with everything else and dropping the
		--> part takes its readout with it
		Card.Parent = Model
	end

	Bind(Model, Root, Core, Offset)

	self.Model = Model

	local Joints = self:GetArmPose(Character)

	--> Written in the step before the simulation, because that is where the animator evaluates and
	--> the last write before it is the one that lands. Doing this on a render step instead looks
	--> like it works, and reads back like it works, but the animator overwrites every frame and the
	--> arms never leave the walk cycle. This is the difference between an arm pointing where it is
	--> told and an arm pointing at the floor.
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
	--> A respawn hands back a character with no pose and leaves the part orphaned in the world
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		self:Clear()
	end)
end

return CarryController
