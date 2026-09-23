local ReplicatedStorage = game:GetService("ReplicatedStorage")

--> Client-run, so it never reaches the server and the require has to stay inside the callback:
--> this definition is loaded on the server too, where a controller does not exist.
return {
	Name = "previewmodel",
	Aliases = { "preview" },
	Description = "Opens a viewport window showing one component model, spinning, with its odds.",
	Group = "Admin",
	Args = {
		{
			Type = "component",
			Name = "Component",
			Description = "Computer, Keyboard or Monitor",
		},
		{
			Type = "variant",
			Name = "Variant",
			Description = "Which variant of it to show",
		},
	},

	ClientRun = function(_Context, Component: string, Variant: string): string
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		local PreviewController = require(Shared.Controllers.PreviewController)

		local Shown, Problem = PreviewController:Show(Component, Variant)

		if not Shown then
			return `Could not show {Variant} {Component}: {Problem}`
		end

		return `Previewing {Variant} {Component}.`
	end,
}
