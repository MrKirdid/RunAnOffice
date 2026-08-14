local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local IsStudio = RunService:IsStudio()
local Dataservicetyped = require(Shared.Packages.Dataservicetyped)

type Desk = {
	Computer: string,
	Keyboard: string,
	Monitor: string,
}

local Config = {
	PlayerData = {
		Cash = 200, -- Starting amount, subject to change but I think it should be enough for tutorial
		Rebirths = 0,

		Luck = 1, -- Multiplier on the roll odds. 1 is the plain table, 2 doubles the rarest chance

		RerollPads = 9,

		--> What each reroll pad is holding right now, keyed by slot. The server writes this when
		--> it rolls and clears the slot when the part is picked up, so a part can only ever be
		--> claimed once and only if the server put it there.
		Pads = {} :: { [number]: { Component: string, Variant: string } },

		--> The one component in hand. Empty table means empty handed. One slot is the whole
		--> anti duplication story: a part is moved into it and moved out, never copied.
		Holding = {} :: { Component: string?, Variant: string? },

		Employees = {} :: { [number]: { desk: { Floor: number, Desk: number }, EmployeeType: string } },

		Floors = {
			[1] = {
				Desks = {} :: { [number]: Desk },
			},
		} :: { [number]: { Desks: { Desk } } },

		Gears = {},
		EquippedGear = nil,

		Upgrades = {
			RollsUnlocked = 1,
		},

		ItemShopStock = {},
		ItemShopLastUpdate = os.time() - 1,

		LastOnline = os.time(),
		TotalCashEarned = 0,

		Gamepasses = {},

		Settings = {
			Music = true,
			SFX = true,
		},
	},

	--- -- --- -- --- -- ---

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
