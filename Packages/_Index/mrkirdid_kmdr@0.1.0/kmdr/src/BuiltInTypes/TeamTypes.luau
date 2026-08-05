--!strict
--[[
	TeamTypes.luau — team(s) matched by name (exact case-insensitive, then
	fuzzy) and teamPlayers (a team's current players).
]]

local Teams = game:GetService("Teams")

local Define = require(script.Parent.Parent.Define)
local Types = require(script.Parent.Parent.Types)
local Util = require(script.Parent.Parent.Util)

type ArgContext = Types.ArgContext
type Resolution<T> = Types.Resolution<T>

-- `Define.err`'s payload type only appears in its return type, which the new
-- solver cannot infer from the surrounding context — pin it per payload.
type Err<T> = (message: string, suggestions: { string }?) -> Resolution<T>
local errTeam = Define.err :: Err<Team>
local errPlayerList = Define.err :: Err<{ Player }>

local function resolveTeam(text: string): Resolution<Team>
	local teams = Teams:GetTeams()
	local names: { string } = {}
	for _, team in teams do
		table.insert(names, team.Name)
	end

	if text == "" then
		return errTeam("Enter a team name", names)
	end

	local lowered = string.lower(text)
	for _, team in teams do
		if string.lower(team.Name) == lowered then
			return Define.ok(team)
		end
	end

	local suggestions = Util.fuzzyFilter(text, names)
	local bestName = suggestions[1]
	if bestName ~= nil then
		for _, team in teams do
			if team.Name == bestName then
				return Define.ok(team, suggestions)
			end
		end
	end
	return errTeam(`No team matching '{text}'`, suggestions)
end

local teamType = Define.defineType({
	name = "team",
	resolve = function(text: string, _ctx: ArgContext): Resolution<Team>
		return resolveTeam(text)
	end,
})

local teamPlayersType = Define.defineType({
	name = "teamPlayers",
	resolve = function(text: string, _ctx: ArgContext): Resolution<{ Player }>
		local resolution = resolveTeam(text)
		if not resolution.ok then
			return errPlayerList(resolution.error, resolution.suggestions)
		end
		return Define.ok(resolution.value:GetPlayers(), resolution.suggestions)
	end,
})

return {
	team = teamType,
	teams = Define.listOf(teamType, "teams"),
	teamPlayers = teamPlayersType,
}
