local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared

local NameList = require(Shared.Configs.NameList)
local DeskData = require(Shared.Utilities.DeskData)
local DeskPurchase = require(Shared.Utilities.DeskPurchase)
local EmployeeService = require(script.Parent.EmployeeService)
local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local PlotService = require(script.Parent.PlotService)
local RevenueService = require(script.Parent.RevenueService)
local ServerLuckService = require(script.Parent.ServerLuckService)
local Store = require(Shared.Utilities.Store)

--> Everything Robux buys lands here. Roblox calls ProcessReceipt for a product and fires
--> PromptGamePassPurchaseFinished for a pass; both end in Grant, keyed by the entry in
--> Configs.Products. Passes are also asked about at join, so a pass bought on the website or
--> refunded shows up without being pressed in the shop.
--> A receipt is remembered by its PurchaseId in the save, so the same one sent twice -- which
--> Roblox does whenever it is unsure the first went through -- is granted once and answered
--> twice. Nothing is answered PurchaseGranted until the grant has been written into the data.

--> What the player walks at, and with Sprint Shoes.
local BaseWalkSpeed = 16

--> A status on the player, slowed by goo or sped up by a coil, multiplies the whole thing. Written
--> by StatusService as an attribute, so nothing here has to know what did it.
local SpeedAttribute = "SpeedFactor"
local SprintMultiplier = 2.5

--> Everyone walks this much faster than the default out of the box, before the tree or the pass:
--> the plot is wide and the street is a walk from it, and the stock speed made both a trudge.
local StockMultiplier = 1.7

--> VIP's welcome: a day of income at the rate the plot makes when it is bought, and one pad.
local VipBonusHours = 24
local VipBonusKey = "VipBonus"

--> The pack rule: a set fills a desk with nothing on it, and when there are none the next desk
--> is bought for the player, so "4 Space desks" is four desks whatever the plot looked like.
local Components = { "Computer", "Keyboard", "Monitor" }

local NameRandom = Random.new()

type Entry = Store.Entry

local MonetizationService = {}

local function PickName(): string
	return NameList[NameRandom:NextInteger(1, #NameList)]
end

local function Tag(Player: Player, Text: string)
	Player:SetAttribute("Tag", Text)
end

--> Applied at grant and again every respawn, since a new character walks at the default.
local function ApplyWalkSpeed(Player: Player, Data: any)
	local Character = Player.Character
	local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

	if not Humanoid then
		return
	end

	--> the tree's multiplier under the pass, so Sprint Shoes are still 2.5x whatever was bought
	local Base = BaseWalkSpeed * StockMultiplier * Data.Multipliers.WalkSpeed()

	local Factor = Player:GetAttribute(SpeedAttribute)
	local Status = if type(Factor) == "number" then Factor else 1

	Humanoid.WalkSpeed = (if Store.Owns(Data, "Sprint") then Base * SprintMultiplier else Base) * Status
end

--> A desk that holds no parts at all, lowest first, or nil.
local function FindBareDesk(Data: any): (number?, number?)
	for _, Floor in DeskData.GetFloors(Data) do
		for _, Slot in DeskData.GetSlots(Data, Floor) do
			local Desk = DeskData.Get(Data, Floor, Slot)
			local Record = Desk and Desk()

			if type(Record) ~= "table" then
				continue
			end

			local Bare = true

			for _, Component in Components do
				if Record[Component] ~= nil then
					Bare = false
					break
				end
			end

			if Bare then
				return Floor, Slot
			end
		end
	end

	return nil, nil
end

local function Furnish(Data: any, Floor: number, Slot: number, Variant: string)
	local Desk = DeskData.Get(Data, Floor, Slot)
	local Record = if Desk then table.clone(Desk()) else {}

	for _, Component in Components do
		Record[Component] = Variant
	end

	if Desk then
		Desk(Record)
		return
	end

	DeskData.Unlock(Data, Floor).Desks[Slot](Record)
end

--> How many sets actually landed. Fewer than asked means the plot is full to the top floor.
function MonetizationService:GrantDesks(Player: Player, Data: any, Variant: string, Sets: number): number
	local Plot = PlotService:GetPlot(Player)
	local Landed = 0

	for _ = 1, Sets do
		local Floor, Slot = FindBareDesk(Data)

		if not Floor or not Slot then
			local Next = DeskPurchase.Next(Data, Plot)

			if not Next then
				break
			end

			Floor, Slot = Next.Floor, Next.Slot
		end

		Furnish(Data, Floor :: number, Slot :: number, Variant)
		Landed += 1
	end

	return Landed
end

function MonetizationService:GrantEmployees(Data: any, Type: string, Count: number): number
	local Seated = 0

	for _ = 1, Count do
		local Floor, Slot = DeskData.GetFreeSeat(Data)

		if not Floor or not Slot then
			break
		end

		if EmployeeService:SeatAt(Data, Floor, Slot, PickName(), Type) then
			Seated += 1
		end
	end

	return Seated
end

function MonetizationService:GrantPack(Player: Player, Data: any, Entry: Entry): boolean
	local Contents: { Store.DeskSet } = Entry.Contents or {}

	for _, Set in Contents do
		self:GrantDesks(Player, Data, Set.Variant, Set.Sets)
	end

	if Entry.Employee and Entry.Employees then
		self:GrantEmployees(Data, Entry.Employee, Entry.Employees)
	end

	--> the cash printed in the pack's third box
	local Bonus = Entry.Bonus

	if Bonus and Bonus > 0 then
		Data.Cash(function(Current: number)
			return Current + Bonus
		end)
	end

	return true
end

function MonetizationService:GrantSkip(Player: Player, Data: any, Hours: number): boolean
	local Amount = math.floor(RevenueService:GetRate(Player) * Hours * 3600)

	Data.Cash(function(Current: number)
		return Current + Amount
	end)

	return true
end

function MonetizationService:GrantPad(Data: any): boolean
	Data.RerollPads(function(Current: number)
		return math.min(Current + 1, Store.MaxPads)
	end)

	return true
end

--> The rung on offer is always the next one, so whichever rung's id came through, it is the
--> next rung that is granted: that is the one the button was showing and the one that was paid
--> for. Buying past the top does nothing.
function MonetizationService:GrantRung(Data: any): boolean
	local Owned = Data.Store.CashRung()

	if Owned >= #Store.Rungs() then
		return false
	end

	Data.Store.CashRung(Owned + 1)

	return true
end

function MonetizationService:GrantPass(Player: Player, Data: any, Key: string): boolean
	local Passes = table.clone(Data.Store.Passes())

	if Key == "Everything" then
		for _, Bundled in Store.BundledPasses() do
			Passes[Bundled] = true
		end
	end

	Passes[Key] = true
	Data.Store.Passes(Passes)

	if Passes.Sprint then
		ApplyWalkSpeed(Player, Data)
	end

	if Passes.Founder then
		Tag(Player, "FOUNDER")
	elseif Passes.VIP then
		Tag(Player, "VIP")
	end

	--> VIP's welcome comes once, however many times the pass is found owned again.
	if Passes.VIP and not Data.Store.OwnedProducts()[VipBonusKey] then
		local Owned = table.clone(Data.Store.OwnedProducts())
		Owned[VipBonusKey] = true

		Data.Store.OwnedProducts(Owned)

		self:GrantPad(Data)
		self:GrantSkip(Player, Data, VipBonusHours)
	end

	return true
end

--> One entry point for a receipt, a pass and the grantproduct command alike. True when
--> something was handed over.
function MonetizationService:Grant(Player: Player, Data: any, Key: string): boolean
	local Rung = Store.Rung(Key)

	if Rung then
		return self:GrantRung(Data)
	end

	local Tier = Store.Tier(Key)

	if Tier then
		return ServerLuckService:Apply(Player, Tier.Multiplier, Tier.Minutes)
	end

	local Entry = Store.Entry(Key)

	if not Entry then
		return false
	end

	if Entry.Kind == "Pass" then
		return self:GrantPass(Player, Data, Key)
	end

	local Granted = false

	if Entry.Contents then
		Granted = self:GrantPack(Player, Data, Entry)
	elseif Entry.Hours then
		Granted = self:GrantSkip(Player, Data, Entry.Hours)
	elseif Key == "Pad" then
		Granted = self:GrantPad(Data)
	end

	if Granted and Entry.Once then
		local Owned = table.clone(Data.Store.OwnedProducts())
		Owned[Key] = true

		Data.Store.OwnedProducts(Owned)
	end

	return Granted
end

function MonetizationService:_Remember(Data: any, PurchaseId: string)
	local Remembered = table.clone(Data.Store.PurchaseIds())

	table.insert(Remembered, PurchaseId)

	while #Remembered > Store.PurchaseMemory do
		table.remove(Remembered, 1)
	end

	Data.Store.PurchaseIds(Remembered)
end

function MonetizationService:ProcessReceipt(Receipt: any): Enum.ProductPurchaseDecision
	local Player = Players:GetPlayerByUserId(Receipt.PlayerId)
	local Data = if Player then PlayerData[Player] else nil

	--> Not here, or not loaded: Roblox holds the receipt and asks again, on this server or the
	--> next one they join.
	if not Player or not Data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if table.find(Data.Store.PurchaseIds(), Receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local Key = Store.KeyOfId(Receipt.ProductId, "Product")

	if not Key then
		warn(`[Monetization] receipt for product {Receipt.ProductId}, which is not in Configs.Products`)

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local Ok, Granted = pcall(function()
		return self:Grant(Player, Data, Key)
	end)

	if not Ok then
		warn(`[Monetization] granting {Key} to {Player.Name} failed: {Granted}`)

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	--> A rung past the top or a pack that had nowhere to land is still theirs: what was paid for
	--> was answered as far as the game can, and holding the receipt would only re-run it.
	self:_Remember(Data, Receipt.PurchaseId)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--> Every pass with a real id, asked about once the save is up. What is already in the save is
--> not asked again, so a player with every pass costs one call per pass they lack.
function MonetizationService:_SyncPasses(Player: Player, Data: any)
	for _, Key in Store.BundledPasses() do
		self:_SyncPass(Player, Data, Key)
	end

	self:_SyncPass(Player, Data, "Founder")
end

function MonetizationService:_SyncPass(Player: Player, Data: any, Key: string)
	local Entry = Store.Entry(Key)

	if not Entry or not Entry.Id or Entry.Id == 0 or Store.Owns(Data, Key) then
		return
	end

	local Ok, Owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, Player.UserId, Entry.Id)

	if Ok and Owns then
		self:GrantPass(Player, Data, Key)
	end
end

function MonetizationService:_HandlePlayer(Player: Player)
	Player.CharacterAdded:Connect(function()
		local Data = PlayerData[Player]

		if Data then
			ApplyWalkSpeed(Player, Data)
		end
	end)

	task.spawn(function()
		local Data = PlayerData.Service:waitForData(Player)

		if not Player.Parent then
			return
		end

		ApplyWalkSpeed(Player, Data)

		--> the tree's speed nodes write the multiplier, and the character is walking while they do
		Data.Multipliers.WalkSpeed.Changed(function()
			ApplyWalkSpeed(Player, Data)
		end)

		Player:GetAttributeChangedSignal(SpeedAttribute):Connect(function()
			ApplyWalkSpeed(Player, Data)
		end)

		--> the starter's day starts on the first join and is stamped once, so a rejoin reads the
		--> same deadline rather than a fresh one
		if Data.Store.StarterExpiresAt() == 0 then
			Data.Store.StarterExpiresAt(os.time() + Store.StarterWindow)
		end

		if Store.Owns(Data, "Founder") then
			Tag(Player, "FOUNDER")
		elseif Store.Owns(Data, "VIP") then
			Tag(Player, "VIP")
		end

		self:_SyncPasses(Player, Data)
	end)
end

--> The Creator Hub id a key sells under, whatever kind of thing it is; 0 for one not made yet.
local function IdOf(Key: string): number
	local Rung = Store.Rung(Key)

	if Rung then
		return Rung.Id
	end

	local Tier = Store.Tier(Key)

	if Tier then
		return Tier.Id
	end

	local Entry = Store.Entry(Key)

	return if Entry then Entry.Id or 0 else 0
end

--> Studio only: a product with no id yet is granted as if Roblox had taken the Robux, so the
--> shop can be played through before the products exist. Anything with a real id goes through
--> Roblox like anywhere else, and outside Studio this does nothing at all.
function MonetizationService:DevBuy(Player: Player, Key: string): boolean
	local Data = PlayerData[Player]

	if not RunService:IsStudio() or not Data then
		return false
	end

	if IdOf(Key) ~= 0 then
		return false
	end

	local Granted = self:Grant(Player, Data, Key)

	if Granted then
		print(`[Monetization] Studio: granted "{Key}" to {Player.Name} without a product id`)
	end

	return Granted
end

function MonetizationService:Init()
	MarketplaceService.ProcessReceipt = function(Receipt)
		return self:ProcessReceipt(Receipt)
	end

	NetworkingServer.Shop.DevBuy.On(function(Player: Player, Key: string)
		return self:DevBuy(Player, Key)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(Player: Player, PassId: number, Purchased: boolean)
			local Data = PlayerData[Player]

			if not Purchased or not Data then
				return
			end

			local Key = Store.KeyOfId(PassId, "Pass")

			if not Key then
				warn(`[Monetization] {Player.Name} bought pass {PassId}, which is not in Configs.Products`)
				return
			end

			self:GrantPass(Player, Data, Key)
		end
	)

	for _, Player in Players:GetPlayers() do
		self:_HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:_HandlePlayer(Player)
	end)
end

return MonetizationService
