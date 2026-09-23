local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local VfxConfigs = require(Shared.Configs.Vfx)

local Templates = Assets:WaitForChild("VFX"):WaitForChild(VfxConfigs.Folder)

local AuraName = "Aura"
local DustName = "WalkDust"

--> On top of the longest a particle from the burst can live, so nothing is torn down while the last
--> of it is still on screen.
local BurstGrace = 1

--> What every aura is measured against, worked out once rather than per part.
local ReferenceLength = VfxConfigs.Reference.Magnitude

type Footsteps = typeof(VfxConfigs.Footsteps)

local VfxController = {
	--> One warning per effect, or a name that is not in the folder warns every frame something
	--> tries to play it.
	Warned = {} :: { [string]: boolean },
}

local function ScaleSequence(Sequence: NumberSequence, Scale: number): NumberSequence
	local Points = {}

	for _, Point in Sequence.Keypoints do
		table.insert(Points, NumberSequenceKeypoint.new(Point.Time, Point.Value * Scale, Point.Envelope * Scale))
	end

	return NumberSequence.new(Points)
end

local function ScaleRange(Range: NumberRange, Scale: number): NumberRange
	return NumberRange.new(Range.Min * Scale, Range.Max * Scale)
end

--> Nothing an effect is cloned onto has any business colliding, being clicked through or casting a
--> shadow. The templates ship this way; this is what keeps a retouched one from getting it wrong.
local function Inert(Part: BasePart)
	Part.Transparency = 1
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.CastShadow = false
	Part.Massless = true
end

function VfxController:_Template(Name: string): BasePart?
	local Template = Templates:FindFirstChild(Name)

	if Template and Template:IsA("BasePart") then
		return Template
	end

	if not self.Warned[Name] then
		self.Warned[Name] = true
		warn(`[Vfx] there is no effect called {Name} under {Templates:GetFullName()}`)
	end

	return nil
end

--> An aura is the template resized to the item and stood inside it. Every emitter on these fills
--> its parent's volume, so resizing the box is the whole of the fitting: give it the item's own
--> bounding box and the art wraps whatever it is put on, without a number written down per part.
--> The particles are resized with it, and the rate along with them, or a big item wears the same
--> handful of small sparks a small one does.
function VfxController:Aura(Model: Model, Tier: string): BasePart?
	local Entry = VfxConfigs.Auras[Tier]

	if not Entry then
		return nil
	end

	local Template = self:_Template(Entry.Effect)

	if not Template then
		return nil
	end

	--> Read before the aura goes in, though it would not matter: the box is the box, so an aura
	--> exactly the size of it never grows the model it was measured from.
	local BoxCFrame, BoxSize = Model:GetBoundingBox()
	local Host = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true)

	if not Host then
		return nil
	end

	local Existing = Model:FindFirstChild(AuraName)

	if Existing then
		Existing:Destroy()
	end

	local Scale = math.clamp(BoxSize.Magnitude / ReferenceLength, VfxConfigs.MinScale, VfxConfigs.MaxScale)

	--> Only the particles are boosted, not the rate and not the speed: art that does not read is
	--> art that is too small, and answering that with six times as many of the same invisible specks
	--> would cost the frame budget without ever showing up.
	local Boost = Entry.Boost or 1

	local Aura = Template:Clone()
	Aura.Name = AuraName
	Aura.Size = BoxSize
	Aura.CFrame = BoxCFrame

	--> Held by the weld rather than by being anchored, so an item picked up and carried takes its
	--> aura with it instead of leaving it standing on the desk.
	Aura.Anchored = false
	Inert(Aura)

	for _, Emitter in Aura:GetDescendants() do
		if not Emitter:IsA("ParticleEmitter") then
			continue
		end

		Emitter.Size = ScaleSequence(Emitter.Size, Scale * Boost)
		Emitter.Speed = ScaleRange(Emitter.Speed, Scale)
		Emitter.Acceleration *= Scale
		Emitter.Rate = math.min(Emitter.Rate * Scale ^ VfxConfigs.RateExponent, VfxConfigs.RateCeiling)
	end

	local Joint = Instance.new("WeldConstraint")
	Joint.Part0 = Host
	Joint.Part1 = Aura

	--> Parented to the aura and not to the host, so taking the aura off takes the weld with it.
	Joint.Parent = Aura

	Aura.Parent = Model

	return Aura
end

--> A one shot: the template stood where the thing happened, emptied once and thrown away. These
--> ship with their emitters switched off, which is what they were drawn for.
function VfxController:Burst(Name: string, Position: Vector3)
	local Template = self:_Template(Name)

	if not Template then
		return
	end

	local Entry = VfxConfigs.Bursts[Name]
	local Count = if Entry then Entry.Count else 1
	local Tint = Entry and Entry.Tint

	local Burst = Template:Clone()
	Burst.CFrame = CFrame.new(Position)
	Burst.Anchored = true
	Inert(Burst)
	Burst.Parent = workspace

	local Longest = 0

	for _, Emitter in Burst:GetDescendants() do
		if not Emitter:IsA("ParticleEmitter") then
			continue
		end

		--> Flat, because the art's own shading is what should be carrying the colour. A gradient
		--> written here would be a second thing tinting it on top of the texture.
		if Tint then
			Emitter.Color = ColorSequence.new(Tint)
		end

		Emitter:Emit(Count)
		Longest = math.max(Longest, Emitter.Lifetime.Max)
	end

	Debris:AddItem(Burst, Longest + BurstGrace)
end

--> One of these per rig on its feet, built once and moved rather than cloned per step: a footfall
--> twice a second per employee is a lot of instances to make and throw away, and a particle is left
--> where it was born rather than dragged along by the emitter, so moving one is free.
function VfxController:Dust(): BasePart?
	local Settings: Footsteps = VfxConfigs.Footsteps
	local Template = self:_Template(Settings.Effect)

	if not Template then
		return nil
	end

	local Dust = Template:Clone()
	Dust.Name = DustName
	Dust.Size = Settings.Size
	Dust.Anchored = true
	Inert(Dust)

	--> Off, or the slab throws dust on its own wherever it was last put down.
	for _, Emitter in Dust:GetDescendants() do
		if Emitter:IsA("ParticleEmitter") then
			Emitter.Enabled = false
		end
	end

	Dust.Parent = workspace

	return Dust
end

function VfxController:Puff(Dust: BasePart, Position: Vector3)
	local Settings: Footsteps = VfxConfigs.Footsteps

	Dust.CFrame = CFrame.new(Position)

	for _, Emitter in Dust:GetDescendants() do
		if Emitter:IsA("ParticleEmitter") then
			Emitter:Emit(Settings.Emit)
		end
	end
end

return VfxController
