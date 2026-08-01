-- Kore.Log — Structured logger with levels, tagging, and filtering

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

type TaggedLogger = Types.TaggedLogger
type LogLevel = Types.LogLevel

local Log = {}
Log.__index = Log

local LEVELS: { [string]: number } = {
	Debug = 1,
	Info = 2,
	Warn = 3,
	Error = 4,
}

local isStudio: boolean = RunService:IsStudio()
local minLevel: number = LEVELS.Warn

--- Set the minimum log level. Messages below this level are suppressed.
function Log.SetMinLevel(level: LogLevel): ()
	minLevel = LEVELS[level] or LEVELS.Warn
end

--- Enable debug-level logging.
function Log.EnableDebug(): ()
	minLevel = LEVELS.Debug
end

local function formatMessage(tag: string?, level: string, message: string, ...: any): string
	local args = { ... }
	if #args > 0 then
		local ok, formatted = pcall(string.format, message, ...)
		if ok then
			message = formatted
		end
	end

	if tag then
		return string.format("[%s][%s] %s", tag, level, message)
	end
	return string.format("[Kore][%s] %s", level, message)
end

--- Log a debug-level message (suppressed unless debug is enabled).
function Log.Debug(tag: string, message: string, ...: any): ()
	if minLevel > LEVELS.Debug then
		return
	end
	print(formatMessage(tag, "DEBUG", message, ...))
end

--- Log an info-level message.
function Log.Info(tag: string, message: string, ...: any): ()
	if minLevel > LEVELS.Info then
		return
	end
	print(formatMessage(tag, "INFO", message, ...))
end

--- Log a warning-level message.
function Log.Warn(tag: string, message: string, ...: any): ()
	if minLevel > LEVELS.Warn then
		return
	end
	warn(formatMessage(tag, "WARN", message, ...))
end

--- Log an error-level message and throw.
function Log.Error(tag: string, message: string, ...: any): ()
	-- Errors always print
	error(formatMessage(tag, "ERROR", message, ...), 2)
end

--- Log an error-level message without throwing.
function Log.ErrorNoThrow(tag: string, message: string, ...: any): ()
	-- Logs error without throwing
	warn(formatMessage(tag, "ERROR", message, ...))
end

--- Create a tagged logger scoped to a specific service or controller.
function Log.Tagged(tag: string): TaggedLogger
	local tagged: TaggedLogger = {} :: TaggedLogger

	function tagged.Debug(message: string, ...: any): ()
		Log.Debug(tag, message, ...)
	end

	function tagged.Info(message: string, ...: any): ()
		Log.Info(tag, message, ...)
	end

	function tagged.Warn(message: string, ...: any): ()
		Log.Warn(tag, message, ...)
	end

	function tagged.Error(message: string, ...: any): ()
		Log.Error(tag, message, ...)
	end

	function tagged.ErrorNoThrow(message: string, ...: any): ()
		Log.ErrorNoThrow(tag, message, ...)
	end

	return tagged
end

return Log :: Types.LogModule
