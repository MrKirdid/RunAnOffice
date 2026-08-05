--!nonstrict
-- Nonstrict: see Interface/init.luau — Fusion 0.3 vs new-solver inference.
--[[
	SuggestionList.luau — full-width results section inside the palette
	(Raycast model): 44px rows, bright title left, muted detail right,
	neutral rounded selection fill that slides between rows on a snappy
	spring. The section's height springs open/closed; text fades linearly.
]]

local Completion = require(script.Parent.Parent.Completion)
local External = require(script.Parent.Parent.Parent.External)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)

local Fusion = External.Fusion

type Scope = External.Scope
type UsedAs<T> = External.UsedAs<T>

export type Props = {
	read analysis: UsedAs<Completion.Analysis?>,
	read selectedIndex: UsedAs<number>,
	read open: UsedAs<boolean>,
	read onAccept: (index: number) -> (),
	--- Hovering a row moves the selection (mouse parity with arrow keys).
	read onHover: (index: number) -> (),
}

type RowModel = {
	read absoluteIndex: number,
	read label: string,
	read detail: string?,
	read prefix: string,
}

--- Rich text with the fuzzy-matched characters of `prefix` tinted accent.
local function highlightMatch(label: string, prefix: string): string
	if #prefix == 0 then
		return Theme.escape(label)
	end
	local pieces: { string } = {}
	local prefixLower = string.lower(prefix)
	local labelLower = string.lower(label)
	local prefixIndex = 1
	for index = 1, #label do
		local char = string.sub(label, index, index)
		local escaped = Theme.escape(char)
		if
			prefixIndex <= #prefixLower
			and string.sub(labelLower, index, index) == string.sub(prefixLower, prefixIndex, prefixIndex)
		then
			table.insert(pieces, Theme.tint(escaped, Theme.accent))
			prefixIndex += 1
		else
			table.insert(pieces, escaped)
		end
	end
	return table.concat(pieces)
end

local function SuggestionList(scope: Scope, props: Props): Frame
	local rowCount = scope:Computed(function(use)
		local analysis = use(props.analysis)
		return if analysis ~= nil then math.min(#analysis.items, Theme.maxSuggestionRows) else 0
	end)

	local isVisible = scope:Computed(function(use)
		return use(props.open) and use(rowCount) > 0
	end)

	-- Window start so the selected row stays visible.
	local windowStart = scope:Computed(function(use)
		local selected = use(props.selectedIndex)
		local visibleRows = use(rowCount)
		local analysis = use(props.analysis)
		local total = if analysis ~= nil then #analysis.items else 0
		if total <= visibleRows then
			return 1
		end
		return math.clamp(selected - visibleRows + 1, 1, total - visibleRows + 1)
	end)

	local rows = scope:Computed(function(use): { RowModel }
		local analysis = use(props.analysis)
		if analysis == nil then
			return {}
		end
		local start = use(windowStart)
		local result: { RowModel } = {}
		for offset = 0, use(rowCount) - 1 do
			local item = analysis.items[start + offset]
			if item == nil then
				break
			end
			table.insert(result, {
				absoluteIndex = start + offset,
				label = item.label,
				detail = item.detail,
				prefix = analysis.prefix,
			})
		end
		return result
	end)

	local heightGoal = scope:Computed(function(use): number
		return if use(isVisible) then use(rowCount) * Theme.rowHeight + Theme.listInset * 2 else 0
	end)

	local textFade = Motion.fade(
		scope,
		scope:Computed(function(use)
			return if use(isVisible) then 0 else 1
		end),
		Theme.fadeDurationFast
	)

	-- Neutral selection fill slides between visible rows.
	local highlightY = scope:Computed(function(use): number
		local visibleIndex = use(props.selectedIndex) - use(windowStart)
		return math.max(visibleIndex, 0) * Theme.rowHeight
	end)

	return scope:New("Frame")({
		Name = "Suggestions",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 3,
		Size = Motion.popupSpring(
			scope,
			scope:Computed(function(use)
				return UDim2.new(1, 0, 0, use(heightGoal))
			end)
		),
		Visible = scope:Computed(function(use)
			return use(heightGoal) > 0
		end),
		[Fusion.Children] = {
			scope:New("UIPadding")({
				PaddingLeft = UDim.new(0, Theme.listInset),
				PaddingRight = UDim.new(0, Theme.listInset),
				PaddingTop = UDim.new(0, Theme.listInset),
				PaddingBottom = UDim.new(0, Theme.listInset),
			}),
			scope:New("Frame")({
				Name = "Highlight",
				BackgroundColor3 = Theme.overlayColor,
				BackgroundTransparency = Theme.selectionTransparency,
				Size = UDim2.new(1, 0, 0, Theme.rowHeight),
				Position = Motion.snappySpring(
					scope,
					scope:Computed(function(use)
						return UDim2.fromOffset(0, use(highlightY))
					end)
				),
				ZIndex = 21,
				[Fusion.Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, Theme.selectionRadius) }),
				},
			}),
			scope:New("Frame")({
				Name = "Rows",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 22,
				[Fusion.Children] = {
					scope:New("UIListLayout")({
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					scope:ForPairs(rows, function(_use, rowScope: Scope, index: number, row: RowModel)
						local button = rowScope:New("TextButton")({
							Name = `Row{index}`,
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, Theme.rowHeight),
							LayoutOrder = index,
							Text = "",
							ZIndex = 22,
							[Fusion.OnEvent("Activated")] = function()
								props.onAccept(row.absoluteIndex)
							end,
							[Fusion.OnEvent("MouseEnter")] = function()
								props.onHover(row.absoluteIndex)
							end,
							[Fusion.Children] = {
								rowScope:New("TextLabel")({
									Name = "Title",
									BackgroundTransparency = 1,
									Size = UDim2.new(0.55, -24, 1, 0),
									Position = UDim2.fromOffset(12, 0),
									Text = highlightMatch(row.label, row.prefix),
									RichText = true,
									TextColor3 = Theme.text,
									TextTransparency = textFade,
									TextSize = Theme.rowTitleSize,
									FontFace = Theme.fontSans,
									TextXAlignment = Enum.TextXAlignment.Left,
									TextTruncate = Enum.TextTruncate.AtEnd,
									ZIndex = 23,
								}),
								rowScope:New("TextLabel")({
									Name = "Detail",
									BackgroundTransparency = 1,
									Size = UDim2.new(0.45, -24, 1, 0),
									Position = UDim2.new(0.55, 12, 0, 0),
									Text = Theme.escape(row.detail or ""),
									TextColor3 = Theme.tertiary,
									TextTransparency = textFade,
									TextSize = Theme.rowDetailSize,
									FontFace = Theme.fontSansRegular,
									TextXAlignment = Enum.TextXAlignment.Right,
									TextTruncate = Enum.TextTruncate.AtEnd,
									ZIndex = 23,
								}),
							},
						})
						return index, button
					end),
				},
			}),
		},
	}) :: Frame
end

return SuggestionList
