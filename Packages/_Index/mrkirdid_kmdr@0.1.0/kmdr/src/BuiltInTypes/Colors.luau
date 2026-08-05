--!strict
--[[
	Colors.luau — color3 (#RGB / #RRGGBB / r,g,b) and brickColor (palette
	enumerated at load via BrickColor.palette, not a hardcoded list), plus
	their list variants.
]]

local Define = require(script.Parent.Parent.Define)
local Types = require(script.Parent.Parent.Types)
local Util = require(script.Parent.Parent.Util)

type ArgContext = Types.ArgContext
type Resolution<T> = Types.Resolution<T>

-- `Define.err`'s payload type only appears in its return type, which the new
-- solver cannot infer from the surrounding context — pin it per payload.
type Err<T> = (message: string, suggestions: { string }?) -> Resolution<T>
local errColor3 = Define.err :: Err<Color3>
local errBrickColor = Define.err :: Err<BrickColor>

-- The BrickColor palette, enumerated once at load (it contains duplicate names).
local brickColorNames: { string } = {}
local brickColorByLower: { [string]: BrickColor } = {}
for paletteIndex = 0, 127 do
	local success, color = pcall(BrickColor.palette, paletteIndex)
	if success then
		local key = string.lower(color.Name)
		if brickColorByLower[key] == nil then
			brickColorByLower[key] = color
			table.insert(brickColorNames, color.Name)
		end
	end
end

local color3Type = Define.defineType({
	name = "color3",
	resolve = function(text: string, _ctx: ArgContext): Resolution<Color3>
		if text == "" then
			return errColor3("Enter a color (#RRGGBB or r,g,b)")
		end

		local hex = string.match(text, "^#?(%x+)$")
		if hex ~= nil and (#hex == 3 or #hex == 6) then
			local success, color = pcall(function()
				return Color3.fromHex(hex)
			end)
			if success then
				return Define.ok(color)
			end
		end

		local parts = string.split(text, ",")
		if #parts == 3 then
			local r = tonumber(parts[1])
			local g = tonumber(parts[2])
			local b = tonumber(parts[3])
			if r ~= nil and g ~= nil and b ~= nil then
				if r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255 then
					return Define.ok(Color3.fromRGB(r, g, b))
				end
			end
		end

		return errColor3(`'{text}' is not a color (use #RRGGBB or r,g,b with 0-255 components)`)
	end,
})

local brickColorType = Define.defineType({
	name = "brickColor",
	resolve = function(text: string, _ctx: ArgContext): Resolution<BrickColor>
		if text == "" then
			return errBrickColor("Enter a BrickColor name", brickColorNames)
		end
		local match = brickColorByLower[string.lower(text)]
		if match ~= nil then
			return Define.ok(match)
		end
		-- Off-palette names: BrickColor.new falls back to Medium stone grey on
		-- unknown input, so only a name that round-trips is a real color.
		local success, color = pcall(function(): BrickColor
			-- Cast: the analysis signature only accepts palette-name literals.
			return (BrickColor.new :: any)(text)
		end)
		if success and string.lower(color.Name) == string.lower(text) then
			return Define.ok(color)
		end
		return errBrickColor(`'{text}' is not a BrickColor`, Util.fuzzyFilter(text, brickColorNames))
	end,
})

return {
	color3 = color3Type,
	color3s = Define.listOf(color3Type, "color3s"),
	brickColor = brickColorType,
	brickColors = Define.listOf(brickColorType, "brickColors"),
}
