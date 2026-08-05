--!nonstrict
-- Nonstrict: see Interface/init.luau — Fusion 0.3 vs new-solver inference.
--[[
	Motion.luau — the animation vocabulary of the console.

	House rules (deliberate, keep them):
	- Springs move things (position, size): critically damped, short, no bounce.
	- Transparency NEVER springs — linear tweens only.
	- Text arrives with typewriter reveals (MaxVisibleGraphemes — cheap) or,
	  for short accent strings, per-letter staggered rise+fade.
]]

local RunService = game:GetService("RunService")

local External = require(script.Parent.Parent.External)
local Theme = require(script.Parent.Theme)

local Fusion = External.Fusion

type Scope = External.Scope
type UsedAs<T> = External.UsedAs<T>

local Motion = {}

local LINEAR = Enum.EasingStyle.Linear

--- Critically-damped layout spring (open/close, panel growth).
function Motion.layoutSpring<T>(scope: Scope, goal: UsedAs<T>): External.Spring<T>
	return scope:Spring(goal, Theme.springSpeedLayout, 1)
end

--- Popup-size spring.
function Motion.popupSpring<T>(scope: Scope, goal: UsedAs<T>): External.Spring<T>
	return scope:Spring(goal, Theme.springSpeedPopup, 1)
end

--- Snappy spring (selection highlight slide, small risers).
function Motion.snappySpring<T>(scope: Scope, goal: UsedAs<T>): External.Spring<T>
	return scope:Spring(goal, Theme.springSpeedSnappy, 1)
end

--- Linear fade for any transparency-like number.
function Motion.fade(scope: Scope, goal: UsedAs<number>, duration: number?): External.Tween<number>
	return scope:Tween(goal, TweenInfo.new(duration or Theme.fadeDuration, LINEAR))
end

export type Typewriter = {
	--- Bind to MaxVisibleGraphemes.
	read visible: External.Value<number>,
	--- Reveals a new string from zero (counts graphemes itself).
	read play: (text: string) -> (),
	--- Snaps the current reveal to completion.
	read skip: () -> (),
}

local function countGraphemes(text: string): number
	-- Rich text tags shouldn't count; the console feeds plain text here.
	local count = 0
	local okIter = pcall(function()
		for _ in utf8.graphemes(text) do
			count += 1
		end
	end)
	if not okIter then
		count = #text
	end
	return count
end

--[=[
	Creates a typewriter driver for one text object. Imperative on purpose:
	a RenderStepped stepper beats reactive graphs for a monotone counter.
	The connection lives in the scope and dies with it.
]=]
function Motion.typewriter(scope: Scope): Typewriter
	local visible = scope:Value(-1)
	local target = 0
	local progress = 0
	local connection: RBXScriptConnection? = nil

	local function stop()
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
	end

	local function play(text: string)
		stop()
		target = countGraphemes(text)
		if target == 0 then
			visible:set(-1)
			return
		end
		local speed = math.max(Theme.typewriterSpeed, target / Theme.typewriterMaxDuration)
		progress = 0
		visible:set(0)
		connection = RunService.RenderStepped:Connect(function(dt: number)
			progress += dt * speed
			if progress >= target then
				visible:set(-1) -- -1 shows everything; robust against later edits
				stop()
			else
				visible:set(math.floor(progress))
			end
		end)
	end

	local function skip()
		stop()
		visible:set(-1)
	end

	table.insert(scope, stop)
	return { visible = visible, play = play, skip = skip }
end

export type PerLetterProps = {
	read text: UsedAs<string>,
	read color: UsedAs<Color3>,
	read textSize: number?,
	read font: Font?,
}

--[=[
	Short accent text where each letter rises 3 px and fades in, staggered.
	Works with proportional fonts: a horizontal list of auto-sized letter
	cells, each animating an inner label. Falls back to a single cell beyond
	Theme.perLetterLimit graphemes.
]=]
function Motion.perLetterText(scope: Scope, props: PerLetterProps): Frame
	local textSize = props.textSize or Theme.rowTitleSize
	local font = props.font or Theme.fontSans
	local cellHeight = math.round(textSize * 1.4)

	local graphemes = scope:Computed(function(use): { string }
		local text = use(props.text)
		local list: { string } = {}
		if countGraphemes(text) > Theme.perLetterLimit then
			-- Sentinel: single "grapheme" holding everything → plain reveal.
			return { text }
		end
		local okIter = pcall(function()
			for first, last in utf8.graphemes(text) do
				table.insert(list, string.sub(text, first, last))
			end
		end)
		if not okIter then
			for index = 1, #text do
				table.insert(list, string.sub(text, index, index))
			end
		end
		return list
	end)

	return scope:New("Frame")({
		Name = "PerLetterText",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, cellHeight),
		[Fusion.Children] = {
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			scope:ForPairs(graphemes, function(_use, letterScope: Scope, index: number, letter: string)
				local risen = letterScope:Value(false)
				local offsetGoal = letterScope:Computed(function(useInner)
					return if useInner(risen) then UDim2.fromOffset(0, 0) else UDim2.fromOffset(0, 3)
				end)
				local fadeGoal = letterScope:Computed(function(useInner)
					return if useInner(risen) then 0 else 1
				end)

				task.delay((index - 1) * Theme.perLetterStagger, function()
					risen:set(true)
				end)

				local cell = letterScope:New("Frame")({
					Name = `L{index}`,
					BackgroundTransparency = 1,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, cellHeight),
					LayoutOrder = index,
					[Fusion.Children] = {
						letterScope:New("TextLabel")({
							Name = "Glyph",
							BackgroundTransparency = 1,
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromOffset(0, cellHeight),
							Position = Motion.snappySpring(letterScope, offsetGoal),
							Text = letter,
							TextColor3 = props.color,
							TextTransparency = Motion.fade(letterScope, fadeGoal, Theme.fadeDurationFast),
							TextSize = textSize,
							FontFace = font,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					},
				})
				return index, cell
			end),
		},
	}) :: Frame
end

return Motion
