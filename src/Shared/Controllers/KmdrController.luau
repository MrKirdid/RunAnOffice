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

	--> The server only syncs each command's metadata, so the client has to hold the same
	--> argument types itself or it cannot check or suggest them while you are typing.
	for _, Handle in ConsoleTypes do
		Console.registerType(Handle)
	end

	Console.registerDefaults()
	Console.registerFolder(Shared.Console.ClientCommands)
end

return KmdrController
