--!strict
--[[
	PlayerTypes.luau — player and players (selector operators), plus playerId(s):
	raw UserIds with no name lookup (that would yield, and resolve never yields).

	player selectors: "." / "me" (executor), "?" / "random", "@name" (exact Name).
	players adds:     "*" / "all", "**" / "others", "?" (one random), "?N".
]]

local Players = game:GetService("Players")

local Define = require(script.Parent.Parent.Define)
local Parser = require(script.Parent.Parent.Parser)
local Types = require(script.Parent.Parent.Types)
local Util = require(script.Parent.Parent.Util)

type ArgContext = Types.ArgContext
type Resolution<T> = Types.Resolution<T>

-- `Define.err`'s payload type only appears in its return type, which the new
-- solver cannot infer from the surrounding context — pin it per payload.
type Err<T> = (message: string, suggestions: { string }?) -> Resolution<T>
local errPlayer = Define.err :: Err<Player>
local errPlayerList = Define.err :: Err<{ Player }>
local errUserId = Define.err :: Err<number>

--[[
	Snapshot of the online players, rebuilt per resolve call (cheap — resolve
	runs per keystroke, not per frame). Names index before display names so an
	exact Name always beats a DisplayName collision; `byCandidate` is keyed by
	lowercase candidate text.
]]
type PlayerIndex = {
	players: { Player },
	names: { string },
	candidates: { string },
	byCandidate: { [string]: Player },
}

local function buildIndex(): PlayerIndex
	local players = Players:GetPlayers()
	local names: { string } = {}
	local candidates: { string } = {}
	local byCandidate: { [string]: Player } = {}
	for _, player in players do
		table.insert(names, player.Name)
		local key = string.lower(player.Name)
		if byCandidate[key] == nil then
			byCandidate[key] = player
			table.insert(candidates, player.Name)
		end
	end
	for _, player in players do
		local key = string.lower(player.DisplayName)
		if byCandidate[key] == nil then
			byCandidate[key] = player
			table.insert(candidates, player.DisplayName)
		end
	end
	return { players = players, names = names, candidates = candidates, byCandidate = byCandidate }
end

--- Fuzzy matches over Names + DisplayNames, mapped back to unique player Names.
local function fuzzyNames(text: string, index: PlayerIndex): { string }
	local names: { string } = {}
	local seen: { [Player]: boolean } = {}
	for _, candidate in Util.fuzzyFilter(text, index.candidates) do
		local player = index.byCandidate[string.lower(candidate)]
		if player ~= nil and not seen[player] then
			seen[player] = true
			table.insert(names, player.Name)
		end
	end
	return names
end

local function resolvePlayer(text: string, ctx: ArgContext): Resolution<Player>
	local index = buildIndex()

	if text == "" then
		return errPlayer("Enter a player name", index.names)
	end

	local lowered = string.lower(text)
	if text == "." or lowered == "me" then
		local executor = ctx.executor
		if executor == nil then
			return errPlayer("No executor to resolve 'me'")
		end
		return Define.ok(executor)
	end
	if text == "?" or lowered == "random" then
		if #index.players == 0 then
			return errPlayer("No players online")
		end
		return Define.ok(index.players[math.random(#index.players)])
	end
	if string.sub(text, 1, 1) == "@" then
		local name = string.sub(text, 2)
		for _, player in index.players do
			if player.Name == name then
				return Define.ok(player)
			end
		end
		return errPlayer(`No player named '{name}'`, Util.fuzzyFilter(name, index.names))
	end

	local exact = index.byCandidate[lowered]
	if exact ~= nil then
		return Define.ok(exact)
	end

	local suggestions = fuzzyNames(text, index)
	local bestName = suggestions[1]
	if bestName ~= nil then
		local best = index.byCandidate[string.lower(bestName)]
		if best ~= nil then
			return Define.ok(best, suggestions)
		end
	end
	return errPlayer(`No player matching '{text}'`, suggestions)
end

local playerType = Define.defineType({
	name = "player",
	resolve = resolvePlayer,
})

local function appendUnique(values: { Player }, seen: { [Player]: boolean }, player: Player)
	if not seen[player] then
		seen[player] = true
		table.insert(values, player)
	end
end

-- Custom (not listOf): comma segments support the selector operators above,
-- so the plain element resolver alone could not express them.
local playersType = Define.defineType({
	name = "players",
	resolve = function(_text: string, ctx: ArgContext): Resolution<{ Player }>
		local values: { Player } = {}
		local seen: { [Player]: boolean } = {}
		local lastSuggestions: { string }? = nil

		for _, segment in Parser.splitList(ctx.rawToken) do
			lastSuggestions = nil
			local lowered = string.lower(segment)
			if segment == "*" or lowered == "all" then
				for _, player in Players:GetPlayers() do
					appendUnique(values, seen, player)
				end
			elseif segment == "**" or lowered == "others" then
				for _, player in Players:GetPlayers() do
					if player ~= ctx.executor then
						appendUnique(values, seen, player)
					end
				end
			elseif segment == "?" or string.match(segment, "^%?%d+$") ~= nil then
				local count = if segment == "?" then 1 else tonumber(string.sub(segment, 2)) :: number
				if count < 1 then
					return errPlayerList(`'{segment}' must pick at least one player`)
				end
				local pool = Players:GetPlayers()
				if #pool == 0 then
					return errPlayerList("No players online")
				end
				-- Partial Fisher–Yates: the first `count` slots become the sample.
				for slot = 1, math.min(count, #pool) do
					local pick = math.random(slot, #pool)
					pool[slot], pool[pick] = pool[pick], pool[slot]
					appendUnique(values, seen, pool[slot])
				end
			else
				local resolution = resolvePlayer(segment, ctx)
				if not resolution.ok then
					return errPlayerList(resolution.error, resolution.suggestions)
				end
				appendUnique(values, seen, resolution.value)
				lastSuggestions = resolution.suggestions
			end
		end
		return Define.ok(values, lastSuggestions)
	end,
})

local playerIdType = Define.defineType({
	name = "playerId",
	resolve = function(text: string, _ctx: ArgContext): Resolution<number>
		local value = tonumber(text)
		if value == nil or value ~= math.floor(value) or value <= 0 then
			return errUserId(`'{text}' is not a UserId (positive integer)`)
		end
		return Define.ok(value)
	end,
})

return {
	player = playerType,
	players = playersType,
	playerId = playerIdType,
	playerIds = Define.listOf(playerIdType, "playerIds"),
}
