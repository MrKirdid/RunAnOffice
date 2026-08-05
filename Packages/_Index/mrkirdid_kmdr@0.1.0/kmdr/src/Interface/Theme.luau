--!strict
--[[
	Theme.luau — the "Kmdr palette" design system.

	Modeled on Raycast/Linear command palettes: an OPAQUE near-black panel
	floating over a blurred world, depth from a stepped surface ladder and
	1px hairlines (never heavy transparency), Builder Sans typography with
	monospace demoted to literal command/output text, one disciplined accent.
]]

local Theme = {
	-- Frosted glass: a translucent near-black panel over the blurred world.
	-- Raised elements are white overlays at high transparency (glass on glass).
	base = Color3.fromRGB(14, 14, 17), -- panel glass tint
	panelTransparency = 0.2, -- the glass
	overlayColor = Color3.fromRGB(255, 255, 255), -- raised glass layers
	selectionTransparency = 0.88, -- selected row fill (white overlay)
	keycapTransparency = 0.9,
	hairline = Color3.fromRGB(120, 122, 132), -- 1px strokes (glass edge)
	sheen = Color3.fromRGB(255, 255, 255), -- top-edge inner highlight

	-- Text ladder
	text = Color3.fromRGB(242, 243, 245), -- primary: titles, input
	secondary = Color3.fromRGB(168, 173, 184), -- descriptions, footer labels
	tertiary = Color3.fromRGB(108, 112, 120), -- hints, placeholder, keycap glyphs

	-- One accent + semantic states
	accent = Color3.fromRGB(124, 134, 255), -- caret, matched chars, active arg
	error = Color3.fromRGB(255, 107, 107),
	success = Color3.fromRGB(89, 212, 153),
	warning = Color3.fromRGB(255, 197, 51),
	string = Color3.fromRGB(255, 197, 51), -- quoted tokens (warning hue, subtle)
	number = Color3.fromRGB(255, 168, 116), -- numeric tokens

	-- Typography: Builder Sans first; mono ONLY for command/output literals.
	fontSans = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	fontSansRegular = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
	fontSansSemiBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold),
	fontMono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),

	inputTextSize = 20,
	rowTitleSize = 16,
	rowDetailSize = 14,
	footerTextSize = 13,
	logTextSize = 15,

	-- Panel metrics — squircle-generous corners, floating with a top margin.
	panelWidth = 740,
	panelRadius = 20,
	panelTopOffset = 12, -- floating gap from the screen top
	selectionRadius = 11,
	keycapRadius = 7,
	inputRowHeight = 56,
	rowHeight = 44,
	listInset = 6, -- selection fill insets from panel edges
	footerHeight = 36,
	keycapHeight = 20,
	padding = 16,
	maxSuggestionRows = 8,
	logMaxHeight = 308, -- 7 mono lines-ish; content area cap

	strokeTransparency = 0.6,
	sheenTransparency = 0.92,

	-- World treatment while the console is open (this is what makes the
	-- translucent panel read as frosted glass rather than a cheap overlay)
	worldBlurSize = 16,
	worldDim = 0.12, -- ColorCorrection brightness reduction

	-- Motion (unchanged house rules: springs move, fades are linear)
	springSpeedLayout = 35,
	springSpeedPopup = 40,
	springSpeedSnappy = 45,
	fadeDuration = 0.12,
	fadeDurationFast = 0.10,
	typewriterSpeed = 140,
	typewriterMaxDuration = 0.30,
	perLetterStagger = 0.012,
	perLetterLimit = 32,
}

--- Rich text escaping.
function Theme.escape(text: string): string
	local result = string.gsub(text, "&", "&amp;")
	result = string.gsub(result, "<", "&lt;")
	result = string.gsub(result, ">", "&gt;")
	return result
end

--- Wraps text in a rich-text color tag.
function Theme.tint(text: string, color: Color3): string
	local r = math.round(color.R * 255)
	local g = math.round(color.G * 255)
	local b = math.round(color.B * 255)
	return `<font color="rgb({r},{g},{b})">{text}</font>`
end

return Theme
