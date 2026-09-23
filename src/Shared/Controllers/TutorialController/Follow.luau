local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--> A beam from the player's feet to the thing to walk to, with the texture running along it the
--> way to go. The far end is a part, or an attachment for something that stands off one, like a
--> gift floating over a desk. Built in code off the pack's numbers, so the art is here rather than
--> in the place.

local BeamName = "TutorialBeam"
local BeamTexture = "rbxassetid://6399401493"
local BeamWidth = 2
local BeamColor = Color3.new(1, 1, 1)

--> negative runs the texture from the character towards the target
local TextureSpeed = -2
local TextureLength = 5
local Segments = 500
local LightEmission = 0.5

local GrowTween = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ShrinkTween = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local Follow = {
	Beam = nil :: Beam?,

	--> the end on the target and the end on the character, both destroyed with the beam
	Head = nil :: Attachment?,
	Tail = nil :: Attachment?,
}

local function BuildBeam(): Beam
	local Beam = Instance.new("Beam")
	Beam.Name = BeamName
	Beam.Texture = BeamTexture
	Beam.TextureMode = Enum.TextureMode.Static
	Beam.TextureSpeed = TextureSpeed
	Beam.TextureLength = TextureLength
	Beam.Segments = Segments
	Beam.LightEmission = LightEmission
	Beam.LightInfluence = 0
	Beam.FaceCamera = true
	Beam.Color = ColorSequence.new(BeamColor)
	Beam.Transparency = NumberSequence.new(0)
	Beam.Width0 = 0
	Beam.Width1 = 0

	return Beam
end

function Follow:_Clear()
	if self.Beam then
		self.Beam:Destroy()
		self.Beam = nil
	end

	if self.Head then
		self.Head:Destroy()
		self.Head = nil
	end

	if self.Tail then
		self.Tail:Destroy()
		self.Tail = nil
	end
end

export type Target = BasePart | Attachment

--> Puts the far end on the target: inside a part, or beside an attachment at the same spot.
local function Place(Head: Attachment, To: Target)
	if To:IsA("Attachment") then
		Head.Parent = To.Parent
		Head.WorldPosition = To.WorldPosition
		return
	end

	Head.Parent = To
	Head.Position = Vector3.zero
end

--> Runs the beam from the character to a target and grows it in. A beam already out is replaced.
function Follow:Start(To: Target)
	self:_Clear()

	local Character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
	local Root = Character:WaitForChild("HumanoidRootPart") :: BasePart

	local Head = Instance.new("Attachment")
	Head.Name = BeamName
	Place(Head, To)

	local Tail = Instance.new("Attachment")
	Tail.Name = BeamName
	Tail.Parent = Root

	local Beam = BuildBeam()
	Beam.Attachment0 = Head
	Beam.Attachment1 = Tail
	Beam.Parent = workspace.Terrain

	self.Beam = Beam
	self.Head = Head
	self.Tail = Tail

	TweenService:Create(Beam, GrowTween, { Width0 = BeamWidth, Width1 = BeamWidth }):Play()
end

--> Moves the far end of the beam to another target without growing it in again.
function Follow:Switch(To: Target)
	local Beam, Head = self.Beam, self.Head

	if not Beam or not Head then
		return
	end

	Place(Head, To)
end

--> Shrinks the beam away and takes it down once it has gone.
function Follow:Stop()
	local Beam = self.Beam

	if not Beam then
		self:_Clear()
		return
	end

	local Shrink = TweenService:Create(Beam, ShrinkTween, { Width0 = 0, Width1 = 0 })

	Shrink.Completed:Once(function()
		--> only if nothing started a new one while this was going
		if self.Beam == Beam then
			self:_Clear()
		end
	end)

	Shrink:Play()
end

return Follow
