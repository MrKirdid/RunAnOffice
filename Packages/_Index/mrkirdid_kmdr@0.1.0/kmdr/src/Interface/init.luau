--!nonstrict
-- Fusion 0.3 predates the new solver: `UsedAs<T> = StateObject<T> | T` defeats
-- generic inference at every use() site, so the Fusion-facing interface layer
-- runs nonstrict. The public API and engine (everything outside Interface/)
-- stays fully strict. Revisit when Fusion ships new-solver-ready types.
--[[
	Interface/init.luau — the controller. Owns the palette panel, the world
	blur, the reactive state graph, and the keyboard state machine:

	                     popup open           popup closed
	  Up / Down          move selection       history (prefix-filtered)
	  Tab / Shift+Tab    accept / cycle       accept ghost, else open popup
	  Enter              run the line         run the line
	  Right / End        —                    accept ghost (at line end)
	  Ctrl+Backspace     delete word left     delete word left
	  Ctrl+←/→ (+Shift)  word jump / select   word jump / select
	  Ctrl+U             clear the line       clear the line
	  Esc                close popup (focus release is native TextBox behavior)

	Structure (Raycast-style unified panel, docked to the top of the screen —
	square top corners, rounded bottom):

	  ┌──────────────────────────────────────┐ ← screen top
	  │ ❯  input row (Builder Sans)          │
	  ├──────────────────────────────────────┤ ← hairline
	  │ suggestion rows (full width)         │
	  │ output log (mono, copyable)          │
	  ├──────────────────────────────────────┤ ← hairline
	  │ status / signature      [Tab] [↵]    │ ← footer
	  └──────────────────────────────────────┘

	No CanvasGroup anywhere — group rasterization softens text. Open/close is
	a slide+scale spring plus a linear world blur/dim; text stays crisp.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = require(script.Parent.Client)
local Completion = require(script.Completion)
local Dispatcher = require(script.Parent.Dispatcher)
local External = require(script.Parent.External)
local Motion = require(script.Motion)
local Theme = require(script.Theme)
local Types = require(script.Parent.Types)

local Bar = require(script.Components.Bar)
local Footer = require(script.Components.Footer)
local OutputLog = require(script.Components.OutputLog)
local SuggestionList = require(script.Components.SuggestionList)

local Fusion = External.Fusion
local peek = Fusion.peek

type Scope = External.Scope
type Analysis = Completion.Analysis
type Evaluation = Dispatcher.Evaluation
type LogLine = OutputLog.LogLine
type Token = Types.Token

export type MountOptions = {
	read activationKeys: { Enum.KeyCode }?,
	read placeLabel: string?,
	read hideOnFocusLoss: boolean?,
}

export type Controls = {
	read show: () -> (),
	read hide: () -> (),
	read toggle: () -> (),
	read isOpen: () -> boolean,
	read setActivationKeys: (keys: { Enum.KeyCode }) -> (),
	read destroy: () -> (),
}

local Interface = {}

local WORD_CHARS = "[%w_%-]"

local function previousWordBoundary(text: string, cursor: number): number
	local index = cursor - 1
	while index >= 1 and string.match(string.sub(text, index, index), "%s") ~= nil do
		index -= 1
	end
	if index >= 1 and string.match(string.sub(text, index, index), WORD_CHARS) ~= nil then
		while index >= 1 and string.match(string.sub(text, index, index), WORD_CHARS) ~= nil do
			index -= 1
		end
	elseif index >= 1 then
		index -= 1
	end
	return index + 1
end

local function nextWordBoundary(text: string, cursor: number): number
	local index = cursor
	local length = #text
	while index <= length and string.match(string.sub(text, index, index), "%s") ~= nil do
		index += 1
	end
	if index <= length and string.match(string.sub(text, index, index), WORD_CHARS) ~= nil then
		while index <= length and string.match(string.sub(text, index, index), WORD_CHARS) ~= nil do
			index += 1
		end
	elseif index <= length then
		index += 1
	end
	return index
end

function Interface.mount(client: Client.KmdrClient, options: MountOptions?): Controls
	local opts: MountOptions = options or {}
	local activationKeys: { [Enum.KeyCode]: boolean } = {}
	for _, key in opts.activationKeys or { Enum.KeyCode.F2 } do
		activationKeys[key] = true
	end

	local scope: Scope = Fusion.scoped(Fusion)

	-- ── State ──────────────────────────────────────────────────────────
	local open = scope:Value(false)
	local shown = scope:Value(false) -- lags `open` on close so the exit spring plays
	local text = scope:Value("")
	local cursor = scope:Value(1)
	local evaluationState: External.Value<Evaluation?> = scope:Value(nil) :: any
	local analysisState: External.Value<Analysis?> = scope:Value(nil) :: any
	local popupOpen = scope:Value(false)
	local selectedIndex = scope:Value(1)
	local ghost: External.Value<string?> = scope:Value(nil) :: any
	local lines: External.Value<{ LogLine }> = scope:Value({}) :: any
	local viewportWidth = scope:Value(1920)

	local textBox: TextBox? = nil
	local suppressTextEvents = false
	local nextLineId = 0
	local mountTime = os.clock()

	-- History navigation.
	local historyDraft: string? = nil
	local historyList: { string } = {}
	local historyPos: number? = nil

	-- ── Derived state ──────────────────────────────────────────────────
	local base: Dispatcher.EvalBase = {
		realm = "client" :: "client",
		executor = Players.LocalPlayer,
	}

	local function recompute()
		local currentText = peek(text)
		local currentCursor = peek(cursor)
		local evaluation = client.evaluate(currentText)
		evaluationState:set(evaluation)

		local analysis = Completion.compute(client.registry, base, evaluation, currentCursor)
		analysisState:set(analysis)
		selectedIndex:set(1)

		if currentCursor >= #currentText + 1 and #currentText > 0 then
			ghost:set(Completion.ghost(currentText, client.getHistory()))
		else
			ghost:set(nil)
		end

		local items = analysis.items
		local exhausted = #items == 0 or (#items == 1 and items[1].label == analysis.prefix)
		popupOpen:set(not exhausted and #currentText > 0)
	end

	-- Neutral-first mirror: valid command is bright white, invalid red;
	-- the accent is reserved for matched characters and the chevron.
	local mirrorRich = scope:Computed(function(use): string
		local currentText = use(text)
		local evaluation = use(evaluationState)
		local pieces: { string } = {}
		local lastEnd = 0

		if evaluation ~= nil then
			local errorByToken: { [Token]: boolean } = {}
			for _, argEval in evaluation.args do
				if argEval.token ~= nil and argEval.error ~= nil then
					errorByToken[argEval.token] = true
				end
			end
			for index, token in evaluation.tokens do
				if token.startPos > lastEnd + 1 then
					table.insert(pieces, Theme.escape(string.sub(currentText, lastEnd + 1, token.startPos - 1)))
				end
				local raw = Theme.escape(token.rawText)
				local color: Color3
				if index == 1 then
					color = if evaluation.entry ~= nil then Theme.text else Theme.error
				elseif errorByToken[token] then
					color = Theme.error
				elseif token.quoted then
					color = Theme.string
				elseif tonumber(token.text) ~= nil then
					color = Theme.number
				else
					color = Theme.secondary
				end
				table.insert(pieces, Theme.tint(raw, color))
				lastEnd = token.endPos
			end
		end
		if lastEnd < #currentText then
			table.insert(pieces, Theme.escape(string.sub(currentText, lastEnd + 1)))
		end

		local ghostText = use(ghost)
		if ghostText ~= nil then
			table.insert(pieces, Theme.tint(Theme.escape(ghostText), Theme.tertiary))
		end
		return table.concat(pieces)
	end)

	-- ── Text manipulation helpers ──────────────────────────────────────
	local function setLine(newText: string, newCursor: number?)
		local box = textBox
		if box == nil then
			return
		end
		suppressTextEvents = true
		box.Text = newText
		box.CursorPosition = newCursor or (#newText + 1)
		suppressTextEvents = false
		text:set(newText)
		cursor:set(box.CursorPosition)
		recompute()
	end

	local function resetHistoryNav()
		historyPos = nil
		historyDraft = nil
	end

	local function acceptGhost(): boolean
		local ghostText = peek(ghost)
		if ghostText == nil then
			return false
		end
		setLine(peek(text) .. ghostText)
		return true
	end

	local function acceptSuggestion(index: number?): boolean
		local analysis = peek(analysisState)
		if analysis == nil or #analysis.items == 0 then
			return false
		end
		local item = analysis.items[index or peek(selectedIndex)]
		if item == nil then
			return false
		end
		local newText, newCursor = Completion.apply(peek(text), analysis, item)
		setLine(newText, newCursor)
		return true
	end

	local function moveSelection(delta: number)
		local analysis = peek(analysisState)
		if analysis == nil then
			return
		end
		local count = #analysis.items
		if count == 0 then
			return
		end
		local index = peek(selectedIndex) + delta
		if index < 1 then
			index = count
		elseif index > count then
			index = 1
		end
		selectedIndex:set(index)
	end

	local function navigateHistory(delta: number)
		local history = client.getHistory()
		if historyPos == nil then
			if delta > 0 then
				return
			end
			historyDraft = peek(text)
			historyList = {}
			local prefix = historyDraft :: string
			for _, entryText in history do
				if #prefix == 0 or string.sub(entryText, 1, #prefix) == prefix then
					table.insert(historyList, entryText)
				end
			end
			if #historyList == 0 then
				return
			end
			historyPos = #historyList
		else
			local position = (historyPos :: number) + delta
			if position > #historyList then
				local draft = historyDraft or ""
				resetHistoryNav()
				setLine(draft)
				return
			end
			historyPos = math.clamp(position, 1, #historyList)
		end
		local chosen = historyList[historyPos :: number]
		if chosen ~= nil then
			setLine(chosen)
		end
	end

	local function runLine()
		local line = peek(text)
		if #string.gsub(line, "%s", "") == 0 then
			return
		end
		client.run(line)
		resetHistoryNav()
		setLine("")
		popupOpen:set(false)
	end

	-- ── World treatment (blur + dim while open) ────────────────────────
	local blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "KmdrBlur"
	blurEffect.Size = 0
	blurEffect.Enabled = false
	blurEffect.Parent = Lighting

	local dimEffect = Instance.new("ColorCorrectionEffect")
	dimEffect.Name = "KmdrDim"
	dimEffect.Brightness = 0
	dimEffect.Enabled = false
	dimEffect.Parent = Lighting

	-- Slightly longer than the panel slide so the world settles with it.
	local worldTweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Linear)

	local function setWorldTreatment(active: boolean)
		blurEffect.Enabled = true
		dimEffect.Enabled = true
		TweenService:Create(blurEffect, worldTweenInfo, { Size = if active then Theme.worldBlurSize else 0 }):Play()
		TweenService:Create(dimEffect, worldTweenInfo, { Brightness = if active then -Theme.worldDim else 0 }):Play()
		if not active then
			task.delay(0.25, function()
				if not peek(open) then
					blurEffect.Enabled = false
					dimEffect.Enabled = false
				end
			end)
		end
	end

	-- The Roblox topbar sits exactly where the palette drops in; hide it
	-- while the console is open (restored on close/destroy).
	local StarterGui = game:GetService("StarterGui")
	local function setTopbar(visible: boolean)
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", visible)
		end)
	end
	table.insert(scope, function()
		setTopbar(true)
	end)

	table.insert(scope, function()
		blurEffect:Destroy()
		dimEffect:Destroy()
	end)

	-- ── Show/hide ──────────────────────────────────────────────────────
	-- Declared before panel assembly; bound after the position spring exists.
	local parkSpringClosed: () -> () = function() end

	local function show()
		if peek(open) then
			return
		end
		-- Start the slide from fully parked off-screen — reopening mid-close
		-- must not begin from a half-travelled spring (the "landing jitter").
		if not peek(shown) then
			parkSpringClosed()
		end
		open:set(true)
		shown:set(true)
		setWorldTreatment(true)
		setTopbar(false)
		task.defer(function()
			local box = textBox
			if box ~= nil then
				box:CaptureFocus()
			end
		end)
	end

	local function hide()
		if not peek(open) then
			return
		end
		open:set(false)
		popupOpen:set(false)
		setWorldTreatment(false)
		setTopbar(true)
		local box = textBox
		if box ~= nil then
			box:ReleaseFocus(false)
		end
		-- The panel slides its full height off-screen; hide only once the
		-- spring has genuinely left the viewport.
		task.delay(0.45, function()
			if not peek(open) then
				shown:set(false)
			end
		end)
	end

	local function toggle()
		if peek(open) then
			hide()
		else
			show()
		end
	end

	-- ── Components ─────────────────────────────────────────────────────
	local barHandle = Bar(scope, {
		mirrorText = mirrorRich,
		open = open,
		onTextBox = function(box: TextBox)
			textBox = box

			table.insert(
				scope,
				box:GetPropertyChangedSignal("Text"):Connect(function()
					if suppressTextEvents then
						return
					end
					local raw = box.Text
					local cleaned = string.gsub(raw, "[\t\n\r]", "")
					if cleaned ~= raw then
						box.Text = cleaned
						return
					end
					resetHistoryNav()
					text:set(cleaned)
					cursor:set(box.CursorPosition)
					recompute()
				end)
			)

			table.insert(
				scope,
				box:GetPropertyChangedSignal("CursorPosition"):Connect(function()
					if suppressTextEvents or box.CursorPosition < 1 then
						return
					end
					cursor:set(box.CursorPosition)
					recompute()
				end)
			)

			table.insert(
				scope,
				box.FocusLost:Connect(function(enterPressed: boolean)
					if enterPressed then
						runLine()
						task.defer(function()
							if peek(open) then
								box:CaptureFocus()
							end
						end)
					else
						popupOpen:set(false)
					end
				end)
			)
		end,
	})

	local outputLog = OutputLog(scope, {
		lines = lines,
		expanded = open,
	})

	local suggestionList = SuggestionList(scope, {
		analysis = analysisState,
		selectedIndex = selectedIndex,
		open = scope:Computed(function(use)
			return use(open) and use(popupOpen)
		end),
		onAccept = function(index: number)
			acceptSuggestion(index)
			local box = textBox
			if box ~= nil then
				box:CaptureFocus()
			end
		end,
		onHover = function(index: number)
			selectedIndex:set(index)
		end,
	})

	local footer = Footer(scope, {
		signature = scope:Computed(function(use)
			local analysis = use(analysisState)
			return if analysis ~= nil then analysis.signature else nil
		end),
		errorText = scope:Computed(function(use)
			local analysis = use(analysisState)
			return if analysis ~= nil then analysis.errorText else nil
		end),
		placeLabel = opts.placeLabel or "kmdr",
		open = open,
	})

	local hasContent = scope:Computed(function(use)
		return (#use(lines) > 0 and use(open)) or (use(open) and use(popupOpen))
	end)

	-- ── Panel assembly ─────────────────────────────────────────────────
	local panelWidth = scope:Computed(function(use): number
		return math.min(Theme.panelWidth, math.round(use(viewportWidth) * 0.92))
	end)

	-- The closed position is fully off-screen (panel height + shadow room),
	-- so open/close is one continuous slide instead of a nudge-then-pop.
	local panelHeight = scope:Value(240)

	local panelPosition = scope:Computed(function(use)
		local x = math.round((use(viewportWidth) - use(panelWidth)) / 2)
		local y = if use(open) then Theme.panelTopOffset else -(use(panelHeight) + 80)
		return UDim2.fromOffset(x, y)
	end)

	local positionSpring = Motion.layoutSpring(scope, panelPosition)

	parkSpringClosed = function()
		positionSpring:setPosition(peek(panelPosition))
		positionSpring:setVelocity(UDim2.fromOffset(0, 0))
	end

	local divider = function(order: number, visible: any): Frame
		return scope:New("Frame")({
			Name = `Divider{order}`,
			BackgroundColor3 = Theme.hairline,
			BackgroundTransparency = Theme.strokeTransparency,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			LayoutOrder = order,
			Visible = visible,
		}) :: Frame
	end

	local panel = scope:New("Frame")({
		Name = "Panel",
		Position = positionSpring,
		Size = scope:Computed(function(use)
			return UDim2.fromOffset(use(panelWidth), 0)
		end),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.base,
		BackgroundTransparency = Theme.panelTransparency,
		BorderSizePixel = 0,
		Visible = shown,
		[Fusion.Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0, Theme.panelRadius) }),
			scope:New("UIStroke")({
				Color = Theme.hairline,
				Transparency = Theme.strokeTransparency,
			}),
			-- Glass highlight: a faint 1px light line inside the top edge.
			scope:New("Frame")({
				Name = "Sheen",
				BackgroundColor3 = Theme.sheen,
				BackgroundTransparency = Theme.sheenTransparency,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(Theme.panelRadius, 1),
				Size = UDim2.new(1, -Theme.panelRadius * 2, 0, 1),
				ZIndex = 5,
			}),
			-- Layout lives one level down so absolute decorations (sheen)
			-- aren't captured by the list layout.
			scope:New("Frame")({
				Name = "Content",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.fromScale(1, 0),
				[Fusion.Children] = {
					scope:New("UIListLayout")({
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Vertical,
					}),
					barHandle.frame, -- LayoutOrder 1
					divider(2, hasContent),
					suggestionList, -- LayoutOrder 3
					outputLog, -- LayoutOrder 4
					divider(5, true),
					footer, -- LayoutOrder 6
				},
			}),
		},
	}) :: Frame

	-- Soft shadow (native UIShadow, mid-2026). Guarded: degrade gracefully
	-- on clients that don't have the class yet.
	pcall(function()
		local shadow = Instance.new("UIShadow" :: any) :: any
		shadow.BlurRadius = 48
		shadow.Transparency = 0.4
		shadow.Offset = Vector2.new(0, 12)
		shadow.Parent = panel
	end)

	local gui = scope:New("ScreenGui")({
		Name = "Kmdr",
		DisplayOrder = 1000,
		ResetOnSpawn = false,
		-- The topbar is hidden while open; the palette owns the true top edge.
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		[Fusion.Children] = { panel },
	}) :: ScreenGui

	table.insert(
		scope,
		panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			panelHeight:set(panel.AbsoluteSize.Y)
		end)
	)

	-- Track viewport width for integer centering.
	local function updateViewport()
		local camera = workspace.CurrentCamera
		if camera ~= nil then
			viewportWidth:set(camera.ViewportSize.X)
		end
	end
	updateViewport()
	local camera = workspace.CurrentCamera
	if camera ~= nil then
		table.insert(scope, camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateViewport))
	end

	-- ── Output wiring ──────────────────────────────────────────────────
	table.insert(
		scope,
		client.onLine(function(line)
			nextLineId += 1
			local model: LogLine = {
				id = nextLineId,
				text = line.text,
				kind = line.kind,
				animate = os.clock() - mountTime > 0.5,
			}
			local current = table.clone(peek(lines))
			table.insert(current, model)
			while #current > 300 do
				table.remove(current, 1)
			end
			lines:set(current)
		end)
	)

	table.insert(
		scope,
		client.onClear(function()
			lines:set({})
		end)
	)

	-- ── Keyboard state machine ─────────────────────────────────────────
	table.insert(
		scope,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			local key = input.KeyCode

			if activationKeys[key] ~= nil then
				local box = textBox
				local focusedOnUs = box ~= nil and box:IsFocused()
				if not processed or focusedOnUs then
					toggle()
				end
				return
			end

			if not peek(open) then
				return
			end
			local box = textBox
			if box == nil or not box:IsFocused() then
				return
			end

			local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

			if key == Enum.KeyCode.Up then
				if peek(popupOpen) then
					moveSelection(-1)
				else
					navigateHistory(-1)
				end
			elseif key == Enum.KeyCode.Down then
				if peek(popupOpen) then
					moveSelection(1)
				else
					navigateHistory(1)
				end
			elseif key == Enum.KeyCode.Tab then
				if peek(popupOpen) then
					if shift then
						moveSelection(-1)
					else
						acceptSuggestion(nil)
					end
				elseif not acceptGhost() then
					popupOpen:set(true)
				end
			elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.End then
				if peek(cursor) >= #peek(text) + 1 then
					acceptGhost()
				end
			elseif key == Enum.KeyCode.U and ctrl then
				setLine("")
			elseif key == Enum.KeyCode.Backspace and ctrl then
				local currentText = box.Text
				local currentCursor = box.CursorPosition
				local boundary = previousWordBoundary(currentText, currentCursor)
				if boundary < currentCursor then
					local newText = string.sub(currentText, 1, boundary - 1) .. string.sub(currentText, currentCursor)
					task.defer(setLine, newText, boundary)
				end
			elseif (key == Enum.KeyCode.Left or key == Enum.KeyCode.Right) and ctrl then
				local currentText = box.Text
				local currentCursor = box.CursorPosition
				local target = if key == Enum.KeyCode.Left
					then previousWordBoundary(currentText, currentCursor)
					else nextWordBoundary(currentText, currentCursor)
				task.defer(function()
					suppressTextEvents = true
					if shift then
						if box.SelectionStart == -1 then
							box.SelectionStart = currentCursor
						end
					else
						box.SelectionStart = -1
					end
					box.CursorPosition = target
					suppressTextEvents = false
					cursor:set(target)
					recompute()
				end)
			end
		end)
	)

	if opts.hideOnFocusLoss then
		table.insert(scope, UserInputService.WindowFocusReleased:Connect(hide))
	end

	local controls: Controls = {
		show = show,
		hide = hide,
		toggle = toggle,
		isOpen = function()
			return peek(open)
		end,
		setActivationKeys = function(keys: { Enum.KeyCode })
			table.clear(activationKeys)
			for _, key in keys do
				activationKeys[key] = true
			end
		end,
		destroy = function()
			gui:Destroy()
			Fusion.doCleanup(scope)
		end,
	}
	return controls
end

return Interface
