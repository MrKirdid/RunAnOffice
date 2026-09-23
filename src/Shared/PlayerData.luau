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
		--> Enough for the first desk at 250, a hire off the street and most of the second desk.
		Cash = 1000,
		Rebirths = 0,

		--> Which step of the tutorial the player is on, 1 for the first, one past the last once it is
		--> done. Only TutorialService writes it, off what the rest of the save says.
		TutorialStage = 1,

		--> How many employees have been hired and whether the base has been locked, counted only for
		--> the tutorial, and whether the rigged first roll has been handed out. Written by
		--> EmployeeService, BaseLockingService and RollingService.
		TutorialHires = 0,
		TutorialLocked = false,
		TutorialRolled = false,

		--> How many times the roll button has been pressed, ever. Written by RollingService, and
		--> read by it for the lucky roll Configs.Tutorial names.
		Rolls = 0,

		Luck = 1, -- 1 is the plain table, 2 doubles the rarest chance

		RerollPads = 9,

		Pads = {} :: { [number]: { Component: string, Variant: string } },

		--> The one thing in hand: a part, as Component and Variant, picked up off a pad or taken
		--> out of the inventory; or an employee, as Name and Type, taken out of the inventory or
		--> lifted off somebody else's desk. The Stolen fields are set only by a theft and cleared
		--> once the thief is seen inside their own base: while they are set the employee still
		--> belongs to the desk they came off, which is where they go back to if the thief is caught.
		Holding = {} :: {
			Component: string?,
			Variant: string?,
			Name: string?,
			Type: string?,
			StolenFrom: number?,
			StolenFloor: number?,
			StolenSlot: number?,
		},

		--> Parts put away rather than placed, and employees bought and not yet seated, oldest
		--> first. Each is one or the other. Nothing in here earns anything: a part only pays once
		--> it is standing on a desk with somebody sat at it, and an employee only once sat down.
		Inventory = {} :: { { Component: string?, Variant: string?, Name: string?, Type: string? } },

		--> The first desk comes with the save, standing and wearing the three commonest parts, so
		--> the tutorial has something to swap a better roll onto. Configs.Tutorial names the variant.
		Floors = {
			[1] = {
				Desks = {
					[1] = { Computer = "Mossy", Keyboard = "Mossy", Monitor = "Mossy" },
				} :: { [number]: Desk },
			},
		} :: { [number]: { Desks: { Desk } } },

		--> Gears bought from the gear shop, by key in Configs.Gears, kept for good; the ones in the
		--> backpack right now; and how many may be in it at once, raised by the tree. Gears and
		--> EquippedGears are written only by GearService, GearSlots only by an upgrade.
		Gears = {} :: { [string]: boolean },
		EquippedGears = {} :: { [string]: boolean },
		GearSlots = 2,

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
			WalkSpeed = 1,
		},

		--> The purple branch of the tree. Stealing is in, but nothing acts on this yet beyond the
		--> upgrades that raise it; what it buys the base is still to come.
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
			--> os.time() the starter pack stops being offered, set on the first join
			StarterExpiresAt = 0,
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

	--> Bumped 2026-09-20 to wipe every save: the gear shop came in and then grew gear slots, with
	--> the tutorial rebuilt around a starter desk just before. Old saves stay under the 1.04 keys.
	profileStoreIndex = IsStudio and "dev1.05" or "prod1.05",

	useMock = IsStudio and Config.UseMock,
	viewedUserId = IsStudio and Config.ViewUserId,
	dontSave = IsStudio and Config.DontSave,
})
