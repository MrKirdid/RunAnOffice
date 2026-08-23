local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Assets = ReplicatedStorage:WaitForChild("Assets")

local TemplateName = "PlayerDisplay"
local RateAttribute = "MoneyPerSecond"
local HeadName = "Head"

--> Long enough to cover a slow character load, short enough that a character taken away mid-spawn
--> gives up rather than holding a thread forever.
local HeadTimeout = 10

local PlayerDisplayController = {
	Displays = {} :: { [Player]: BillboardGui },
}

local function GetTemplate(): BillboardGui
	return Assets:WaitForChild("UI"):WaitForChild(TemplateName) :: BillboardGui
end

local function FormatRate(Rate: any): string
	return `${if type(Rate) == "number" then Rate else 0}/s`
end

function PlayerDisplayController:Refresh(Player: Player)
	local Display = self.Displays[Player]

	if not Display or not Display.Parent then
		return
	end

	Display.Frame.MoneyPerSecond.Text = FormatRate(Player:GetAttribute(RateAttribute))
end

function PlayerDisplayController:Remove(Player: Player)
	local Display = self.Displays[Player]

	if Display then
		Display:Destroy()
	end

	self.Displays[Player] = nil
end

function PlayerDisplayController:Attach(Player: Player, Character: Model)
	local Head = Character:WaitForChild(HeadName, HeadTimeout)

	--> Respawning while the head was still loading leaves this thread holding the old character,
	--> and parenting to it would hang the card on a corpse.
	if not Head or Player.Character ~= Character then
		return
	end

	self:Remove(Player)

	local Display = GetTemplate():Clone()
	Display.Frame.PlayerName.Text = Player.Name
	Display.Parent = Head

	self.Displays[Player] = Display

	self:Refresh(Player)
end

function PlayerDisplayController:Watch(Player: Player)
	Player:GetAttributeChangedSignal(RateAttribute):Connect(function()
		self:Refresh(Player)
	end)

	Player.CharacterAdded:Connect(function(Character: Model)
		task.spawn(function()
			self:Attach(Player, Character)
		end)
	end)

	if Player.Character then
		task.spawn(function()
			self:Attach(Player, Player.Character :: Model)
		end)
	end
end

function PlayerDisplayController:Start()
	for _, Player in Players:GetPlayers() do
		self:Watch(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:Watch(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		self:Remove(Player)
	end)
end

return PlayerDisplayController
