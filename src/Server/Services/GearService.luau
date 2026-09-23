local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared

local Effects = require(ServerScriptService.Server.Gears.Effects)
local GearConfigs = require(Shared.Configs.Gears)
local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local StatusService = require(ServerScriptService.Server.Services.StatusService)
local TutorialConfigs = require(Shared.Configs.Tutorial)

--> The gear shop's server side: what is bought is written into the save, and what is equipped is
--> cloned into the backpack, one Tool per equipped gear up to the save's slots, again after every
--> respawn. A use is checked here, owned and in hand and off cooldown, and then handed to
--> Server.Gears.Effects. The client asks and is told yes or no; nothing it says about cash,
--> ownership or the tool in its hands is believed.

--> Every tool handed out carries this, so the ones taken away on a change are the ones this gave
--> and not something else the player is holding.
local GearAttribute = "Gear"

--> the name of the speed modifier a coil in the hand holds on the player
local PassiveName = "Gear"

--> Scales every part of a tool about its handle, welds and all, and the grip offset with it, so
--> the hand stays on the same spot of a bat that has shrunk. Done through a Model because a Tool
--> has no ScaleTo of its own.
local function ScaleTool(Tool: Tool, Scale: number)
	local Handle = Tool:FindFirstChild("Handle")

	if not Handle or not Handle:IsA("BasePart") then
		return
	end

	local Holder = Instance.new("Model")

	for _, Child in Tool:GetChildren() do
		if Child:IsA("BasePart") then
			Child.Parent = Holder
		end
	end

	Holder.PrimaryPart = Handle
	Holder:ScaleTo(Scale)

	for _, Child in Holder:GetChildren() do
		Child.Parent = Tool
	end

	Holder:Destroy()

	Tool.Grip = CFrame.new(Tool.Grip.Position * Scale) * Tool.Grip.Rotation
end

local GearService = {
	Name = "GearService",

	--> when each gear may next be used, per player
	Cooldowns = {} :: { [Player]: { [string]: number } },

	--> stand-ins built for keys with no Tool in the place, made once each
	Placeholders = {} :: { [string]: Tool },
}

--> A Tool with a plain handle in the gear's colour, for a key the place has no model for yet, so
--> the whole shop plays before the models are in.
function GearService:BuildPlaceholder(Key: string): Tool
	local Existing = self.Placeholders[Key]

	if Existing then
		return Existing
	end

	local Config = GearConfigs.List[Key]

	local Tool = Instance.new("Tool")
	Tool.Name = Config.Name
	Tool.RequiresHandle = true
	Tool.CanBeDropped = false

	local Handle = Instance.new("Part")
	Handle.Name = "Handle"
	Handle.Size = Config.Placeholder.Size
	Handle.Color = Config.Placeholder.Color
	Handle.Shape = Config.Placeholder.Shape or Enum.PartType.Block
	Handle.Material = Config.Placeholder.Material or Enum.Material.SmoothPlastic
	Handle.CanCollide = false
	Handle.Massless = true
	Handle.Parent = Tool

	self.Placeholders[Key] = Tool

	return Tool
end

--> The Tool for a key, out of the folder the config names, or the stand-in for one that is not
--> in the place yet, or for one the config says is better plain.
function GearService:GetTool(Key: string): Tool
	if GearConfigs.List[Key].Plain then
		return self:BuildPlaceholder(Key)
	end

	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local Folder = Assets and Assets:FindFirstChild(GearConfigs.Folder)
	local Tool = Folder and Folder:FindFirstChild(Key)

	if Tool and Tool:IsA("Tool") then
		return Tool
	end

	return self:BuildPlaceholder(Key)
end

function GearService:Owns(Data: any, Key: string): boolean
	return Data.Gears[Key]() == true
end

function GearService:IsEquipped(Data: any, Key: string): boolean
	return Data.EquippedGears[Key]() == true
end

--> How many are in the backpack, counting only ones the save still owns and the config still has.
function GearService:CountEquipped(Data: any): number
	local Count = 0

	for Key, On in Data.EquippedGears() do
		if On and self:Owns(Data, Key) and GearConfigs.List[Key] then
			Count += 1
		end
	end

	return Count
end

--> The gear the player is holding right now, by the tag on the tool in the character.
function GearService:GetHeld(Player: Player): string?
	local Character = Player.Character

	if not Character then
		return nil
	end

	for _, Child in Character:GetChildren() do
		local Key = Child:IsA("Tool") and Child:GetAttribute(GearAttribute)

		if type(Key) == "string" then
			return Key
		end
	end

	return nil
end

--> Takes back whatever this handed out, from the backpack and from the hands.
function GearService:Strip(Player: Player)
	local Backpack = Player:FindFirstChildOfClass("Backpack")
	local Character = Player.Character

	for _, Holder in { Backpack, Character } do
		if not Holder then
			continue
		end

		for _, Child in Holder:GetChildren() do
			if Child:IsA("Tool") and Child:GetAttribute(GearAttribute) ~= nil then
				Child:Destroy()
			end
		end
	end
end

--> Puts every equipped gear in the backpack, and nothing else of this in it. Run on join, on
--> every respawn, and whenever what is equipped changes.
function GearService:Apply(Player: Player)
	local Data = PlayerData[Player]

	if not Data then
		return
	end

	self:Strip(Player)

	local Backpack = Player:FindFirstChildOfClass("Backpack")

	if not Backpack then
		return
	end

	for Key, On in Data.EquippedGears() do
		if not On or not GearConfigs.List[Key] or not self:Owns(Data, Key) then
			continue
		end

		local Config = GearConfigs.List[Key]
		local Copy = self:GetTool(Key):Clone()
		Copy:SetAttribute(GearAttribute, Key)

		--> the Tools in the place keep whatever they were saved with, which is droppable by default
		Copy.CanBeDropped = false

		--> the config has the last word on how it sits in the hand and how big it is
		if Config.Grip then
			Copy.Grip = Config.Grip
		end

		if Config.Scale then
			ScaleTool(Copy, Config.Scale)
		end

		Copy.Parent = Backpack
	end
end

--> A coil is faster only while it is out: the tool moving into the character is it being drawn,
--> and moving out is it being put away.
function GearService:_WatchCharacter(Player: Player, Character: Model)
	Character.ChildAdded:Connect(function(Child: Instance)
		local Key = Child:IsA("Tool") and Child:GetAttribute(GearAttribute)
		local Config = if type(Key) == "string" then GearConfigs.List[Key] else nil

		if Config and Config.Speed then
			StatusService:Set(Player, PassiveName, 1 + Config.Speed)
		end
	end)

	Character.ChildRemoved:Connect(function(Child: Instance)
		if Child:IsA("Tool") and Child:GetAttribute(GearAttribute) ~= nil then
			StatusService:Clear(Player, PassiveName)
		end
	end)
end

--> Hands a gear over for nothing and writes it down. No price and no cash check, so the console
--> can hand one out for testing; Buy is the paid path in front of it.
function GearService:Grant(Player: Player, Key: string): boolean
	local Data = PlayerData[Player]

	if not Data or not GearConfigs.List[Key] or self:Owns(Data, Key) then
		return false
	end

	Data.Gears[Key](true)

	return true
end

function GearService:Buy(Player: Player, Key: string): boolean
	local Data = PlayerData[Player]
	local Config = GearConfigs.List[Key]

	if not Data or not Config or self:Owns(Data, Key) then
		return false
	end

	local Free = TutorialConfigs.IsFreeGear(Data, Key)
	local Price = if Free then 0 else Config.Price

	if Data.Cash() < Price then
		return false
	end

	--> every reason to turn this down is out of the way, so the charge lands with the grant
	Data.Cash(function(Current: number)
		return math.max(Current - Price, 0)
	end)

	if not self:Grant(Player, Key) then
		return false
	end

	--> the tutorial's gear goes straight into the backpack, so it is in hand the moment it is taken
	if Free then
		self:Equip(Player, Key, true)
	end

	return true
end

--> Puts an owned gear in the backpack, while there is a slot for it, or takes one out again.
function GearService:Equip(Player: Player, Key: string, On: boolean): boolean
	local Data = PlayerData[Player]

	if not Data or not GearConfigs.List[Key] or not self:Owns(Data, Key) then
		return false
	end

	if On and not self:IsEquipped(Data, Key) and self:CountEquipped(Data) >= Data.GearSlots() then
		return false
	end

	Data.EquippedGears[Key](if On then true else nil)
	self:Apply(Player)

	return true
end

--> A use of the gear in hand. Everything the client said is checked against what the server can
--> see: the save for ownership, the character for the tool, its own clock for the cooldown.
function GearService:Use(Player: Player, Key: string, Aim: Vector3?)
	local Data = PlayerData[Player]
	local Config = GearConfigs.List[Key]
	local Effect = Effects[Key]

	if not Data or not Config or not Effect or not Config.Cooldown then
		return
	end

	if not self:Owns(Data, Key) or self:GetHeld(Player) ~= Key then
		return
	end

	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	if not Character or not Root or not Root:IsA("BasePart") then
		return
	end

	local Cooldowns = self.Cooldowns[Player]

	if not Cooldowns then
		Cooldowns = {}
		self.Cooldowns[Player] = Cooldowns
	end

	local Now = os.clock()

	if (Cooldowns[Key] or 0) > Now then
		return
	end

	Cooldowns[Key] = Now + Config.Cooldown

	Effect({
		Player = Player,
		Character = Character,
		Root = Root,
		Aim = Aim,
	})
end

function GearService:_HandlePlayer(Player: Player)
	--> the backpack is new every respawn, and comes back empty
	Player.CharacterAdded:Connect(function(Character: Model)
		self:_WatchCharacter(Player, Character)
		self:Apply(Player)
	end)

	if Player.Character then
		self:_WatchCharacter(Player, Player.Character)
	end

	task.spawn(function()
		PlayerData.Service:waitForData(Player)

		if not Player.Parent then
			return
		end

		self:Apply(Player)
	end)
end

function GearService:Init()
	NetworkingServer.Gears.Buy.On(function(Player: Player, Key: string): boolean
		return self:Buy(Player, Key)
	end)

	NetworkingServer.Gears.Equip.On(function(Player: Player, Request: { Key: string, On: boolean }): boolean
		return self:Equip(Player, Request.Key, Request.On)
	end)

	NetworkingServer.Gears.Use.On(function(Player: Player, Use: { Key: string, Aim: Vector3? })
		self:Use(Player, Use.Key, Use.Aim)
	end)

	for _, Player in Players:GetPlayers() do
		self:_HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:_HandlePlayer(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self.Cooldowns[Player] = nil
	end)
end

return GearService
