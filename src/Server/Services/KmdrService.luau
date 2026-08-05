local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local Admins = require(Shared.Configs.Admins)

local KmdrService = {}

function KmdrService:IsAdmin(Player: Player): boolean
	if RunService:IsStudio() or not Admins.RestrictInGame then
		return true
	end

	if Admins.UserIds[Player.UserId] then
		return true
	end

	--> A group owned place reports the group id here, so only a user owned one has a creator
	--> that maps onto a player.
	return game.CreatorType == Enum.CreatorType.User and Player.UserId == game.CreatorId
end

function KmdrService:Init()
	local Console = Kmdr.server()
	self.Console = Console

	for _, Handle in ConsoleTypes do
		Console.registerType(Handle)
	end

	Console.registerDefaults()
	Console.registerFolder(Server.Commands)

	--> Kmdr blocks every command outside Studio until a guard exists, so this is both the
	--> permission check and the switch that turns the console on at all.
	Console.addGuard(function(Context)
		local Executor = Context.executor

		--> No executor means the server ran it itself, which is already trusted
		if Executor and not self:IsAdmin(Executor) then
			return "You do not have permission to run commands here."
		end

		return nil
	end)
end

return KmdrService
