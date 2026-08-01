-- Kore.Net.RateLimit — Per-remote rate limiting

local Log = require(script.Parent.Parent.Log)
local Types = require(script.Parent.Parent.Types)

type RateLimitTracker = {
	count: number,
	resetTime: number,
}

local RateLimit = {}

local trackers: { [string]: { [number]: RateLimitTracker } } = {} -- [remoteName] = { [userId] = tracker }

--- Check whether a remote call from `player` is within the rate limit.
--- Returns `true` if the call is allowed, `false` if it should be dropped.
function RateLimit.Check(remoteName: string, player: Player, config: Types.RateLimitConfig?): boolean
	if not config then
		return true
	end

	local maxCalls: number = (config :: Types.RateLimitConfig).MaxCalls
	local perSeconds: number = (config :: Types.RateLimitConfig).PerSeconds

	if not maxCalls or not perSeconds then
		return true
	end

	if not trackers[remoteName] then
		trackers[remoteName] = {}
	end

	local playerKey: number = player.UserId
	local tracker: RateLimitTracker? = trackers[remoteName][playerKey]
	local now: number = os.clock()

	if not tracker or now >= (tracker :: RateLimitTracker).resetTime then
		trackers[remoteName][playerKey] = {
			count = 1,
			resetTime = now + perSeconds,
		}
		return true
	end

	(tracker :: RateLimitTracker).count += 1
	if (tracker :: RateLimitTracker).count > maxCalls then
		Log.Debug(
			"Kore.Net",
			"Rate limit exceeded for '%s' by %s (%d/%d in %.1fs)",
			remoteName,
			player.Name,
			(tracker :: RateLimitTracker).count,
			maxCalls,
			perSeconds
		)
		return false
	end

	return true
end

--- Remove all rate-limit tracking data for a player (call on PlayerRemoving).
function RateLimit.ClearPlayer(player: Player): ()
	local playerKey: number = player.UserId
	for _, remoteTrackers in pairs(trackers) do
		remoteTrackers[playerKey] = nil
	end
end

return RateLimit
