--!strict
--[[
	Dispatcher.luau — turns a line of text into an Evaluation: command lookup,
	per-argument resolution (with spans and errors preserved for the UI), and
	context construction. Realm orchestration (guards, callbacks, networking)
	lives in Server.luau / Client.luau on top of this.

	The same evaluate() runs on every keystroke for live validation and once
	more on submit — one code path, no divergence between what the UI shows
	and what execution does.
]]

local Parser = require(script.Parent.Parser)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)

type ArgContext = Types.ArgContext
type CommandContext = Types.CommandContext
type CommandEntry = Registry.CommandEntry
type EffectiveArgSpec = Registry.EffectiveArgSpec
type Realm = Types.Realm
type ReplyKind = Types.ReplyKind
type RegistryType = Registry.Registry
type Token = Types.Token

local Dispatcher = {}

export type EvalBase = {
	read realm: Realm,
	read executor: Player?,
}

export type ArgEvaluation = {
	read spec: EffectiveArgSpec,
	read token: Token?,
	--- False when the argument was filled from a default or left nil (optional).
	read provided: boolean,
	read value: any,
	read error: string?,
	read suggestions: { string }?,
}

export type Evaluation = {
	read text: string,
	read tokens: { Token },
	read entry: CommandEntry?,
	--- The name/alias actually typed (original casing).
	read alias: string?,
	--- Set when the first token matches no command; includes a fuzzy hint.
	read commandError: string?,
	read args: { ArgEvaluation },
	read argValues: { [string]: any },
	--- First blocking problem, ready to display.
	read firstError: string?,
}

--[=[
	Evaluates a line against a registry. Never yields, never throws.
]=]
function Dispatcher.evaluate(registry: RegistryType, text: string, base: EvalBase): Evaluation
	local tokens = Parser.tokenize(text)
	local args: { ArgEvaluation } = {}
	local argValues: { [string]: any } = {}

	local commandToken = tokens[1]
	if commandToken == nil then
		return {
			text = text,
			tokens = tokens,
			entry = nil,
			alias = nil,
			commandError = nil, -- empty line: nothing to complain about
			args = args,
			argValues = argValues,
			firstError = nil,
		}
	end

	local entry = registry.getEntry(commandToken.text)
	if entry == nil then
		local suggestions = Util.fuzzyFilter(commandToken.text, registry.getNames(true))
		local hint = if suggestions[1] ~= nil then ` — did you mean '{suggestions[1]}'?` else ""
		local message = `Unknown command '{commandToken.text}'{hint}`
		return {
			text = text,
			tokens = tokens,
			entry = nil,
			alias = commandToken.text,
			commandError = message,
			args = args,
			argValues = argValues,
			firstError = message,
		}
	end

	local specs = registry.argSpecsFor(entry)
	local firstError: string? = nil
	local tokenIndex = 2
	local consumedAll = false

	for _, spec in specs do
		local token = tokens[tokenIndex]
		local isGreedy = spec.spec ~= nil and (spec.spec :: Types.ErasedTypeSpec).greedy == true

		if token == nil then
			-- Missing: default, optional, or error.
			if spec.hasDefault then
				argValues[spec.key] = spec.defaultValue
				table.insert(args, {
					spec = spec,
					token = nil,
					provided = false,
					value = spec.defaultValue,
					error = nil,
					suggestions = nil,
				})
			elseif spec.isOptional then
				table.insert(args, {
					spec = spec,
					token = nil,
					provided = false,
					value = nil,
					error = nil,
					suggestions = nil,
				})
			else
				local message = `Missing required argument '{spec.key}' ({spec.displayName})`
				firstError = firstError or message
				table.insert(args, {
					spec = spec,
					token = nil,
					provided = false,
					value = nil,
					error = message,
					suggestions = nil,
				})
			end
			continue
		end

		local resolveText: string
		local rawToken: string
		if isGreedy then
			-- The rest of the line, raw, as one value.
			resolveText = string.sub(text, token.startPos)
			rawToken = resolveText
			consumedAll = true
		else
			resolveText = token.text
			rawToken = token.rawText
		end

		local argCtx: ArgContext = {
			realm = base.realm,
			executor = base.executor,
			registry = registry,
			rawText = text,
			rawToken = rawToken,
			argKey = spec.key,
		}

		local value: any = nil
		local errorMessage: string? = nil
		local suggestions: { string }? = nil

		local typeSpec = spec.spec
		if typeSpec == nil then
			-- Unknown type on this realm (remote command): pass the raw string.
			value = resolveText
		else
			local okCall, resolution = pcall(typeSpec.resolve, resolveText, argCtx)
			if not okCall then
				errorMessage = `error resolving '{spec.key}': {resolution}`
			elseif resolution.ok then
				value = resolution.value
				suggestions = resolution.suggestions
			else
				errorMessage = resolution.error
				suggestions = resolution.suggestions
			end
		end

		if errorMessage ~= nil then
			firstError = firstError or `{spec.key}: {errorMessage}`
		else
			argValues[spec.key] = value
		end
		table.insert(args, {
			spec = spec,
			token = token,
			provided = true,
			value = value,
			error = errorMessage,
			suggestions = suggestions,
		})

		tokenIndex += 1
		if consumedAll then
			tokenIndex = #tokens + 1
			break
		end
	end

	if not consumedAll and tokens[tokenIndex] ~= nil then
		local extra = tokens[tokenIndex]
		local message = `Too many arguments — '{extra.text}' is not expected (quote values containing spaces)`
		firstError = firstError or message
	end

	return {
		text = text,
		tokens = tokens,
		entry = entry,
		alias = commandToken.text,
		commandError = nil,
		args = args,
		argValues = argValues,
		firstError = firstError,
	}
end

export type ReplySink = (message: string, kind: ReplyKind) -> ()

--[=[
	Builds the context passed to guards and run callbacks.
]=]
function Dispatcher.makeContext(
	registry: RegistryType,
	evaluation: Evaluation,
	base: EvalBase,
	replySink: ReplySink
): CommandContext
	local entry = evaluation.entry
	assert(entry ~= nil, "makeContext requires a successful command lookup")
	return {
		realm = base.realm,
		executor = base.executor,
		rawText = evaluation.text,
		alias = evaluation.alias or entry.name,
		name = entry.name,
		group = entry.meta.group,
		permission = entry.meta.permission,
		argValues = evaluation.argValues,
		reply = function(_self: CommandContext, message: string, kind: ReplyKind?)
			replySink(message, kind or "info")
		end,
		getStore = function(_self: CommandContext, name: string): { [any]: any }
			return registry.getStore(name)
		end,
	}
end

return Dispatcher
