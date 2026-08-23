local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local IsStudio = RunService:IsStudio()
local Dataservicetyped = require(Shared.Packages.Dataservicetyped)

type Employee = {
	Name: string,
	Type: string,
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
