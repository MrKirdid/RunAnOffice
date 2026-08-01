-- Kore.Util.String — String manipulation utilities

local Types = require(script.Parent.Parent.Types)

local String = {}

--- Remove leading and trailing whitespace from `s`.
function String.trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") :: string
end

--- Split `s` by `sep` (default `","`) and return an array of parts.
function String.split(s: string, sep: string?): { string }
	local separator: string = sep or ","
	local result: { string } = {}
	for part in string.gmatch(s, "([^" .. separator .. "]+)") do
		table.insert(result, part)
	end
	return result
end

--- Return whether `s` starts with `prefix`.
function String.startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

--- Return whether `s` ends with `suffix`.
function String.endsWith(s: string, suffix: string): boolean
	return string.sub(s, -#suffix) == suffix
end

--- Capitalize the first character of `s`.
function String.capitalize(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

--- Truncate `s` to `maxLen` characters, appending `suffix` (default `"..."`) if truncated.
function String.truncate(s: string, maxLen: number, suffix: string?): string
	local sfx: string = suffix or "..."
	if #s <= maxLen then
		return s
	end
	return string.sub(s, 1, maxLen - #sfx) .. sfx
end

--- Pad the start of `s` with `char` (default `" "`) until it reaches `len` characters.
function String.padStart(s: string, len: number, char: string?): string
	local c: string = char or " "
	while #s < len do
		s = c .. s
	end
	return s
end

--- Pad the end of `s` with `char` (default `" "`) until it reaches `len` characters.
function String.padEnd(s: string, len: number, char: string?): string
	local c: string = char or " "
	while #s < len do
		s = s .. c
	end
	return s
end

--- Convert a hyphen/underscore-separated string to camelCase.
function String.camelize(s: string): string
	local result: string = string.gsub(s, "[%-_]+(%w)", function(c: string): string
		return string.upper(c)
	end)
	return string.lower(string.sub(result, 1, 1)) .. string.sub(result, 2)
end

--- Convert a string to a URL-safe slug (lowercase, hyphens, no special chars).
function String.slugify(s: string): string
	s = string.lower(s)
	s = string.gsub(s, "%s+", "-")
	s = string.gsub(s, "[^%w%-]", "")
	s = string.gsub(s, "%-%-+", "-")
	s = string.gsub(s, "^%-+", "")
	s = string.gsub(s, "%-+$", "")
	return s
end

return String :: Types.StringUtil
