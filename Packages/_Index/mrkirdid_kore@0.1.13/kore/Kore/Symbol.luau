-- Kore.Symbol — Unique opaque sentinel values (interned by name)

local Types = require(script.Parent.Types)

type Symbol = Types.Symbol

local symbols: { [string]: Symbol } = {}

local Symbol = {}
Symbol.__index = Symbol

function Symbol:__tostring(): string
	return "Symbol(" .. self._name .. ")"
end

function Symbol:__eq(other: Symbol): boolean
	return rawequal(self, other)
end

return function(name: string): Symbol
	if symbols[name] then
		return symbols[name]
	end

	local sym: Symbol = setmetatable({
		_name = name,
		_isSymbol = true,
	}, Symbol) :: any

	symbols[name] = sym
	return sym
end :: Types.SymbolConstructor
