local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--> A 3D arrow over the player's head, turned towards the thing to walk to. Up close it moves over
--> the thing itself and points down at it. The target is asked for every frame rather than given
--> once, so it can be whichever employee is nearest right now.

local ArrowName = "TutorialArrow"
local MeshId = "rbxassetid://79816613185185"

--> The pack ships the arrow as a MeshPart, which cannot be given its mesh at runtime; a part with
--> a mesh on it can. The size the pack drew it at, over the mesh's own size, is the scale.
local MeshSize = Vector3.new(23.219863891601562, 146.7080078125, 72.97065734863281)
local DrawnSize = Vector3.new(1.1039583683013916, 6.975042343139648, 3.4692952632904053)
local MeshScale = DrawnSize / MeshSize

--> How high over the head it floats, how close is close enough to move over the target instead,
--> and how high over the target it sits then.
local OverheadHeight = 3.75
local NearDistance = 12
local NearHeight = 5

--> How fast it crosses from over the head to over the target, per second.
local BlendRate = 4

--> the mesh points along its own Y, so it is turned to point along the look direction and stood on
--> its side; near, it is turned to point straight down
local FacingTurn = CFrame.Angles(0, math.rad(-90), math.rad(90))
local DownTurn = CFrame.Angles(0, math.rad(-90), math.rad(180))

local GrowTween = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ShrinkTween = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BreatheTween = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local FloatTween = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local BreatheScale = 0.9
local FloatDistance = 0.5

export type GetTarget = () -> BasePart?

local Overhead = {
	Arrow = nil :: BasePart?,
	Mesh = nil :: SpecialMesh?,

	--> the two loops, each driving a value the frame step reads
	Scale = nil :: NumberValue?,
	Float = nil :: NumberValue?,
	Breathe = nil :: Tween?,
	Bob = nil :: Tween?,

	--> how far across from over the head to over the target it is right now
	Blend = 0,

	Step = nil :: RBXScriptConnection?,
}

local function BuildArrow(): (BasePart, SpecialMesh)
	local Arrow = Instance.new("Part")
	Arrow.Name = ArrowName
	Arrow.Anchored = true
	Arrow.CanCollide = false
	Arrow.CanQuery = false
	Arrow.CanTouch = false
	Arrow.CastShadow = false
	Arrow.Massless = true
	Arrow.Color = Color3.new(1, 1, 1)
	Arrow.Material = Enum.Material.Plastic
	Arrow.Size = DrawnSize

	local Mesh = Instance.new("SpecialMesh")
	Mesh.MeshType = Enum.MeshType.FileMesh
	Mesh.MeshId = MeshId
	Mesh.Scale = MeshScale
	Mesh.Parent = Arrow

	return Arrow, Mesh
end

function Overhead:_Clear()
	if self.Step then
		self.Step:Disconnect()
		self.Step = nil
	end

	if self.Breathe then
		self.Breathe:Cancel()
		self.Breathe = nil
	end

	if self.Bob then
		self.Bob:Cancel()
		self.Bob = nil
	end

	if self.Scale then
		self.Scale:Destroy()
		self.Scale = nil
	end

	if self.Float then
		self.Float:Destroy()
		self.Float = nil
	end

	if self.Arrow then
		self.Arrow:Destroy()
		self.Arrow = nil
		self.Mesh = nil
	end

	self.Blend = 0
end

--> Puts the arrow up over the character and starts it following GetTarget. With no target it is
--> hidden rather than pointed at nothing, and comes back the frame there is one.
function Overhead:Start(GetTarget: GetTarget)
	self:_Clear()

	local Character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
	local Root = Character:WaitForChild("HumanoidRootPart") :: BasePart

	local Arrow, Mesh = BuildArrow()
	Arrow.CFrame = CFrame.new(Root.Position + Vector3.new(0, OverheadHeight - 1, 0)) * FacingTurn
	Arrow.Parent = workspace

	local Scale = Instance.new("NumberValue")
	Scale.Value = 0

	local Float = Instance.new("NumberValue")
	Float.Value = 0

	self.Arrow = Arrow
	self.Mesh = Mesh
	self.Scale = Scale
	self.Float = Float

	Mesh.Scale = MeshScale * 0

	local Grow = TweenService:Create(Scale, GrowTween, { Value = 1 })

	Grow.Completed:Once(function()
		if self.Scale ~= Scale then
			return
		end

		self.Breathe = TweenService:Create(Scale, BreatheTween, { Value = BreatheScale })
		self.Breathe:Play()
	end)

	Grow:Play()

	self.Bob = TweenService:Create(Float, FloatTween, { Value = FloatDistance })
	self.Bob:Play()

	self.Step = RunService.RenderStepped:Connect(function(Delta: number)
		if not Arrow:IsDescendantOf(workspace) or not Root:IsDescendantOf(workspace) then
			return
		end

		local Target = GetTarget()

		if not Target then
			Arrow.Transparency = 1
			return
		end

		Arrow.Transparency = 0
		Mesh.Scale = MeshScale * Scale.Value

		local Distance = (Root.Position - Target.Position).Magnitude
		local Wanted = if Distance <= NearDistance then 1 else 0

		self.Blend += (Wanted - self.Blend) * math.min(Delta * BlendRate, 1)

		local OverHead = Root.Position + Vector3.new(0, OverheadHeight + Float.Value, 0)
		local OverTarget = Target.Position + Vector3.new(0, NearHeight + Float.Value, 0)

		local Far = CFrame.lookAt(OverHead, Target.Position) * FacingTurn
		local Near = CFrame.new(OverTarget) * DownTurn

		Arrow.CFrame = Far:Lerp(Near, self.Blend)
	end)
end

--> Shrinks the arrow away and takes it down once it has gone.
function Overhead:Stop()
	local Scale, Arrow = self.Scale, self.Arrow

	if not Scale or not Arrow then
		self:_Clear()
		return
	end

	if self.Breathe then
		self.Breathe:Cancel()
		self.Breathe = nil
	end

	local Shrink = TweenService:Create(Scale, ShrinkTween, { Value = 0 })

	Shrink.Completed:Once(function()
		if self.Arrow == Arrow then
			self:_Clear()
		end
	end)

	Shrink:Play()
end

return Overhead
