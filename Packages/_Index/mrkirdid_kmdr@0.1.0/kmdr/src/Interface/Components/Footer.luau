--!nonstrict
-- Nonstrict: see Interface/init.luau — Fusion 0.3 vs new-solver inference.
--[[
	Footer.luau — the action bar at the bottom of the palette (Raycast
	model): a raised strip with the current status on the left (validation
	error > signature help > the per-letter place label) and keycap hints on
	the right. Keycaps are tiny fake-3D keys: raised fill, vertical sheen
	gradient, hairline stroke.
]]

local Completion = require(script.Parent.Parent.Completion)
local External = require(script.Parent.Parent.Parent.External)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)

local Fusion = External.Fusion

type Scope = External.Scope
type UsedAs<T> = External.UsedAs<T>

export type Props = {
	read signature: UsedAs<Completion.Signature?>,
	read errorText: UsedAs<string?>,
	read placeLabel: UsedAs<string>,
	read open: UsedAs<boolean>,
}

local function renderSignature(signature: Completion.Signature): string
	local pieces: { string } = { Theme.tint(Theme.escape(signature.name), Theme.secondary) }
	for _, arg in signature.args do
		local inner = `{Theme.escape(arg.label)}: {Theme.escape(arg.typeName)}`
		local wrapped = if arg.optional then `[{inner}]` else `&lt;{inner}&gt;`
		if arg.active then
			wrapped = `<u>{Theme.tint(wrapped, Theme.accent)}</u>`
		else
			wrapped = Theme.tint(wrapped, Theme.tertiary)
		end
		table.insert(pieces, wrapped)
	end
	return table.concat(pieces, "  ")
end

local function keycap(scope: Scope, order: number, key: string, label: string): Frame
	return scope:New("Frame")({
		Name = `Hint{order}`,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Theme.keycapHeight),
		LayoutOrder = order,
		[Fusion.Children] = {
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			}),
			scope:New("Frame")({
				Name = "Key",
				BackgroundColor3 = Theme.overlayColor,
				BackgroundTransparency = Theme.keycapTransparency,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Theme.keycapHeight),
				LayoutOrder = 1,
				[Fusion.Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, Theme.keycapRadius) }),
					scope:New("UIStroke")({
						Color = Theme.hairline,
						Transparency = Theme.strokeTransparency,
					}),
					scope:New("UIGradient")({
						Rotation = 90,
						Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 205, 215)),
					}),
					scope:New("UIPadding")({
						PaddingLeft = UDim.new(0, 6),
						PaddingRight = UDim.new(0, 6),
					}),
					scope:New("TextLabel")({
						Name = "Glyph",
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromScale(0, 1),
						Text = key,
						TextColor3 = Theme.secondary,
						TextSize = Theme.footerTextSize,
						FontFace = Theme.fontSans,
						TextXAlignment = Enum.TextXAlignment.Center,
					}),
				},
			}),
			scope:New("TextLabel")({
				Name = "Label",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Theme.keycapHeight),
				LayoutOrder = 2,
				Text = label,
				TextColor3 = Theme.tertiary,
				TextSize = Theme.footerTextSize,
				FontFace = Theme.fontSans,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		},
	}) :: Frame
end

local function Footer(scope: Scope, props: Props): Frame
	local statusText = scope:Computed(function(use): string
		local errorText = use(props.errorText)
		if errorText ~= nil then
			return Theme.tint(Theme.escape(errorText), Theme.error)
		end
		local signature = use(props.signature)
		if signature ~= nil then
			return renderSignature(signature)
		end
		return ""
	end)

	-- The per-letter place label shows when there's no status to report;
	-- re-rendering on open replays its stagger.
	local idleLabel = scope:Computed(function(use): string
		return if use(props.open) and use(statusText) == "" then use(props.placeLabel) else ""
	end)

	local brand = Motion.perLetterText(scope, {
		text = idleLabel,
		color = Theme.tertiary,
		textSize = Theme.footerTextSize,
		font = Theme.fontSansSemiBold,
	})

	return scope:New("Frame")({
		Name = "Footer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.footerHeight),
		LayoutOrder = 6,
		[Fusion.Children] = {
			scope:New("UIPadding")({
				PaddingLeft = UDim.new(0, Theme.padding),
				PaddingRight = UDim.new(0, Theme.padding),
			}),
			scope:New("Frame")({
				Name = "Status",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.6, 1),
				ZIndex = 2,
				[Fusion.Children] = {
					scope:New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					}),
					brand,
					scope:New("TextLabel")({
						Name = "StatusText",
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromScale(0, 1),
						LayoutOrder = 2,
						Text = statusText,
						RichText = true,
						TextColor3 = Theme.secondary,
						TextSize = Theme.footerTextSize,
						FontFace = Theme.fontSans,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}),
				},
			}),
			scope:New("Frame")({
				Name = "Hints",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.4, 1),
				ZIndex = 2,
				[Fusion.Children] = {
					scope:New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						Padding = UDim.new(0, 14),
					}),
					keycap(scope, 1, "Tab", "Complete"),
					keycap(scope, 2, "↵", "Run"),
				},
			}),
		},
	}) :: Frame
end

return Footer
