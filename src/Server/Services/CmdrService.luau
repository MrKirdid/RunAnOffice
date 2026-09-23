local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Cmdr = require(ServerScriptService.ServerPackages.Cmdr)
local CommandUtil = require(Shared.Console.CommandUtil)

local CmdrService = {
	Cmdr = nil :: any,
}

function CmdrService:Init()
	self.Cmdr = Cmdr

	--> Types before commands: a definition names its argument types by string, and registering one
	--> whose type is not known yet errors at registration rather than at the prompt.
	Cmdr.Registry:RegisterTypesIn(Server.CmdrTypes)
	Cmdr.Registry:RegisterDefaultCommands()
	Cmdr.Registry:RegisterCommandsIn(Server.Commands)

	--> The only check that counts. A client-run command skips the server entirely and skips this
	--> with it, which is why nothing that touches saved data is allowed to be one.
	Cmdr.Registry:RegisterHook("BeforeRun", function(Context)
		if not CommandUtil.IsAdmin(Context.Executor) then
			return "You do not have permission to run commands here."
		end

		return nil
	end)
end

return CmdrService
