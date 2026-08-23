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

	Console.addGuard(function(Context)
		local Executor = Context.executor

		if Executor and not self:IsAdmin(Executor) then
			return "You do not have permission to run commands here."
		end

		return nil
	end)
end

return KmdrService
