local ReplicatedStorage = game:GetService("ReplicatedStorage")

--> Client-run, so it never reaches the server and the require has to stay inside the callback:
--> this definition is loaded on the server too, where a controller does not exist.
return {
	Name = "partsdemo",
	Description = "Builds the every-variant showcase off in the sky, or clears it, or drops you at it.",
	Group = "Admin",
	Args = {
		{
			Type = "demoAction",
			Name = "Action",
			Description = "What to do with the showcase",
			Default = "build",
		},
	},

	ClientRun = function(_Context, Action: string): string
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		local PartsDemoController = require(Shared.Controllers.PartsDemoController)

		if Action == "clear" then
			PartsDemoController:Clear()

			return "Cleared the parts demo."
		end

		if Action == "goto" then
			PartsDemoController:Teleport()

			return "Dropped you at the parts demo."
		end

		PartsDemoController:Build()
		PartsDemoController:Teleport()

		return "Built the parts demo and dropped you at it."
	end,
}
