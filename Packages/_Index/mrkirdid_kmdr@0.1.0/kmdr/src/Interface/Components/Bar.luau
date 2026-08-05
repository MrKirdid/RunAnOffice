--!nonstrict
-- Nonstrict: see Interface/init.luau — Fusion 0.3 vs new-solver inference.
--[[
	Bar.luau — the input row at the top of the palette: accent chevron plus
	the input stack (invisible-text TextBox over a RichText mirror).

	Typography is Builder Sans Medium — sans-first input is what separates
	"product palette" from "terminal overlay". The mirror renders syntax
	tints, error tinting and ghost text; when the line overflows the box
	(TextBox scrolls internally, the mirror can't follow) the mirror hides
	and the box shows plain text.
]]

local External = require(script.Parent.Parent.Parent.External)
local Theme = require(script.Parent.Parent.Theme)

local Fusion = External.Fusion

type Scope = External.Scope
type UsedAs<T> = External.UsedAs<T>

export type Props = {
	--- Rich text the mirror shows (built by the controller from the evaluation).
	read mirrorText: UsedAs<string>,
	read open: UsedAs<boolean>,
	--- Reports the created TextBox so the controller can wire input handling.
	read onTextBox: (textBox: TextBox) -> (),
}

export type BarHandle = {
	read frame: Frame,
}

local function Bar(scope: Scope, props: Props): BarHandle
	local overflowing = scope:Value(false)

	local chevron = scope:New("TextLabel")({
		Name = "Chevron",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, Theme.inputRowHeight),
		LayoutOrder = 1,
		Text = "❯",
		TextColor3 = Theme.accent,
		TextSize = Theme.inputTextSize,
		FontFace = Theme.fontSansSemiBold,
		TextXAlignment = Enum.TextXAlignment.Center,
	}) :: TextLabel

	local textBox: TextBox
	local mirror: TextLabel

	mirror = scope:New("TextLabel")({
		Name = "Mirror",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = props.mirrorText,
		RichText = true,
		TextColor3 = Theme.text,
		TextSize = Theme.inputTextSize,
		FontFace = Theme.fontSans,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Visible = scope:Computed(function(use)
			return not use(overflowing)
		end),
		ZIndex = 11,
	}) :: TextLabel

	textBox = scope:New("TextBox")({
		Name = "Input",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		PlaceholderText = "Type a command…",
		PlaceholderColor3 = Theme.tertiary,
		TextColor3 = Theme.text,
		TextTransparency = scope:Computed(function(use)
			return if use(overflowing) then 0 else 1
		end),
		TextSize = Theme.inputTextSize,
		FontFace = Theme.fontSans,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		MultiLine = false,
		ZIndex = 12,
		[Fusion.OnChange("TextBounds")] = function(bounds: Vector2)
			local width = textBox.AbsoluteSize.X
			overflowing:set(width > 0 and bounds.X > width - 4)
		end,
	}) :: TextBox

	props.onTextBox(textBox)

	local frame = scope:New("Frame")({
		Name = "InputRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.inputRowHeight),
		LayoutOrder = 1,
		[Fusion.Children] = {
			scope:New("UIPadding")({
				PaddingLeft = UDim.new(0, Theme.padding),
				PaddingRight = UDim.new(0, Theme.padding),
			}),
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
			}),
			chevron,
			scope:New("Frame")({
				Name = "InputStack",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0, 1),
				LayoutOrder = 2,
				[Fusion.Children] = {
					scope:New("UIFlexItem")({ FlexMode = Enum.UIFlexMode.Fill }),
					mirror,
					textBox,
				},
			}),
		},
	}) :: Frame

	return {
		frame = frame,
	}
end

return Bar
