--!strict
--[[
	Vectors.luau — vector2 ("x,y"), vector3 ("x,y,z") and positionVector3
	("x,y,z" where a component may be "~" or "~n": relative to the executor's
	HumanoidRootPart). List variants via listOf; quoted elements carry the
	inner commas.
]]

local Define = require(script.Parent.Parent.Define)
local Types = require(script.Parent.Parent.Types)

type ArgContext = Types.ArgContext
type Resolution<T> = Types.Resolution<T>

-- `Define.err`'s payload type only appears in its return type, which the new
-- solver cannot infer from the surrounding context — pin it per payload.
type Err<T> = (message: string, suggestions: { string }?) -> Resolution<T>
local errVector2 = Define.err :: Err<Vector2>
local errVector3 = Define.err :: Err<Vector3>

local AXIS_LABELS = { "x", "y", "z" }

local function executorRootPosition(ctx: ArgContext): Vector3?
	local executor = ctx.executor
	if executor == nil then
		return nil
	end
	local character = executor.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return (root :: BasePart).Position
end

local vector2Type = Define.defineType({
	name = "vector2",
	resolve = function(text: string, _ctx: ArgContext): Resolution<Vector2>
		if text == "" then
			return errVector2("Enter a Vector2 as x,y")
		end
		local parts = string.split(text, ",")
		if #parts == 2 then
			local x = tonumber(parts[1])
			local y = tonumber(parts[2])
			if x ~= nil and y ~= nil then
				return Define.ok(Vector2.new(x, y))
			end
		end
		return errVector2(`'{text}' is not a Vector2 (use x,y)`)
	end,
})

local vector3Type = Define.defineType({
	name = "vector3",
	resolve = function(text: string, _ctx: ArgContext): Resolution<Vector3>
		if text == "" then
			return errVector3("Enter a Vector3 as x,y,z")
		end
		local parts = string.split(text, ",")
		if #parts == 3 then
			local x = tonumber(parts[1])
			local y = tonumber(parts[2])
			local z = tonumber(parts[3])
			if x ~= nil and y ~= nil and z ~= nil then
				return Define.ok(Vector3.new(x, y, z))
			end
		end
		return errVector3(`'{text}' is not a Vector3 (use x,y,z)`)
	end,
})

local positionVector3Type = Define.defineType({
	name = "positionVector3",
	resolve = function(text: string, ctx: ArgContext): Resolution<Vector3>
		if text == "" then
			return errVector3("Enter a position as x,y,z (~ = your position)", { "~,~,~" })
		end
		local parts = string.split(text, ",")
		if #parts ~= 3 then
			return errVector3(`'{text}' is not a position (use x,y,z; ~ = relative)`)
		end

		local components: { number } = {}
		for axis = 1, 3 do
			local part = string.match(parts[axis], "^%s*(.-)%s*$") :: string
			local value: number? = nil
			if string.sub(part, 1, 1) == "~" then
				local base = executorRootPosition(ctx)
				if base == nil then
					return errVector3("Relative '~' coordinates require your character")
				end
				local baseComponent = if axis == 1 then base.X elseif axis == 2 then base.Y else base.Z
				local rest = string.sub(part, 2)
				if rest == "" then
					value = baseComponent
				else
					local offset = tonumber(rest)
					value = if offset == nil then nil else baseComponent + offset
				end
			else
				value = tonumber(part)
			end
			if value == nil then
				return errVector3(`'{part}' is not a valid {AXIS_LABELS[axis]} component`)
			end
			table.insert(components, value)
		end
		return Define.ok(Vector3.new(components[1], components[2], components[3]))
	end,
})

return {
	vector2 = vector2Type,
	vector2s = Define.listOf(vector2Type, "vector2s"),
	vector3 = vector3Type,
	vector3s = Define.listOf(vector3Type, "vector3s"),
	positionVector3 = positionVector3Type,
}
