--> Registered on the client, not the server: the showcase is a local build, not a real part
--> of anyone's plot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Kmdr = require(Shared.Packages.Kmdr)
local PartsDemoController = require(Shared.Controllers.PartsDemoController)

local Action = Kmdr.enumOf("demoAction", { "build", "clear", "goto" })

local Definition = Kmdr.defineCommand({
	name = "partsdemo",
	description = "Builds the every-variant showcase off in the sky, or clears it, or drops you at it.",
	group = "admin",
	args = {
		Action = Action("What to do with the showcase"):default("build"),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	if Args.Action == "clear" then
		PartsDemoController:Clear()
		return "Cleared the parts demo."
	end

	if Args.Action == "goto" then
		PartsDemoController:Teleport()
		return "Dropped you at the parts demo."
	end

	PartsDemoController:Build()
	PartsDemoController:Teleport()

	return "Built the parts demo and dropped you at it."
end)
