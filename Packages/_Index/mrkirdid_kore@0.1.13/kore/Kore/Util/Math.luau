-- Kore.Util.Math — Math utilities

local Types = require(script.Parent.Parent.Types)

local Math = {}

--- Linearly interpolate between `a` and `b` by factor `t`.
function Math.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Clamp `value` between `min` and `max`.
function Math.clamp(value: number, min: number, max: number): number
	return math.clamp(value, min, max)
end

--- Round `value` to the given number of `decimals` (default: nearest integer).
function Math.round(value: number, decimals: number?): number
	if decimals then
		local mult: number = 10 ^ decimals
		return math.round(value * mult) / mult
	end
	return math.round(value)
end

--- Map `value` from the input range `[inMin, inMax]` to the output range `[outMin, outMax]`.
function Math.map(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin)
end

--- Snap `value` to the nearest multiple of `step`.
function Math.snap(value: number, step: number): number
	return math.round(value / step) * step
end

--- Return the sign of `value`: `1`, `-1`, or `0`.
function Math.sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

--- Return a random floating-point number in `[min, max)`.
function Math.randomRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

--- Move `current` toward `target` by at most `step`.
function Math.approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(current + step, target)
	elseif current > target then
		return math.max(current - step, target)
	end
	return current
end

--- Exponential decay interpolation (frame-rate independent smoothing).
function Math.damp(a: number, b: number, smoothing: number, dt: number): number
	return Math.lerp(a, b, 1 - smoothing ^ dt)
end

--- Evaluate a cubic Bézier curve at parameter `t` with control points `p0`–`p3`.
function Math.bezier(t: number, p0: number, p1: number, p2: number, p3: number): number
	local u: number = 1 - t
	local tt: number = t * t
	local uu: number = u * u
	local uuu: number = uu * u
	local ttt: number = tt * t

	return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3
end

return Math :: Types.MathUtil
