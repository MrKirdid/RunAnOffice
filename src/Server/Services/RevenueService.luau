local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared

local PlayerData = require(Shared.PlayerData).server
local Revenue = require(Shared.Utilities.Revenue)
local Store = require(Shared.Utilities.Store)

local Interval = 1
local DebugFolderName = "Cash"

--> Published on the Player rather than sent over the wire. Attributes replicate to everyone on
--> their own, which is what lets a client put a number on somebody else's card.
local RateAttribute = "MoneyPerSecond"

local Readouts: { [Player]: NumberValue } = {}
local DebugFolder: Folder? = nil

local RevenueService = {}

local function GetDebugFolder(): Folder
	if DebugFolder and DebugFolder.Parent then
		return DebugFolder
	end

	local Existing = Workspace:FindFirstChild(DebugFolderName)

	if Existing and Existing:IsA("Folder") then
		DebugFolder = Existing
		return Existing
	end

	local Folder = Instance.new("Folder")
	Folder.Name = DebugFolderName
	Folder.Parent = Workspace

	DebugFolder = Folder

	return Folder
end

local function UpdateReadout(Player: Player, Cash: number)
	local Readout = Readouts[Player]

	if not Readout or not Readout.Parent then
		Readout = Instance.new("NumberValue")
		Readout.Parent = GetDebugFolder()

		Readouts[Player] = Readout
	end

	Readout.Value = Cash
	Readout.Name = `{Player.Name}: {Cash}`
end

local function ClearReadout(Player: Player)
	local Readout = Readouts[Player]

	if Readout then
		Readout:Destroy()
	end

	Readouts[Player] = nil
end

--> Cash per second this player's plot is currently making, for anything that wants to show it.
function RevenueService:GetRate(Player: Player): number
	local Data = PlayerData[Player]

	return if Data then Revenue.PlotRate(Data) * Store.IncomeMultiplier(Data, Player) else 0
end

--> The same rate without the friends boost: what the plot makes with nobody else around, which is
--> what it was making while the player was away.
function RevenueService:GetSoloRate(Data: any): number
	return Revenue.PlotRate(Data) * Data.Multipliers.Cash() * Store.CashMultiplier(Data)
end

function RevenueService:Pay()
	for _, Player in Players:GetPlayers() do
		local Data = PlayerData[Player]

		if not Data then
			continue
		end

		--> Floored, never rounded up, and no fraction carried over to the next tick: whatever is
		--> under a whole dollar is dropped. The cheapest desk pays 22 a second, so nothing that
		--> earns at all ever floors to nothing.
		--> The tree's multiplier is what the cash branch raises, 1 until one is bought, and what
		--> the shop sold -- the ladder's rung, VIP -- and the friends here are multiplied on top.
		local Amount = math.floor(Revenue.PlotRate(Data) * Store.IncomeMultiplier(Data, Player))

		Player:SetAttribute(RateAttribute, Amount)

		if Amount > 0 then
			Data.Cash(function(Current: number)
				return Current + Amount
			end)

			Data.TotalCashEarned(function(Current: number)
				return Current + Amount
			end)
		end

		UpdateReadout(Player, Data.Cash())
	end
end

function RevenueService:Start()
	Players.PlayerRemoving:Connect(ClearReadout)

	--> Stamped on the way in so a card built before the first tick reads $0/s rather than blank.
	Players.PlayerAdded:Connect(function(Player: Player)
		Player:SetAttribute(RateAttribute, 0)
	end)

	for _, Player in Players:GetPlayers() do
		Player:SetAttribute(RateAttribute, 0)
	end

	task.spawn(function()
		while true do
			task.wait(Interval)

			self:Pay()
		end
	end)
end

return RevenueService
