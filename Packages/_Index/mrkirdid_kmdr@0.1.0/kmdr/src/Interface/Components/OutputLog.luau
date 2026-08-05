--!nonstrict
-- Nonstrict: see Interface/init.luau — Fusion 0.3 vs new-solver inference.
--[[
	OutputLog.luau — the scrolling output panel above the bar. New lines
	arrive with a fast typewriter reveal (MaxVisibleGraphemes — native and
	cheap); replayed buffer lines mount instantly.

	Lines are read-only TextBoxes, not TextLabels, so their text can be
	drag-selected and copied. The scroller pins to the bottom only while the
	user is already at the bottom — scrolling up to read history stays put.
]]

local External = require(script.Parent.Parent.Parent.External)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Parent.Types)

local Fusion = External.Fusion
local peek = Fusion.peek

type Scope = External.Scope
type UsedAs<T> = External.UsedAs<T>

export type LogLine = {
	read id: number,
	read text: string,
	read kind: Types.ReplyKind,
	read animate: boolean,
}

export type Props = {
	read lines: UsedAs<{ LogLine }>,
	read expanded: UsedAs<boolean>,
}

local PADDING_Y = 6

local function kindColor(kind: Types.ReplyKind): Color3
	if kind == "success" then
		return Theme.success
	elseif kind == "warning" then
		return Theme.warning
	elseif kind == "error" then
		return Theme.error
	elseif kind == "echo" then
		return Theme.secondary
	end
	return Theme.text
end

local function OutputLog(scope: Scope, props: Props): Frame
	local contentHeight = scope:Value(0)

	local targetHeight = scope:Computed(function(use)
		if not use(props.expanded) or #use(props.lines) == 0 then
			return 0
		end
		return math.min(use(contentHeight) + PADDING_Y * 2, Theme.logMaxHeight)
	end)

	local scroller: ScrollingFrame
	local atBottom = true

	local function pinToBottom()
		local maxScroll = math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y)
		scroller.CanvasPosition = Vector2.new(0, maxScroll)
	end

	scroller = scope:New("ScrollingFrame")({
		Name = "Scroller",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.hairline,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
		[Fusion.Children] = {
			scope:New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 2),
				[Fusion.OnChange("AbsoluteContentSize")] = function(size: Vector2)
					contentHeight:set(size.Y)
					if atBottom then
						pinToBottom()
					end
				end,
			}),
			scope:New("UIPadding")({
				PaddingLeft = UDim.new(0, Theme.padding),
				PaddingRight = UDim.new(0, Theme.padding),
				PaddingTop = UDim.new(0, PADDING_Y),
				PaddingBottom = UDim.new(0, PADDING_Y),
			}),
			scope:ForPairs(props.lines, function(_use, lineScope: Scope, index: number, line: LogLine)
				local typewriter = Motion.typewriter(lineScope)
				local isEcho = line.kind == "echo"
				local shown = if isEcho then `❯ {line.text}` else line.text
				if line.animate then
					typewriter.play(shown)
				end
				-- A read-only TextBox: selectable and copyable, unlike a label.
				local box = lineScope:New("TextBox")({
					Name = `Line{line.id}`,
					BackgroundTransparency = 1,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.fromScale(1, 0),
					LayoutOrder = line.id,
					Text = shown,
					TextEditable = false,
					ClearTextOnFocus = false,
					MultiLine = true,
					TextColor3 = kindColor(line.kind),
					TextSize = Theme.logTextSize,
					FontFace = Theme.fontMono,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = true,
					MaxVisibleGraphemes = if line.animate then typewriter.visible else -1,
				})
				return index, box
			end),
		},
	}) :: ScrollingFrame

	-- Track whether the user is at the bottom; only then do new lines pin.
	table.insert(
		scope,
		scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			local maxScroll = scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y
			atBottom = scroller.CanvasPosition.Y >= maxScroll - 8
		end)
	)

	return scope:New("Frame")({
		Name = "OutputLog",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 4,
		Size = Motion.layoutSpring(
			scope,
			scope:Computed(function(use)
				return UDim2.new(1, 0, 0, use(targetHeight))
			end)
		),
		Visible = scope:Computed(function(use)
			return use(targetHeight) > 0 or peek(contentHeight) > 0
		end),
		[Fusion.Children] = { scroller },
	}) :: Frame
end

return OutputLog
