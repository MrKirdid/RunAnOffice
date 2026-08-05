-- Imports
local Packages = script:FindFirstAncestorOfClass("Folder")
local Fusion = require(Packages.Fusion)
local New = Fusion.New
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local Children = Fusion.Children

--[[
	@docs BuildTextLabels
	@desc Builds the text labels for the prompt
	@param ParentFrame : Frame
	@param ButtonHeldDown : Spring
	@returns {TextLabel, TextLabel}
]]

return function(ParentFrame, ButtonHeldDown): { any }
	local fadeSpring = Spring(
		Computed(function()
			return ButtonHeldDown:get() and 1 or 0
		end),
		30,
		1
	)

	local ActionText = New("TextLabel")({
		Name = "ActionText",
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.MontserratBold,
		TextSize = 19,
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ParentFrame,

		TextTransparency = fadeSpring,

		[Children] = {
			New("UIStroke")({
				Thickness = 1.5,
				Transparency = fadeSpring,
			}),
		},
	})

	local ObjectText = New("TextLabel")({
		Name = "ObjectText",
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.MontserratBold,
		TextSize = 14,
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ParentFrame,

		TextTransparency = fadeSpring,

		[Children] = {
			New("UIStroke")({
				Thickness = 1.5,
				Transparency = fadeSpring,
			}),
		},
	})

	return { ActionText, ObjectText }
end
