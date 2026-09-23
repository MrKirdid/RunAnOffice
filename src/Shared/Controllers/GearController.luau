local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GearConfigs = require(Shared.Configs.Gears)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client
local ScreenShakeController = require(Shared.Controllers.ScreenShakeController)
local SoundController = require(Shared.Controllers.SoundController)
local TutorialConfigs = require(Shared.Configs.Tutorial)
local TutorialController = require(Shared.Controllers.TutorialController)

--> The gear shop's client side, for the shop screen to sit on: what is owned and equipped is read
--> off the save, and buying or equipping is asked of the server and answered in the bar. A click
--> with a gear out is sent up with where the mouse was; the server decides what happens.

--> the tag GearService puts on every tool it hands out
local GearAttribute = "Gear"

--> what the bar says when a gear will not go in because the backpack is full
local FullText = "All gear slots are full"

local LocalPlayer = Players.LocalPlayer

local GearController = {
	Name = "GearController",

	--> the tools already wired, so one seen in the backpack and again in the hand is wired once
	Wired = {} :: { [Tool]: boolean },
}

function GearController:IsOwned(Key: string): boolean
	return PlayerData.Gears[Key]() == true
end

function GearController:IsEquipped(Key: string): boolean
	return PlayerData.EquippedGears[Key]() == true
end

--> How many are in the backpack, and how many may be.
function GearController:GetSlots(): (number, number)
	local Count = 0

	for Key, On in PlayerData.EquippedGears() do
		if On and self:IsOwned(Key) and GearConfigs.List[Key] then
			Count += 1
		end
	end

	return Count, PlayerData.GearSlots()
end

--> What this gear costs this player right now: nothing for the tutorial's free one on its step.
function GearController:GetPrice(Key: string): number
	local Config = GearConfigs.List[Key]

	if not Config then
		return math.huge
	end

	return if TutorialConfigs.IsFreeGear(PlayerData, Key) then 0 else Config.Price
end

function GearController:CanAfford(Key: string): boolean
	return PlayerData.Cash() >= self:GetPrice(Key)
end

--> Turned down here for the reasons the player can see, so the bar can say why without a round
--> trip; the server checks the same things again and is the one that counts.
function GearController:Buy(Key: string)
	local Config = GearConfigs.List[Key]

	if not Config or self:IsOwned(Key) then
		return
	end

	if not self:CanAfford(Key) then
		SoundController:Play("Error")
		TutorialController:Notify("Not enough cash")
		return
	end

	NetworkingClient.Gears.Buy.Invoke(Key):andThen(function(Bought: boolean)
		SoundController:Play(if Bought then "Purchase" else "Error")

		if Bought then
			ScreenShakeController:Shake(0.6)
			TutorialController:Notify(`Bought {Config.Name}`)
		end
	end)
end

function GearController:Equip(Key: string)
	if not self:IsOwned(Key) or self:IsEquipped(Key) then
		return
	end

	local Count, Slots = self:GetSlots()

	if Count >= Slots then
		SoundController:Play("Error")
		TutorialController:Notify(FullText)
		return
	end

	NetworkingClient.Gears.Equip.Invoke({ Key = Key, On = true }):andThen(function(Done: boolean)
		SoundController:Play(if Done then "Confirm" else "Error")
	end)
end

function GearController:Unequip(Key: string)
	if not self:IsEquipped(Key) then
		return
	end

	NetworkingClient.Gears.Equip.Invoke({ Key = Key, On = false }):andThen(function(Done: boolean)
		SoundController:Play(if Done then "Confirm" else "Error")
	end)
end

--> A click with the tool out. Only the gears that do something on a click are sent; a coil is
--> just carried.
function GearController:_Wire(Tool: Tool)
	local Key = Tool:GetAttribute(GearAttribute)
	local Config = if type(Key) == "string" then GearConfigs.List[Key] else nil

	if not Config or not Config.Cooldown or self.Wired[Tool] then
		return
	end

	self.Wired[Tool] = true

	Tool.Activated:Connect(function()
		local Mouse = LocalPlayer:GetMouse()

		--> the default animate script plays a swing for a StringValue called toolanim dropped into
		--> the tool, and takes it away itself once it has read it
		if Config.Animation then
			local Swing = Instance.new("StringValue")
			Swing.Name = "toolanim"
			Swing.Value = Config.Animation
			Swing.Parent = Tool
		end

		NetworkingClient.Gears.Use.Fire({
			Key = Key :: string,
			Aim = Mouse.Hit.Position,
		})
	end)

	Tool.Destroying:Connect(function()
		self.Wired[Tool] = nil
	end)
end

--> Tools turn up in the backpack and move into the character when drawn; both are watched, and
--> both are new after every respawn.
function GearController:_Watch(Holder: Instance)
	for _, Child in Holder:GetChildren() do
		if Child:IsA("Tool") then
			self:_Wire(Child)
		end
	end

	Holder.ChildAdded:Connect(function(Child: Instance)
		if Child:IsA("Tool") then
			self:_Wire(Child)
		end
	end)
end

function GearController:Init()
	LocalPlayer.ChildAdded:Connect(function(Child: Instance)
		if Child:IsA("Backpack") then
			self:_Watch(Child)
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function(Character: Model)
		self:_Watch(Character)
	end)

	--> something landed on this player: the fling or the freeze is already done, this is the kick
	NetworkingClient.Gears.Hit.On(function(Strength: number)
		ScreenShakeController:Shake(Strength)
	end)

	local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

	if Backpack then
		self:_Watch(Backpack)
	end

	if LocalPlayer.Character then
		self:_Watch(LocalPlayer.Character)
	end
end

return GearController
