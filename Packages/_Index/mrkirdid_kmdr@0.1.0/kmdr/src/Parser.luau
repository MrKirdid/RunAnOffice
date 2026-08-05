--!strict
--[[
	Parser.luau — quote-aware tokenizer that records exact character spans.

	Spans (1-based, inclusive) are load-bearing: cursor-aware completion,
	signature help and inline error tinting all map text positions to tokens.

	Rules:
	- Tokens split on unquoted whitespace only.
	- Double quotes group text (including whitespace) anywhere inside a token;
	  `"a b",c` is one token.
	- Inside quotes, `\"` and `\\` escape; everything else is literal.
	- No sentinel-string substitution (Cmdr's ___!CMDR_*!___ collision bug).
]]

local Types = require(script.Parent.Types)

type Token = Types.Token

local Parser = {}

--[=[
	Splits a line into span-tagged tokens.
]=]
function Parser.tokenize(text: string): { Token }
	local tokens: { Token } = {}
	local i = 1
	local length = #text

	while i <= length do
		-- Skip unquoted whitespace between tokens.
		local nextNonSpace = string.find(text, "%S", i)
		if nextNonSpace == nil then
			break
		end
		i = nextNonSpace

		local startPos = i
		local pieces: { string } = {}
		local quoted = false
		local closed = true

		while i <= length do
			local char = string.sub(text, i, i)
			if char == '"' then
				quoted = true
				closed = false
				i += 1
				-- Consume until the closing quote, handling escapes.
				local piece: { string } = {}
				while i <= length do
					local qc = string.sub(text, i, i)
					if qc == "\\" and i < length then
						local nextChar = string.sub(text, i + 1, i + 1)
						if nextChar == '"' or nextChar == "\\" then
							table.insert(piece, nextChar)
							i += 2
							continue
						end
					end
					if qc == '"' then
						closed = true
						i += 1
						break
					end
					table.insert(piece, qc)
					i += 1
				end
				table.insert(pieces, table.concat(piece))
			elseif string.match(char, "%s") then
				break
			else
				local pieceStart = i
				-- Run of plain characters up to whitespace or a quote.
				while i <= length do
					local pc = string.sub(text, i, i)
					if pc == '"' or string.match(pc, "%s") then
						break
					end
					i += 1
				end
				table.insert(pieces, string.sub(text, pieceStart, i - 1))
			end
		end

		local endPos = i - 1
		table.insert(tokens, {
			text = table.concat(pieces),
			rawText = string.sub(text, startPos, endPos),
			startPos = startPos,
			endPos = endPos,
			quoted = quoted,
			closed = closed,
		})
	end

	return tokens
end

--[=[
	Splits a raw (quotes intact) token into comma-separated list elements,
	honoring quotes so elements can contain commas and spaces: `"a,b",c` → {"a,b", "c"}.
]=]
function Parser.splitList(rawToken: string): { string }
	local elements: { string } = {}
	local piece: { string } = {}
	local i = 1
	local length = #rawToken

	while i <= length do
		local char = string.sub(rawToken, i, i)
		if char == '"' then
			i += 1
			while i <= length do
				local qc = string.sub(rawToken, i, i)
				if qc == "\\" and i < length then
					local nextChar = string.sub(rawToken, i + 1, i + 1)
					if nextChar == '"' or nextChar == "\\" then
						table.insert(piece, nextChar)
						i += 2
						continue
					end
				end
				if qc == '"' then
					i += 1
					break
				end
				table.insert(piece, qc)
				i += 1
			end
		elseif char == "," then
			table.insert(elements, table.concat(piece))
			table.clear(piece)
			i += 1
		else
			table.insert(piece, char)
			i += 1
		end
	end
	table.insert(elements, table.concat(piece))

	return elements
end

export type CursorLocation = {
	--- Argument slot the cursor addresses: 1 = command name, 2 = first argument…
	read index: number,
	--- The token being edited, nil when the cursor sits in fresh whitespace.
	read token: Token?,
}

--[=[
	Maps a cursor position (1-based, "between" semantics matching
	TextBox.CursorPosition) to the token — or fresh slot — it addresses.
]=]
function Parser.locate(tokens: { Token }, cursor: number): CursorLocation
	local caret = cursor - 1 -- number of characters left of the caret
	for index, token in tokens do
		if caret < token.startPos - 1 then
			-- Whitespace gap before this token: a fresh slot.
			return { index = index, token = nil }
		end
		if caret <= token.endPos then
			-- Touching the token (including its left edge) or inside it.
			return { index = index, token = token }
		end
	end
	-- Past every token (trailing whitespace or empty line): a fresh slot.
	return { index = #tokens + 1, token = nil }
end

return Parser
