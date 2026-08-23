local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local SoundConfigs = require(Shared.Configs.Sounds)

--> Clips in the pack top out near a second; anything still alive after this never ended on its own.
local Lifetime = 10

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
	end

	return Container :: Folder
end

--> Plays a detached copy so overlapping clicks stack instead of cutting each other off.
function SoundController:Play(Name: string, Speed: number?): Sound?
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

	local Sound = Template:Clone()
	Sound.PlaybackSpeed = if Speed then Speed else Template.PlaybackSpeed
	Sound.Parent = SoundService
	Sound:Play()

	Debris:AddItem(Sound, Lifetime)

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
