--!strict
--[[
	Completion.luau — pure computation behind the suggestion popup, signature
	help and inline validation. Cursor-aware: the token under the caret is what
	gets completed, and only that token's span is replaced on accept.
]]

local Dispatcher = require(script.Parent.Parent.Dispatcher)
local Parser = require(script.Parent.Parent.Parser)
local Registry = require(script.Parent.Parent.Registry)
local Types = require(script.Parent.Parent.Types)
local Util = require(script.Parent.Parent.Util)

type ArgContext = Types.ArgContext
type Evaluation = Dispatcher.Evaluation
type RegistryType = Registry.Registry
type Token = Types.Token

local MAX_ITEMS = 24

local Completion = {}

export type CompletionItem = {
	read label: string,
	--- Exact text spliced into the line (quoted when necessary).
	read insertText: string,
	read detail: string?,
}

export type SignatureArg = {
	read label: string,
	read typeName: string,
	read active: boolean,
	read optional: boolean,
	read summary: string?,
}

export type Signature = {
	read name: string,
	read args: { SignatureArg },
}

export type Analysis = {
	read items: { CompletionItem },
	--- Character span (1-based, inclusive) replaced when accepting an item.
	--- start > end means "insert at start" (empty slot).
	read replaceStart: number,
	read replaceEnd: number,
	--- The prefix being completed — the popup highlights matched characters.
	read prefix: string,
	read signature: Signature?,
	read errorText: string?,
	--- 1 = command token, 2+ = argument slots.
	read slotIndex: number,
}

--- Finds the last comma split point in a raw token (ignoring quoted commas).
local function lastListSplit(rawText: string): number?
	local inQuotes = false
	local last: number? = nil
	local index = 1
	while index <= #rawText do
		local char = string.sub(rawText, index, index)
		if char == "\\" and inQuotes then
			index += 2
			continue
		end
		if char == '"' then
			inQuotes = not inQuotes
		elseif char == "," and not inQuotes then
			last = index
		end
		index += 1
	end
	return last
end

function Completion.compute(
	registry: RegistryType,
	base: Dispatcher.EvalBase,
	evaluation: Evaluation,
	cursor: number
): Analysis
	local location = Parser.locate(evaluation.tokens, cursor)
	local token = location.token
	local prefix = if token ~= nil then token.text else ""
	local replaceStart = if token ~= nil then token.startPos else cursor
	local replaceEnd = if token ~= nil then token.endPos else cursor - 1

	local items: { CompletionItem } = {}
	local signature: Signature? = nil

	if location.index == 1 then
		-- Completing the command name.
		local names = registry.getNames(true)
		local matches = Util.fuzzyFilter(prefix, names)
		for _, name in matches do
			if #items >= MAX_ITEMS then
				break
			end
			local entry = registry.getEntry(name)
			table.insert(items, {
				label = name,
				insertText = name,
				detail = if entry ~= nil then entry.meta.description else nil,
			})
		end
	else
		local entry = evaluation.entry
		if entry ~= nil then
			local specs = registry.argSpecsFor(entry)
			local argIndex = location.index - 1
			local spec = specs[argIndex]

			-- Signature help with the active argument marked.
			local signatureArgs: { SignatureArg } = {}
			for index, argSpec in specs do
				table.insert(signatureArgs, {
					label = argSpec.key,
					typeName = argSpec.displayName,
					active = index == argIndex,
					optional = argSpec.isOptional or argSpec.hasDefault,
					summary = argSpec.summary,
				})
			end
			signature = { name = entry.name, args = signatureArgs }

			if spec ~= nil and spec.spec ~= nil then
				local typeSpec = spec.spec :: Types.ErasedTypeSpec
				local suggestPrefix = prefix
				local rawToken = if token ~= nil then token.rawText else ""

				-- For list types, complete only the last comma segment.
				if typeSpec.listElement ~= nil and token ~= nil then
					local split = lastListSplit(token.rawText)
					if split ~= nil then
						replaceStart = token.startPos + split
						suggestPrefix = string.sub(token.rawText, split + 1)
						rawToken = suggestPrefix
					end
				end

				local argCtx: ArgContext = {
					realm = base.realm,
					executor = base.executor,
					registry = registry,
					rawText = evaluation.text,
					rawToken = rawToken,
					argKey = spec.key,
				}
				local okCall, resolution = pcall(typeSpec.resolve, suggestPrefix, argCtx)
				if okCall then
					local suggestions = resolution.suggestions
					if suggestions ~= nil then
						for _, suggestion in suggestions do
							if #items >= MAX_ITEMS then
								break
							end
							table.insert(items, {
								label = suggestion,
								insertText = Util.quoteIfNeeded(suggestion),
								detail = spec.displayName,
							})
						end
					end
				end
				prefix = suggestPrefix
			end
		end
	end

	return {
		items = items,
		replaceStart = replaceStart,
		replaceEnd = replaceEnd,
		prefix = prefix,
		signature = signature,
		errorText = evaluation.firstError,
		slotIndex = location.index,
	}
end

--[=[
	Applies a completion: returns the new line text and the cursor position
	just after the inserted text.
]=]
function Completion.apply(text: string, analysis: Analysis, item: CompletionItem): (string, number)
	local before = string.sub(text, 1, analysis.replaceStart - 1)
	local after = string.sub(text, analysis.replaceEnd + 1)
	-- Add a trailing space when completing into the end of the line, so the
	-- next argument is immediately ready to type.
	local suffix = if after == "" then " " else ""
	local newText = `{before}{item.insertText}{suffix}{after}`
	local newCursor = #before + #item.insertText + #suffix + 1
	return newText, newCursor
end

--[=[
	Fish-style ghost suggestion: the most recent history entry starting with
	the current line (case-sensitive, must extend it). Returns the remainder.
]=]
function Completion.ghost(text: string, history: { string }): string?
	if #text == 0 then
		return nil
	end
	for index = #history, 1, -1 do
		local candidate = history[index]
		if #candidate > #text and string.sub(candidate, 1, #text) == text then
			return string.sub(candidate, #text + 1)
		end
	end
	return nil
end

return Completion
