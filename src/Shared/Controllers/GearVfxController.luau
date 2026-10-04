local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GearConfigs = require(Shared.Configs.Gears)
local GearVfx = require(Shared.VFX.Gears)
local NetworkingClient = require(Shared.Networking.networkingClient)
local NetworkingTypes = require(Shared.Networking.networkingTypes)

--> Draws what the gears do, off the server's word that they did it. The swinger's own bat is drawn
--> the moment they click, so it never waits on a round trip, and the server's echo of it is
--> skipped. Thrown things get a trail on the way: the server owns them, the trail is only looks.

local LocalPlayer = Players.LocalPlayer

--> the folder Server.Gears.Effects throws things into, and what each thrown thing trails
local ThrownFolder = "GearEffects"
local Trails: { [string]: { Color: ColorSequence, Width: number } } = {
	TNT = {
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(120, 110, 100)),
		Width = 0.8,
	},
	GooBall = {
		Color = ColorSequence.new(Color3.fromRGB(150, 255, 110), Color3.fromRGB(60, 170, 40)),
		Width = 1,
	},
}

local TrailLife = 0.25

type Effect = {
	Kind: NetworkingTypes.Gears_Fx,
	At: Vector3,
	Direction: Vector3,
	Size: number,
	By: Player?,
	Target: Player?,
}

local GearVfxController = {
	Name = "GearVfxController",

	--> when each gear is next allowed to swing, by key, so a held mouse button is not a swing drawn
	--> every click while the server ignores all but one
	Ready = {} :: { [string]: number },
}

local function CharacterOf(Player: Player?): Model?
	return if Player then Player.Character else nil
end

--> A click with a bat out, drawn on the spot if the bat is off cooldown here.
function GearVfxController:Swing(Key: string)
	local Config = GearConfigs.List[Key]
	local Character = LocalPlayer.Character

	if not Config or not Config.Swing or not Config.Cooldown or not Character then
		return
	end

	local Now = os.clock()

	if (self.Ready[Key] or 0) > Now then
		return
	end

	self.Ready[Key] = Now + Config.Cooldown

	GearVfx.Swing(Character, Config.Swing)
end

function GearVfxController:Play(Effect: Effect)
	local Kind = Effect.Kind
	local Mine = Effect.By == LocalPlayer

	if Kind == "Swing" then
		local Character = CharacterOf(Effect.By)

		if Character and not Mine then
			GearVfx.Swing(Character, Effect.Size)
		end
	elseif Kind == "Bonk" then
		GearVfx.Bonk(CharacterOf(Effect.Target), Effect.At, Effect.Direction, Effect.Size, Mine)
	elseif Kind == "Blast" then
		local Character = LocalPlayer.Character
		local Root = Character and Character:FindFirstChild("HumanoidRootPart")
		local Near = if Root and Root:IsA("BasePart") then (Root.Position - Effect.At).Magnitude else nil

		GearVfx.Blast(Effect.At, Effect.Size, Near)
	elseif Kind == "Splat" then
		GearVfx.Splat(Effect.At, CharacterOf(Effect.Target))
	elseif Kind == "Snap" then
		GearVfx.Snap(Effect.At, CharacterOf(Effect.Target))
	elseif Kind == "Gulp" then
		local Character = CharacterOf(Effect.Target)

		if Character then
			GearVfx.Gulp(Character)
		end
	elseif Kind == "Cloak" then
		GearVfx.Cloak(Effect.At)
	end
end

--> A trail behind one thrown thing, between two points across it, for as long as it flies.
function GearVfxController:AddTrail(Part: Instance)
	local Look = Trails[Part.Name]

	if not Look or not Part:IsA("BasePart") then
		return
	end

	local Half = Look.Width / 2

	local Top = Instance.new("Attachment")
	Top.Position = Vector3.new(0, Half, 0)
	Top.Parent = Part

	local Bottom = Instance.new("Attachment")
	Bottom.Position = Vector3.new(0, -Half, 0)
	Bottom.Parent = Part

	local Trail = Instance.new("Trail")
	Trail.Attachment0 = Top
	Trail.Attachment1 = Bottom
	Trail.Color = Look.Color
	Trail.Lifetime = TrailLife
	Trail.LightEmission = 0.6
	Trail.FaceCamera = true
	Trail.Transparency = NumberSequence.new(0.2, 1)
	Trail.Parent = Part

	--> once it has stuck where it landed there is nothing left to trail
	Part:GetPropertyChangedSignal("Anchored"):Connect(function()
		Trail.Enabled = not (Part :: BasePart).Anchored
	end)
end

function GearVfxController:WatchThrown(Folder: Instance)
	for _, Child in Folder:GetChildren() do
		self:AddTrail(Child)
	end

	Folder.ChildAdded:Connect(function(Child: Instance)
		self:AddTrail(Child)
	end)
end

function GearVfxController:Init()
	NetworkingClient.Gears.Effect.On(function(Effect: Effect)
		self:Play(Effect)
	end)

	local Folder = workspace:FindFirstChild(ThrownFolder)

	if Folder then
		self:WatchThrown(Folder)
	end

	workspace.ChildAdded:Connect(function(Child: Instance)
		if Child.Name == ThrownFolder then
			self:WatchThrown(Child)
		end
	end)
end

return GearVfxController
