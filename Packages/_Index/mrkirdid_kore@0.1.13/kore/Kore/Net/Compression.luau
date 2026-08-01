-- Kore.Net.Compression — Custom compression strategies for networking
-- Built from scratch. Not based on any external module.

local Log = require(script.Parent.Parent.Log)
local Types = require(script.Parent.Parent.Types)

local Compression = {}

local currentStrategy: Types.CompressionStrategy = "Auto"
local customEncode: ((data: any) -> any)? = nil
local customDecode: ((data: any) -> any)? = nil

-- Dictionary encoding for repeated string keys
local dictionary: { [string]: string } = {}
local dictionaryReverse: { [string]: string } = {}
local nextDictId: number = 1

local function getDictKey(key: string): string
	if dictionary[key] then
		return dictionary[key]
	end
	local id: number = nextDictId
	nextDictId = id + 1
	local encoded: string = string.char(0x01) .. string.pack("I2", id)
	dictionary[key] = encoded
	dictionaryReverse[encoded] = key
	return encoded
end

-- Delta compression: encode only differences between consecutive values
local function deltaEncode(values: { any }): { any }
	if #values == 0 then
		return values
	end

	local result: { any } = { values[1] }
	for i = 2, #values do
		if type(values[i]) == "number" and type(values[i - 1]) == "number" then
			result[i] = values[i] - values[i - 1]
		else
			result[i] = values[i]
		end
	end
	return result
end

local function deltaDecode(values: { any }): { any }
	if #values == 0 then
		return values
	end

	local result: { any } = { values[1] }
	for i = 2, #values do
		if type(values[i]) == "number" and type(result[i - 1]) == "number" then
			result[i] = result[i - 1] + values[i]
		else
			result[i] = values[i]
		end
	end
	return result
end

-- Analyze payload to determine best strategy
local function analyzePayload(data: any): Types.CompressionStrategy
	if type(data) ~= "table" then
		return "None"
	end

	local keyCount: number = 0
	local numericValues: number = 0
	local totalValues: number = 0

	for key, value in pairs(data) do
		if type(key) == "string" then
			keyCount = keyCount + 1
		end
		if type(value) == "number" then
			numericValues = numericValues + 1
		end
		totalValues = totalValues + 1
	end

	-- Use aggressive if many string keys or numeric values for delta encoding
	if keyCount > 5 or numericValues > 3 then
		return "Aggressive"
	end

	return "None"
end

-- Encode data using dictionary encoding for string keys
local function dictionaryEncode(data: any): any
	if type(data) ~= "table" then
		return data
	end

	local result: { [any]: any } = {}
	for key, value in pairs(data) do
		if type(key) == "string" then
			result[getDictKey(key)] = dictionaryEncode(value)
		else
			result[key] = dictionaryEncode(value)
		end
	end
	return result
end

local function dictionaryDecode(data: any): any
	if type(data) ~= "table" then
		return data
	end

	local result: { [any]: any } = {}
	for key, value in pairs(data) do
		if type(key) == "string" and dictionaryReverse[key] then
			result[dictionaryReverse[key]] = dictionaryDecode(value)
		else
			result[key] = dictionaryDecode(value)
		end
	end
	return result
end

--- Encode `data` using the current compression strategy.
function Compression.Encode(data: any): any
	local strategy: Types.CompressionStrategy = currentStrategy

	if strategy == "None" then
		return data
	end

	if strategy == "Custom" then
		if customEncode then
			return (customEncode :: (data: any) -> any)(data)
		end
		return data
	end

	if strategy == "Auto" then
		strategy = analyzePayload(data)
		if strategy == "None" then
			return data
		end
	end

	-- Aggressive strategy: dictionary encoding + delta for numeric arrays
	if strategy == "Aggressive" then
		local encoded: any = dictionaryEncode(data)
		return encoded
	end

	return data
end

--- Decode `data` using the current compression strategy.
function Compression.Decode(data: any): any
	local strategy: Types.CompressionStrategy = currentStrategy

	if strategy == "None" then
		return data
	end

	if strategy == "Custom" then
		if customDecode then
			return (customDecode :: (data: any) -> any)(data)
		end
		return data
	end

	-- Auto and Aggressive both need dictionary decoding
	if strategy == "Auto" or strategy == "Aggressive" then
		return dictionaryDecode(data)
	end

	return data
end

--- Set the compression strategy. Accepts a strategy name string or a config table.
function Compression.SetStrategy(config: Types.CompressionStrategy | Types.CompressionConfig): ()
	if type(config) == "string" then
		currentStrategy = config :: Types.CompressionStrategy
		return
	end

	if type(config) == "table" then
		local cfg: Types.CompressionConfig = config :: Types.CompressionConfig
		currentStrategy = cfg.Strategy or "Auto"

		if cfg.Encode then
			customEncode = cfg.Encode
		end
		if cfg.Decode then
			customDecode = cfg.Decode
		end
	end
end

--- Get the current compression strategy name.
function Compression.GetStrategy(): Types.CompressionStrategy
	return currentStrategy
end

return Compression
