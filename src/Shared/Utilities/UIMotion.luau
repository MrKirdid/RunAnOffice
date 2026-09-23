--> A panel pops on a UIScale rather than on its own Size. Every screen in this game is built in
--> the place with its own list layouts and aspect constraints, and driving Size fights all of it.
--> A UIScale multiplies the whole subtree and nothing inside has to know it is being animated.
local ScaleName = "UIMotionScale"

local ShutScale = 0.4
local OpenScale = 1

--> Where the close is aimed, which is well past gone. A spring eases into whatever it is heading
--> for, so a close aimed at the size it stops at spends its last frames barely moving and is then
--> switched off mid air -- a panel that despawns rather than leaves. Aimed at this instead, zero is
--> crossed while it is still travelling, and what the eye sees is one movement out to nothing.
--> The scale shown is clamped at zero, since a negative one turns the panel inside out.
local ExitScale = -2

--> opening is the pair the hex nodes land on, so a panel arriving and a node arriving read as the
--> same hand: one overshoot, then settle.
--> Loosened and slowed from where it was. At 0.7 the panel arrived correctly but flat: it reached
--> the mark and stopped, which is a placement rather than a landing. What reads as bounce is the
--> first overshoot, not the tail, so the damping comes down and the punch goes up together -- a
--> bigger throw past the mark rather than a longer wobble at the end. An earlier pass at 0.58 crept
--> because the punch was left alone and the whole change went into the tail.
local OpenSpeed = 23
local OpenDamping = 0.5

--> closing is critically damped, and slow, because it is now travelling much further than it used
--> to. an undershooting close springs back up before the screen is switched off, which reads as the
--> panel opening again on its way out
local ShutSpeed = 5.5
local ShutDamping = 1

--> the kick on the way in. without it the panel grows rather than pops, and it is what sets how far
--> past the mark the first overshoot goes -- the part of the bounce that is actually watched
local Punch = 2.6

--> fades are always critically damped: transparency clamps at 0 and 1, so an overshoot is not a
--> bounce, it is a frame of nothing.
--> In is deliberately the slower of the two. A backdrop that lands before the thing it sits behind
--> is a black screen with nothing on it, so it darkens at about the rate the content arrives.
local FadeInSpeed = 16

--> Out is slow on purpose too. A backdrop that lifts in a tenth of a second leaves whatever it was
--> behind folding away over the bare world, so it comes up at about the rate the content leaves.
local FadeOutSpeed = 11
local FadeDamping = 1

--> how long the shut spring is given before the screen is switched off underneath it. aimed at
--> ExitScale at ShutSpeed, a panel crosses zero at about 0.22s, so by here there is nothing left on
--> screen to cut off
local ShutTime = 0.3

export type Handle = {
	Show: () -> (),
	Hide: () -> (),
}

local UIMotion = {
	ShutTime = ShutTime,
}

local function GetScale(Frame: GuiObject): UIScale
	local Existing = Frame:FindFirstChild(ScaleName)

	if Existing and Existing:IsA("UIScale") then
		return Existing
	end

	local Scale = Instance.new("UIScale")
	Scale.Name = ScaleName
	Scale.Scale = ShutScale
	Scale.Parent = Frame

	return Scale
end

--> The scope is the caller's: a screen thrown away on respawn takes its springs with it when the
--> scope it was attached under is cleaned up.
function UIMotion.Attach(Scope: any, Frame: GuiObject): Handle
	local Goal = Scope:Value(ShutScale)

	--> the character of the motion is part of its direction: a spring reads both of these every
	--> step, so retargeting mid-flight picks up the new feel with it
	local Speed = Scope:Value(ShutSpeed)
	local Damping = Scope:Value(ShutDamping)
	local Motion = Scope:Spring(Goal, Speed, Damping)

	Scope:Hydrate(GetScale(Frame))({
		Scale = Scope:Computed(function(Use)
			return math.max(Use(Motion), 0)
		end),
	})

	local function Show()
		--> put back on the shelf before it is opened. the close runs the spring well below zero, and
		--> without this a reopen would spend its first frames climbing back up to visible
		Motion:setPosition(ShutScale)

		Speed:set(OpenSpeed)
		Damping:set(OpenDamping)
		Goal:set(OpenScale)
		Motion:addVelocity(Punch)
	end

	local function Hide()
		Speed:set(ShutSpeed)
		Damping:set(ShutDamping)
		Goal:set(ExitScale)
	end

	return {
		Show = Show,
		Hide = Hide,
	}
end

--> A backdrop fading rather than popping, for a screen that fills the display instead of sitting
--> in the middle of it. Whatever transparency the frame was built with is the value it fades back
--> to, so the art stays the art and nothing here needs to know what it was set to.
function UIMotion.Fade(Scope: any, Object: GuiObject, Dim: number?): Handle
	--> Dim is how dark it gets to sit at. Left out, the frame keeps whatever it was built with.
	local Shown = Dim or Object.BackgroundTransparency
	local Goal = Scope:Value(1)
	local Speed = Scope:Value(FadeInSpeed)
	local Motion = Scope:Spring(Goal, Speed, FadeDamping)

	Scope:Hydrate(Object)({
		BackgroundTransparency = Motion,
	})

	local function Show()
		Speed:set(FadeInSpeed)
		Goal:set(Shown)
	end

	local function Hide()
		Speed:set(FadeOutSpeed)
		Goal:set(1)
	end

	return {
		Show = Show,
		Hide = Hide,
	}
end

return UIMotion
