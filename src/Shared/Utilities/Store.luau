local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Products = require(Shared.Configs.Products)

--> The one place anything bought with Robux turns into a number the game reads. RevenueService
--> asks here what to multiply the plot's rate by, every roll asks here what luck to roll at, and
--> both sides can, so the odds a card prints are the odds the server rolls.
--> The upgrade tree is additive and lives in Data.Luck and Data.Multipliers; everything bought is
--> multiplied on top of it, and none of it is ever written back into those.

--> Server luck is a fact about the server, not a player, so it lives on Workspace as attributes:
--> replicated to everyone for free, and gone with the server.
local LuckAttribute = "ServerLuck"
local ExpiresAttribute = "ServerLuckExpires"
local SponsorAttribute = "ServerLuckSponsor"

local LuckyRollerMultiplier = 2
local VipCashMultiplier = 1.25

--> Pads go 1 to 9 through the tree, and the product stops at the same place.
local MaxPads = 9

--> How long the starter pack is on offer from the first join.
local StarterWindow = 24 * 60 * 60

--> Roblox keeps the last purchase ids so the same receipt is never granted twice; this is how
--> many are worth remembering per player before the oldest is forgotten.
local PurchaseMemory = 50

export type Entry = Products.Entry
export type Rung = Products.Rung
export type Tier = Products.Tier
export type DeskSet = Products.DeskSet

local Store = {
	LuckAttribute = LuckAttribute,
	ExpiresAttribute = ExpiresAttribute,
	SponsorAttribute = SponsorAttribute,

	MaxPads = MaxPads,
	StarterWindow = StarterWindow,
	PurchaseMemory = PurchaseMemory,
}

--> Every entry that is a thing for sale, by key, with the ladder's rungs and the luck tiers
--> indexed alongside so a rung or a tier is looked up the same way as a pass.
local ByKey: { [string]: Entry } = {}
local ByRungKey: { [string]: { Rung: Rung, Index: number } } = {}
local ByTierKey: { [string]: Tier } = {}
local Rungs: { Rung } = {}
local Tiers: { Tier } = {}

for _, Entry in Products.Layout do
	if Entry.Key then
		ByKey[Entry.Key] = Entry
	end

	if Entry.Rungs then
		Rungs = Entry.Rungs

		for Index, Rung in Entry.Rungs do
			ByRungKey[Rung.Key] = { Rung = Rung, Index = Index }
		end
	end

	if Entry.Tiers then
		Tiers = Entry.Tiers

		for _, Tier in Entry.Tiers do
			ByTierKey[Tier.Key] = Tier
		end
	end
end

--> Passes are what Everything is made of: every entry drawn as a pass, apart from Everything
--> itself and Founder, which is bought on its own.
local BundledPasses: { string } = {}

for _, Entry in Products.Layout do
	if Entry.Kind == "Pass" and Entry.Key and Entry.Key ~= "Everything" and Entry.Key ~= "Founder" then
		table.insert(BundledPasses, Entry.Key)
	end
end

function Store.Entry(Key: string): Entry?
	return ByKey[Key]
end

function Store.Rung(Key: string): (Rung?, number?)
	local Found = ByRungKey[Key]

	if not Found then
		return nil, nil
	end

	return Found.Rung, Found.Index
end

function Store.Rungs(): { Rung }
	return Rungs
end

function Store.Tier(Key: string): Tier?
	return ByTierKey[Key]
end

function Store.Tiers(): { Tier }
	return Tiers
end

function Store.BundledPasses(): { string }
	return BundledPasses
end

--> The key a Roblox id belongs to, for a receipt or a pass prompt coming back. Rungs and tiers
--> answer too, as their own keys.
function Store.KeyOfId(Id: number, Kind: Products.Kind): string?
	if Id == 0 then
		return nil
	end

	for _, Entry in Products.Layout do
		if Entry.Id == Id and Entry.Kind == Kind then
			return Entry.Key
		end
	end

	if Kind ~= "Product" then
		return nil
	end

	for _, Rung in Rungs do
		if Rung.Id == Id then
			return Rung.Key
		end
	end

	for _, Tier in Tiers do
		if Tier.Id == Id then
			return Tier.Key
		end
	end

	return nil
end

function Store.Owns(Data: any, Key: string): boolean
	return Data.Store.Passes()[Key] == true
end

--> Whether the starter is still on offer: not bought, and inside the first day. Before the
--> server has stamped the day it counts as on offer, since the stamp lands with the save.
function Store.StarterOnOffer(Data: any): boolean
	if Data.Store.OwnedProducts().Starter then
		return false
	end

	local Expires = Data.Store.StarterExpiresAt()

	return Expires == 0 or os.time() < Expires
end

--> What the server's luck is right now, 1 when nothing is running or it has run out. Read off
--> the clock rather than waiting for the expiry to be cleared, so a roll in the last second of a
--> boost and the first second after it agree with the banner.
function Store.ServerLuck(): number
	local Multiplier = Workspace:GetAttribute(LuckAttribute)
	local Expires = Workspace:GetAttribute(ExpiresAttribute)

	if type(Multiplier) ~= "number" or type(Expires) ~= "number" then
		return 1
	end

	return if os.time() < Expires then Multiplier else 1
end

--> The tier the shop offers: the first above what the server is running, or the top one again
--> to extend it.
function Store.NextTier(): Tier?
	local Current = Store.ServerLuck()

	for _, Tier in Tiers do
		if Tier.Multiplier > Current then
			return Tier
		end
	end

	return Tiers[#Tiers]
end

--> The luck a player's rolls happen at: the tree's number, doubled by Lucky Roller, times
--> whatever the server is running.
function Store.Luck(Data: any): number
	local Luck = Data.Luck()

	if Store.Owns(Data, "LuckyRoller") then
		Luck *= LuckyRollerMultiplier
	end

	return Luck * Store.ServerLuck()
end

--> What the bought rung multiplies income by, 1 before any is bought.
function Store.RungMultiplier(Data: any): number
	local Owned = Data.Store.CashRung()
	local Rung = Rungs[Owned]

	return if Rung then Rung.Multiplier else 1
end

--> Multiplied onto the tree's cash multiplier by RevenueService: the ladder's rung, then VIP.
function Store.CashMultiplier(Data: any): number
	local Multiplier = Store.RungMultiplier(Data)

	if Store.Owns(Data, "VIP") then
		Multiplier *= VipCashMultiplier
	end

	return Multiplier
end

return Store
