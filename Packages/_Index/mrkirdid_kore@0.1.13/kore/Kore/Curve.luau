-- Kore.Curve — Keyframe curve sampler for animation, VFX, and time-based values

local Types = require(script.Parent.Types)

type Keyframe = Types.Keyframe
type CurveInstance = Types.CurveInstance

local Curve = {}
Curve.__index = Curve

--- Create a new curve from a list of keyframes. Keyframes are sorted by `t` automatically.
function Curve.new(keyframes: { Keyframe }): CurveInstance
	local sorted: { Keyframe } = table.clone(keyframes)
	table.sort(sorted, function(a: Keyframe, b: Keyframe): boolean
		return a.t < b.t
	end)

	return setmetatable({
		_keyframes = sorted,
	}, Curve) :: any
end

--- Sample the curve at time `t` using linear interpolation between surrounding keyframes.
function Curve:Sample(t: number): number
	local keyframes: { Keyframe } = self._keyframes
	local count: number = #keyframes

	if count == 0 then
		return 0
	end

	if count == 1 then
		return keyframes[1].v
	end

	-- Clamp to range
	if t <= keyframes[1].t then
		return keyframes[1].v
	end

	if t >= keyframes[count].t then
		return keyframes[count].v
	end

	-- Find surrounding keyframes
	for i = 1, count - 1 do
		local kf0: Keyframe = keyframes[i]
		local kf1: Keyframe = keyframes[i + 1]

		if t >= kf0.t and t <= kf1.t then
			local alpha: number = (t - kf0.t) / (kf1.t - kf0.t)
			return kf0.v + (kf1.v - kf0.v) * alpha
		end
	end

	return keyframes[count].v
end

--- Sample the curve at time `t` using Catmull-Rom cubic interpolation.
--- Falls back to linear `Sample()` if fewer than 4 keyframes.
function Curve:SampleSmooth(t: number): number
	local keyframes: { Keyframe } = self._keyframes
	local count: number = #keyframes

	if count < 4 then
		return self:Sample(t)
	end

	if t <= keyframes[1].t then
		return keyframes[1].v
	end

	if t >= keyframes[count].t then
		return keyframes[count].v
	end

	for i = 1, count - 1 do
		local kf1: Keyframe = keyframes[i]
		local kf2: Keyframe = keyframes[i + 1]

		if t >= kf1.t and t <= kf2.t then
			local alpha: number = (t - kf1.t) / (kf2.t - kf1.t)
			local p0: number = keyframes[math.max(1, i - 1)].v
			local p1: number = kf1.v
			local p2: number = kf2.v
			local p3: number = keyframes[math.min(count, i + 2)].v

			-- Catmull-Rom
			local a: number = 2 * p1
			local b: number = p2 - p0
			local c: number = 2 * p0 - 5 * p1 + 4 * p2 - p3
			local d: number = -p0 + 3 * p1 - 3 * p2 + p3
			return 0.5 * (a + b * alpha + c * alpha * alpha + d * alpha * alpha * alpha)
		end
	end

	return keyframes[count].v
end

return Curve :: Types.CurveModule
