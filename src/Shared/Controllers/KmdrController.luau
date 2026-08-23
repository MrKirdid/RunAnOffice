local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local Admins = require(Shared.Configs.Admins)

local KmdrController = {}

function KmdrController:Init()
	local Console = Kmdr.client({
		activationKeys = Admins.ActivationKeys,
		placeLabel = Admins.PlaceName,
	})

	self.Console = Console

	for _, Handle in ConsoleTypes do
		Console.registerType(Handle)
	end

	Console.registerDefaults()
	Console.registerFolder(Shared.Console.ClientCommands)
end

return KmdrController
