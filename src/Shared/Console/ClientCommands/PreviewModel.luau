--> Registered on the client, not the server: the whole point is a viewport on the caller's
--> own screen, so there is nothing for the server to do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local PreviewController = require(Shared.Controllers.PreviewController)

local Definition = Kmdr.defineCommand({
	name = "previewmodel",
	aliases = { "preview" },
	description = "Opens a viewport window showing one component model, spinning, with its odds.",
	group = "admin",
	args = {
		Component = ConsoleTypes.Component("Computer, Keyboard or Monitor"),
		Variant = ConsoleTypes.Variant("Which variant of it to show"),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	local Shown, Error = PreviewController:Show(Args.Component, Args.Variant)

	if not Shown then
		return `Could not show {Args.Variant} {Args.Component}: {Error}`
	end

	return `Previewing {Args.Variant} {Args.Component}.`
end)
