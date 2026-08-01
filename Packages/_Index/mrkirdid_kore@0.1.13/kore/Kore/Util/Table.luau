-- Kore.Util.Table — Table manipulation utilities

local Types = require(script.Parent.Parent.Types)

local Table = {}

--- Recursively deep-copy a table (preserves metatables).
function Table.deepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end

	local copy: { [any]: any } = {}
	for k, v in pairs(t :: any) do
		copy[Table.deepCopy(k)] = Table.deepCopy(v)
	end
	return setmetatable(copy, getmetatable(t :: any)) :: any
end

--- Shallow-copy a table (one level, no metatables).
function Table.shallowCopy<T>(t: T): T
	local copy: { [any]: any } = {}
	for k, v in pairs(t :: any) do
		copy[k] = v
	end
	return copy :: any
end

--- Merge any number of tables into a new table. Later keys overwrite earlier ones.
function Table.merge(...: { [any]: any }): { [any]: any }
	local result: { [any]: any } = {}
	for i = 1, select("#", ...) do
		local t: any = select(i, ...)
		if type(t) == "table" then
			for k, v in pairs(t) do
				result[k] = v
			end
		end
	end
	return result
end

--- Return an array of all keys in `t`.
function Table.keys<K, V>(t: { [K]: V }): { K }
	local result: { K } = {}
	for k in pairs(t) do
		table.insert(result, k)
	end
	return result
end

--- Return an array of all values in `t`.
function Table.values<K, V>(t: { [K]: V }): { V }
	local result: { V } = {}
	for _, v in pairs(t) do
		table.insert(result, v)
	end
	return result
end

--- Return a new table containing only entries where `predicate(value, key)` is truthy.
function Table.filter<K, V>(t: { [K]: V }, predicate: (value: V, key: K) -> boolean): { [K]: V }
	local result: { [K]: V } = {} :: any
	for k, v in pairs(t) do
		if predicate(v, k) then
			(result :: any)[k] = v
		end
	end
	return result
end

--- Return a new table with each value transformed by `transform(value, key)`.
function Table.map<K, V, R>(t: { [K]: V }, transform: (value: V, key: K) -> R): { [K]: R }
	local result: { [K]: R } = {} :: any
	for k, v in pairs(t) do
		(result :: any)[k] = transform(v, k)
	end
	return result
end

--- Find the first entry where `predicate(value, key)` is truthy. Returns `(value, key)` or `nil`.
function Table.find<K, V>(t: { [K]: V }, predicate: (value: V, key: K) -> boolean): (V?, K?)
	for k, v in pairs(t) do
		if predicate(v, k) then
			return v, k
		end
	end
	return nil
end

--- Flatten a nested array to the given `depth` (default 1).
function Table.flatten(t: { any }, depth: number?): { any }
	local d: number = depth or 1
	local result: { any } = {}
	for _, v in ipairs(t) do
		if type(v) == "table" and d > 0 then
			local flat: { any } = Table.flatten(v, d - 1)
			for _, fv in ipairs(flat) do
				table.insert(result, fv)
			end
		else
			table.insert(result, v)
		end
	end
	return result
end

--- Return a new array with elements in random order (Fisher-Yates shuffle).
function Table.shuffle<T>(t: { T }): { T }
	local result: { T } = table.clone(t)
	for i = #result, 2, -1 do
		local j: number = math.random(1, i)
		result[i], result[j] = result[j], result[i]
	end
	return result
end

--- Count the number of entries in a dictionary table.
function Table.count(t: { [any]: any }): number
	local n: number = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

--- Deep-copy and freeze a table.
function Table.freeze<T>(t: T): T
	return table.freeze(Table.deepCopy(t)) :: any
end

--- Compute the difference between tables `a` and `b`.
--- Returns `{ added, removed, changed }`.
function Table.diff<K, V>(a: { [K]: V }, b: { [K]: V }): Types.DiffResult<K, V>
	local added: { [K]: V } = {} :: any
	local removed: { [K]: V } = {} :: any
	local changed: { [K]: { old: V, new: V } } = {} :: any

	for k, v in pairs(b) do
		if (a :: any)[k] == nil then
			(added :: any)[k] = v
		elseif (a :: any)[k] ~= v then
			(changed :: any)[k] = { old = (a :: any)[k], new = v }
		end
	end

	for k, v in pairs(a) do
		if (b :: any)[k] == nil then
			(removed :: any)[k] = v
		end
	end

	return { added = added, removed = removed, changed = changed }
end

return Table :: Types.TableUtil
