--!strict
--[[
	Util.luau — small shared helpers. The fuzzy scorer lives here: scored
	subsequence matching (VS Code style) with word-boundary and consecutiveness
	bonuses, prefix-first so exact prefixes never lose to fuzzy noise.
]]

local Util = {}

local PREFIX_BONUS = 1000
local WORD_START_BONUS = 12
local CONSECUTIVE_BONUS = 8
local GAP_PENALTY = 1

local function isWordStart(candidate: string, index: number): boolean
	if index == 1 then
		return true
	end
	local prev = string.sub(candidate, index - 1, index - 1)
	if prev == "-" or prev == "_" or prev == " " or prev == "." then
		return true
	end
	-- camelCase boundary
	local char = string.sub(candidate, index, index)
	return string.match(char, "%u") ~= nil and string.match(prev, "%l") ~= nil
end

--[=[
	Scores `query` against `candidate`. Returns nil when query is not a
	(case-insensitive) subsequence. Higher is better. Empty queries score 0.
]=]
function Util.fuzzyScore(query: string, candidate: string): number?
	if #query == 0 then
		return 0
	end
	if #query > #candidate then
		return nil
	end

	local queryLower = string.lower(query)
	local candidateLower = string.lower(candidate)

	if string.sub(candidateLower, 1, #queryLower) == queryLower then
		return PREFIX_BONUS + (#queryLower * CONSECUTIVE_BONUS) - #candidate
	end

	local score = 0
	local candidateIndex = 1
	local previousMatch = 0

	for queryIndex = 1, #queryLower do
		local queryChar = string.sub(queryLower, queryIndex, queryIndex)
		local found: number? = nil
		while candidateIndex <= #candidateLower do
			if string.sub(candidateLower, candidateIndex, candidateIndex) == queryChar then
				found = candidateIndex
				break
			end
			candidateIndex += 1
		end
		if found == nil then
			return nil
		end

		if isWordStart(candidate, found) then
			score += WORD_START_BONUS
		end
		if previousMatch ~= 0 and found == previousMatch + 1 then
			score += CONSECUTIVE_BONUS
		end
		if previousMatch ~= 0 then
			score -= math.min(found - previousMatch - 1, 10) * GAP_PENALTY
		end

		previousMatch = found
		candidateIndex = found + 1
	end

	return score - #candidate
end

export type ScoredMatch = {
	read text: string,
	read score: number,
}

--[=[
	Filters and ranks candidates against a query, best first.
	Ties break alphabetically for stable menus.
]=]
function Util.fuzzyFilter(query: string, candidates: { string }): { string }
	local matches: { ScoredMatch } = {}
	for _, candidate in candidates do
		local score = Util.fuzzyScore(query, candidate)
		if score ~= nil then
			table.insert(matches, { text = candidate, score = score })
		end
	end
	table.sort(matches, function(a: ScoredMatch, b: ScoredMatch)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.text < b.text
	end)
	local result: { string } = table.create(#matches) :: any
	for _, match in matches do
		table.insert(result, match.text)
	end
	return result
end

--[=[
	Longest common prefix of a non-empty candidate list — used for
	tab-completing to the unambiguous part.
]=]
function Util.commonPrefix(candidates: { string }): string
	local first = candidates[1]
	if first == nil then
		return ""
	end
	local limit = #first
	for index = 2, #candidates do
		local other = candidates[index]
		local shared = 0
		for charIndex = 1, math.min(limit, #other) do
			if
				string.lower(string.sub(first, charIndex, charIndex))
				== string.lower(string.sub(other, charIndex, charIndex))
			then
				shared = charIndex
			else
				break
			end
		end
		limit = shared
		if limit == 0 then
			return ""
		end
	end
	return string.sub(first, 1, limit)
end

--[=[
	Quotes a value for reinsertion into a command line when needed.
]=]
function Util.quoteIfNeeded(value: string): string
	if value == "" or string.find(value, '[%s"]') ~= nil then
		return `"{string.gsub(value, '(["\\])', "\\%1")}"`
	end
	return value
end

return Util
