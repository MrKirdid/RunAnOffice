local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local SoundConfigs = require(Shared.Configs.Sounds)

--> Clips in the pack top out near a second; anything still alive after this never ended on its own.
local Lifetime = 10

--> Its own stream rather than math.random: pitch drift is cosmetic and has no business pulling on
--> the sequence anything else in the game rolls from.
local Drift = Random.new()

type Effect = SoundConfigs.Effect

local SoundController = {
	Container = nil :: Folder?,

	--> One warning per name, or a click bound to a missing effect spams the output every frame.
	Warned = {} :: { [string]: boolean },
}

--> The config is the source of truth: a Sound is created for anything missing and every existing
--> one is rewritten from the entry, so retuning a volume never means touching the place file.
function SoundController:Build(): Folder
	local Effects = Assets:WaitForChild("SFX")
	local Container = Effects:FindFirstChild(SoundConfigs.Folder)

	if not Container then
		Container = Instance.new("Folder")
		Container.Name = SoundConfigs.Folder
		Container.Parent = Effects
	end

	for Name, Effect in SoundConfigs.Effects do
		local Sound = Container:FindFirstChild(Name) :: Sound?

		if not Sound then
			Sound = Instance.new("Sound")
			Sound.Name = Name
			Sound.Parent = Container
		end

		Sound.SoundId = if Effect.Id ~= "" then "rbxassetid://" .. Effect.Id else ""
		Sound.Volume = if Effect.Volume then Effect.Volume else SoundConfigs.Volume
		Sound.PlaybackSpeed = if Effect.Speed then Effect.Speed else 1
		Sound.Looped = Effect.Loop == true
	end

	return Container :: Folder
end

--> A detached copy, so overlapping clicks stack instead of cutting each other off. Left unparented
--> and not yet playing: where it is heard from is the caller's business.
function SoundController:_Prepare(Name: string, Speed: number?): Sound?
	local Container = self.Container

	if not Container then
		return nil
	end

	local Template = Container:FindFirstChild(Name) :: Sound?

	if not Template then
		self:Complain(Name, `no effect named {Name}`)
		return nil
	end

	if Template.SoundId == "" then
		self:Complain(Name, `{Name} has no id yet`)
		return nil
	end

	local Effect = SoundConfigs.Effects[Name] :: Effect?
	local Spread = Effect and Effect.Spread
	local Base = if Speed then Speed else Template.PlaybackSpeed

	local Sound = Template:Clone()
	Sound.PlaybackSpeed = if Spread and Spread > 0 then Base * (1 + Drift:NextNumber(-Spread, Spread)) else Base

	return Sound
end

--> Flat, in the middle of the player's head: the whole UI, and anything the player did themselves.
function SoundController:Play(Name: string, Speed: number?): Sound?
	local Sound = self:_Prepare(Name, Speed)

	if not Sound then
		return nil
	end

	Sound.Parent = SoundService
	Sound:Play()

	Debris:AddItem(Sound, Lifetime)

	return Sound
end

--> Linear rather than the default inverse curve: inverse never quite reaches zero, so an effect
--> fired every few seconds across the map stays faintly audible everywhere. Linear is silent past
--> Range, which is what Range means.
function SoundController:_ApplyRange(Sound: Sound, Name: string)
	local Effect = SoundConfigs.Effects[Name] :: Effect?
	local Range = Effect and Effect.Range

	if not Range then
		return
	end

	Sound.RollOffMode = Enum.RollOffMode.Linear
	Sound.RollOffMinDistance = math.min(Sound.RollOffMinDistance, Range)
	Sound.RollOffMaxDistance = Range
end

--> Out in the world, for something that happened somewhere.
function SoundController:PlayAt(Name: string, Position: Vector3, Speed: number?): Sound?
	local Sound = self:_Prepare(Name, Speed)

	if not Sound then
		return nil
	end

	self:_ApplyRange(Sound, Name)

	--> An Attachment rather than a part: it needs no size, no physics and no collision groups, and
	--> Terrain is the one BasePart every place already has to hang it off.
	local Point = Instance.new("Attachment")
	Point.Name = `SFX_{Name}`
	Point.Parent = workspace.Terrain
	Point.WorldPosition = Position

	Sound.Parent = Point
	Sound:Play()

	Debris:AddItem(Point, Lifetime)

	return Sound
end

--> Dropped into the clip at a random point rather than started at the top. A loop hung off twenty
--> desks on the same frame is twenty copies in lockstep, which is heard as one loud source instead
--> of a room full of them. TimeLength reads 0 until the asset is in, so a clip that is not there
--> yet is staggered on the way in instead.
function SoundController:_Stagger(Sound: Sound)
	if Sound.TimeLength > 0 then
		Sound.TimePosition = Drift:NextNumber(0, Sound.TimeLength)
		return
	end

	Sound.Loaded:Once(function()
		Sound.TimePosition = Drift:NextNumber(0, Sound.TimeLength)
	end)
end

--> A loop that lives on a part, for somewhere that makes a noise rather than something that
--> happened. There is no Debris on it and nothing here holds it: it ends when the part it was hung
--> off is destroyed, so an employee taken off a desk takes its typing with it.
function SoundController:Attach(Name: string, Adornee: BasePart, Speed: number?): Sound?
	local Sound = self:_Prepare(Name, Speed)

	if not Sound then
		return nil
	end

	self:_ApplyRange(Sound, Name)

	Sound.Looped = true
	Sound.Parent = Adornee

	self:_Stagger(Sound)

	Sound:Play()

	return Sound
end

function SoundController:Complain(Name: string, Problem: string)
	if self.Warned[Name] then
		return
	end

	self.Warned[Name] = true

	warn(`[Sound] {Problem}`)
end

function SoundController:Init()
	self.Container = self:Build()
end

return SoundController
