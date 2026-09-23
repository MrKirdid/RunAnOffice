local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local EmployeeController = require(Shared.Controllers.EmployeeController)
local VfxConfigs = require(Shared.Configs.Vfx)
local VfxController = require(Shared.Controllers.VfxController)

local Settings = VfxConfigs.Footsteps

type Entry = {
	Left: BasePart,
	Right: BasePart,
	Dust: BasePart,

	--> Where in the loop the rig was last frame. A plant is a phase the loop crossed between two
	--> frames rather than a phase it happens to be sitting on: a one second loop is sampled sixty
	--> times, and a test for being near a mark fires on several of them in a row.
	--> Nil until the walk has been seen for a frame, which is what keeps a rig that appears mid
	--> stride -- or one whose track just restarted -- from throwing a puff it never took a step for.
	Phase: number?,

	--> Which loop that phase was read off. Breaking into a run swaps one loop for another with its
	--> own marks in its own places, and a phase carried across the swap is a phase measured against
	--> the wrong animation.
	Loop: string?,
}

--> Dust under the feet of anything walking: the player, and every employee crossing the office. It
--> is read off the walk animation's own phase, so a foot is planted when the animation plants it
--> and the puff is thrown from where that foot actually is.
local FootstepController = {
	--> Keyed by rig, so one leaving takes only its own dust with it.
	Entries = {} :: { [Model]: Entry },
}

--> The loop a rig is walking to, or nothing if it is doing anything else. A rig standing still, in
--> the air, or sitting at a desk typing is playing something this does not name, and that is the
--> whole of the test for whether a foot is on the ground.
local function WalkTrack(Model: Model): AnimationTrack?
	local Controller = Model:FindFirstChildOfClass("AnimationController") or Model:FindFirstChildOfClass("Humanoid")
	local Animator = Controller and Controller:FindFirstChildOfClass("Animator")

	if not Animator then
		return nil
	end

	for _, Track in Animator:GetPlayingAnimationTracks() do
		if Settings.Plants[Track.Name] and Track.Length > 0 and Track.WeightCurrent >= Settings.MinWeight then
			return Track
		end
	end

	return nil
end

--> The two parts the rig stands on. R15 names its feet, R6 and the employee rigs stop at the leg,
--> so whichever pair the rig actually has is the pair used.
local function FindFeet(Model: Model): (BasePart?, BasePart?)
	for _, Pair in Settings.Feet do
		local Left = Model:FindFirstChild(Pair.Left, true)
		local Right = Model:FindFirstChild(Pair.Right, true)

		if Left and Left:IsA("BasePart") and Right and Right:IsA("BasePart") then
			return Left, Right
		end
	end

	return nil, nil
end

--> The floor under a foot, taken off the foot rather than off a raycast: the sole is the part's
--> lowest corner however the animation has it turned, which is its three half extents projected
--> onto world up.
local function Sole(Foot: BasePart): Vector3
	local Frame = Foot.CFrame
	local Half = Foot.Size / 2

	local Reach = math.abs(Frame.RightVector.Y) * Half.X
		+ math.abs(Frame.UpVector.Y) * Half.Y
		+ math.abs(Frame.LookVector.Y) * Half.Z

	return Vector3.new(Frame.Position.X, Frame.Position.Y - Reach + Settings.Lift, Frame.Position.Z)
end

--> Whether the stretch of the loop covered this frame passed the mark. Half open at the start so a
--> mark landed on exactly is counted once and not again on the frame after.
local function Crossed(From: number, To: number, Mark: number): boolean
	if From <= To then
		return Mark > From and Mark <= To
	end

	--> The loop came round this frame, so what it covered is its tail and its head together.
	return Mark > From or Mark <= To
end

function FootstepController:_Drop(Model: Model)
	local Entry = self.Entries[Model]

	if not Entry then
		return
	end

	self.Entries[Model] = nil
	Entry.Dust:Destroy()
end

--> Nothing is cached until the rig is whole: a character streams its limbs in a few at a time, and
--> an entry built off half of one would hold the wrong pair of feet for the rest of its life.
function FootstepController:_Track(Model: Model): Entry?
	local Left, Right = FindFeet(Model)

	if not Left or not Right then
		return nil
	end

	local Dust = VfxController:Dust()

	if not Dust then
		return nil
	end

	local Entry: Entry = {
		Left = Left,
		Right = Right,
		Dust = Dust,
		Phase = nil,
		Loop = nil,
	}

	self.Entries[Model] = Entry

	return Entry
end

function FootstepController:_Step(Model: Model, Entry: Entry)
	local Track = WalkTrack(Model)

	--> Dropped rather than kept, so a walk picked up again starts from wherever it starts and not
	--> from a phase measured against the last one.
	if not Track then
		Entry.Phase, Entry.Loop = nil, nil
		return
	end

	local Phase = (Track.TimePosition % Track.Length) / Track.Length
	local Last = if Entry.Loop == Track.Name then Entry.Phase else nil

	Entry.Phase, Entry.Loop = Phase, Track.Name

	if not Last then
		return
	end

	for _, Plant in Settings.Plants[Track.Name] do
		local Foot = if Plant.Right then Entry.Right else Entry.Left

		if Foot.Parent and Crossed(Last, Phase, Plant.Phase) then
			VfxController:Puff(Entry.Dust, Sole(Foot))
		end
	end
end

--> Rebuilt off the live sets each frame rather than off a signal, so nothing else has to know this
--> exists: an employee bought, sold or walked off the map is in or out of the table by itself, and
--> so is a character that just respawned.
function FootstepController:Step()
	local Walking: { [Model]: boolean } = {}
	local Character = Players.LocalPlayer.Character

	if Character then
		Walking[Character] = true
	end

	for _, Employee in EmployeeController.Employees do
		Walking[Employee.Model] = true
	end

	for Model in self.Entries do
		if not Walking[Model] or not Model:IsDescendantOf(workspace) then
			self:_Drop(Model)
		end
	end

	for Model in Walking do
		if not Model:IsDescendantOf(workspace) then
			continue
		end

		local Entry = self.Entries[Model] or self:_Track(Model)

		if Entry then
			self:_Step(Model, Entry)
		end
	end
end

function FootstepController:Start()
	RunService.RenderStepped:Connect(function()
		self:Step()
	end)
end

return FootstepController
