-- Imports
local Packages = script:FindFirstAncestorOfClass("Folder")
local Fusion = require(Packages.Fusion)

local New = Fusion.New
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local Children = Fusion.Children

return function(PromptUI, ButtonHeldDown, PromptTransparency, AspectRatioValue, CurrentBarSize, CurrentFrameScaleFactor)
	-- 🔑 shared animated transparency (iconic-lib style)
	local AnimatedTransparency = Spring(PromptTransparency, 30, 1)

	-- MAIN CONTAINER
	local Frame = New("CanvasGroup")({
		Size = Spring(
			Computed(function()
				return ButtonHeldDown:get() and UDim2.fromScale(0.5, 1) or UDim2.fromScale(1, 1)
			end),
			20,
			0.4
		),

		Rotation = Spring(
			Computed(function()
				if ButtonHeldDown:get() then
					return -5
				elseif PromptTransparency:get() < 1 then
					return 0
				else
					return 5
				end
			end),
			30,
			0.1
		),

		BackgroundTransparency = 0.5,
		GroupTransparency = AnimatedTransparency,
		BackgroundColor3 = Color3.fromRGB(15, 15, 15),
		Parent = PromptUI,

		[Children] = {

			New("UICorner")({
				CornerRadius = UDim.new(0.3, 0),
			}),

			-- ✅ STROKE NOW VISIBLY TWEENS
			New("UIStroke")({
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				LineJoinMode = Enum.LineJoinMode.Round,

				Transparency = AnimatedTransparency,
			}),

			New("UIAspectRatioConstraint")({
				AspectRatio = Spring(
					Computed(function()
						return ButtonHeldDown:get() and 1 or AspectRatioValue:get()
					end),
					20,
					0.4
				),
			}),

			-- Progress bar track (sits flush at the bottom of the container)
			New("CanvasGroup")({
				Name = "ProgressBarTrack",
				Position = UDim2.new(0, 4, 1, -4),
				AnchorPoint = Vector2.new(0, 1),
				Size = UDim2.new(1, -8, 0, 4),
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.85,
				GroupTransparency = Spring(
					Computed(function()
						return ButtonHeldDown:get() and 0 or 1
					end),
					25,
					1
				),
				ClipsDescendants = true,

				[Children] = {
					New("UICorner")({
						CornerRadius = UDim.new(1, 0),
					}),

					-- Fill bar (child of the track so it clips to the track's rounded shape)
					New("Frame")({
						Name = "ProgressBarFill",
						Position = UDim2.fromScale(0, 0),
						Size = Spring(
							Computed(function()
								return UDim2.fromScale(CurrentBarSize:get(), 1)
							end),
							40,
							0.85
						),
						BorderSizePixel = 0,
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 0,

						[Children] = {
							New("UICorner")({
								CornerRadius = UDim.new(1, 0),
							}),

							-- Gradient for a subtle colored glow across the fill
							New("UIGradient")({
								Color = ColorSequence.new({
									ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 200, 255)),
									ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
									ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 235, 255)),
								}),
							}),
						},
					}),
				},
			}),

			New("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.5, 0.5),
					NumberSequenceKeypoint.new(1, 0),
				}),

				Rotation = 45,

				Offset = Spring(
					Computed(function()
						return PromptTransparency:get() < 1 and Vector2.new(1, 0) or Vector2.new(-1, 0)
					end),
					8,
					1
				),
			}),
		},
	})

	-- INPUT WRAPPER
	local InputFrame = New("Frame")({
		Name = "InputFrame",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Parent = Frame,
	})

	local ResizeableInputFrame = New("Frame")({
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = InputFrame,

		[Children] = {

			New("UIScale")({
				Scale = Spring(CurrentFrameScaleFactor, 20, 0.7),
			}),

			New("Frame")({
				Name = "RoundFrame",
				Size = UDim2.fromOffset(48, 48),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundTransparency = 0.5,
				BackgroundColor3 = Color3.new(0, 0, 0),

				[Children] = {
					New("UICorner")({
						CornerRadius = UDim.new(1, 0),
					}),
				},
			}),
		},
	})

	return { Frame, ResizeableInputFrame }
end
