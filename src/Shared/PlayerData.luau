local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local IsStudio = RunService:IsStudio()
local Dataservicetyped = require(Shared.Packages.Dataservicetyped)

type Employee = {
	Name: string,
	Type: string,
	--> os.time() at the moment they sat down. Missing on anyone seated before it was recorded.
	HiredAt: number?,
}

--> One seat per desk. Employee is nil until one walks over and sits down, and it is the only
--> record that they exist: nothing tracks employees separately once they are seated.
type Desk = {
	Computer: string,
	Keyboard: string,
	Monitor: string,
	Employee: Employee?,
}

local Config = {
	PlayerData = {
		Cash = 200,
		Rebirths = 0,

		Luck = 1, -- 1 is the plain table, 2 doubles the rarest chance

		RerollPads = 9,

		Pads = {} :: { [number]: { Component: string, Variant: string } },

		Holding = {} :: { Component: string?, Variant: string? },

		Floors = {
			[1] = {
				Desks = {} :: { [number]: Desk },
			},
		} :: { [number]: { Desks: { Desk } } },

		Gears = {},
		EquippedGear = nil,

		Upgrades = {
			RollsUnlocked = 1,

			--> Nodes of the tree that have been bought, by their id in Configs.Upgrades. Buying is
			--> the only thing that ever runs an upgrade's effect, and the effect writes into the
			--> rest of this table, so a rejoin reads the result instead of applying it again.
			Owned = {} :: { [string]: boolean },
		},

		--> What the tree scales, all 1 on a fresh save. Added to rather than multiplied, so four
		--> cash nodes at a quarter each land on 2x.
		Multipliers = {
			Cash = 1,
			EmployeeSpeed = 1,
			RollSpeed = 1,
		},

		--> The purple branch of the tree. Stealing is not in yet, so nothing reads this but the
		--> upgrades that raise it.
		Defense = 0,

		ItemShopStock = {},
		ItemShopLastUpdate = os.time() - 1,

		LastOnline = os.time(),
		TotalCashEarned = 0,

		Gamepasses = {},

		--> What the shop has sold, written only by MonetizationService. CashRung is how many rungs
		--> of the cash ladder are bought, and the only thing that decides which one is on offer
		--> next. Passes is every gamepass by key, whether bought or found owned at join.
		--> OwnedProducts remembers one-time products (the starter, VIP's welcome bonus) and
		--> PurchaseIds the last receipts, so a receipt Roblox sends twice is granted once.
		Store = {
			CashRung = 0,
			Passes = {} :: { [string]: boolean },
			OwnedProducts = {} :: { [string]: boolean },
			PurchaseIds = {} :: { string },
		},

		Settings = {
			Music = true,
			SFX = true,
		},
	},

	UseMock = false,
	ViewUserId = nil,
	DontSave = false,
}

return Dataservicetyped({
	template = Config.PlayerData,
	profileStoreDataPrefix = "data$",

	profileStoreIndex = IsStudio and "dev1.01" or "prod1.01",

	useMock = IsStudio and Config.UseMock,
	viewedUserId = IsStudio and Config.ViewUserId,
	dontSave = IsStudio and Config.DontSave,
})
