--!strict
--[[
	ClientCommands.luau — the built-in client command set: help, clear,
	history, echo, aliases (alias/unalias/aliases), key binds (bind/unbind)
	and version.

	`make(client)` closes over the client singleton and returns the
	implement() bundles ready for registry.register.
]]

local UserInputService = game:GetService("UserInputService")

local BuiltInTypes = require(script.Parent.Parent.BuiltInTypes)
local Define = require(script.Parent.Parent.Define)
local Registry = require(script.Parent.Parent.Registry)
local Types = require(script.Parent.Parent.Types)

type CommandContext = Types.CommandContext
type CommandEntry = Registry.CommandEntry

local t = BuiltInTypes.handles

local VERSION = "0.1.0"
local HISTORY_SHOWN = 20
local BINDS_STORE = "binds"

--[[
	Structural view of KmdrClient — the real type lives in Client.luau, which
	requires this module back (lazily), so importing it would be a cycle.
]]
type ClientLike = {
	read registry: Registry.Registry,
	read run: (text: string) -> (),
	read clear: () -> (),
	read getHistory: () -> { string },
	read addAlias: (name: string, expansion: string) -> (),
	read removeAlias: (name: string) -> boolean,
	read getAliases: () -> { [string]: string },
}

local function padRight(value: string, width: number): string
	return value .. string.rep(" ", math.max(0, width - #value))
end

local function padLeft(value: string, width: number): string
	return string.rep(" ", math.max(0, width - #value)) .. value
end

--- `name <required: type> [optional: type]`, from the entry's synced metadata.
local function formatSignature(entry: CommandEntry): string
	local parts = { entry.name }
	for _, arg in entry.meta.args do
		local piece = `{arg.key}: {arg.typeName}`
		table.insert(parts, if arg.isOptional or arg.hasDefault then `[{piece}]` else `<{piece}>`)
	end
	return table.concat(parts, " ")
end

--- Replies the full command list grouped by `group`, columns aligned
--- (the console font is monospace, so space padding lines up).
local function replyCommandList(ctx: CommandContext, entries: { CommandEntry })
	local groups: { [string]: { CommandEntry } } = {}
	local groupNames: { string } = {}
	local nameWidth = 0
	local aliasWidth = 0

	for _, entry in entries do
		local groupName = entry.meta.group or "other"
		local group = groups[groupName]
		if group == nil then
			group = {}
			groups[groupName] = group
			table.insert(groupNames, groupName)
		end
		table.insert(group, entry)
		nameWidth = math.max(nameWidth, #entry.name)
		aliasWidth = math.max(aliasWidth, #table.concat(entry.meta.aliases, ", "))
	end
	table.sort(groupNames)

	for _, groupName in groupNames do
		local group = groups[groupName] :: { CommandEntry }
		table.sort(group, function(a: CommandEntry, b: CommandEntry)
			return a.name < b.name
		end)
		ctx:reply(groupName, "info")
		for _, entry in group do
			local aliasText = table.concat(entry.meta.aliases, ", ")
			local description = entry.meta.description or ""
			local line = `  {padRight(entry.name, nameWidth)}  {padRight(aliasText, aliasWidth)}  {description}`
			ctx:reply((string.gsub(line, "%s+$", "")), "info")
		end
	end
end

-- ── Definitions ────────────────────────────────────────────────────────

local helpDef = Define.defineCommand({
	name = "help",
	description = "Lists all commands, or explains one command.",
	group = "utility",
	args = {
		command = t.command("Command to explain"):optional(),
	},
})

local clearDef = Define.defineCommand({
	name = "clear",
	description = "Clears the console output.",
	group = "utility",
})

local historyDef = Define.defineCommand({
	name = "history",
	description = "Shows recently run commands.",
	group = "utility",
})

local echoDef = Define.defineCommand({
	name = "echo",
	aliases = { "=" },
	description = "Echoes the given text.",
	group = "utility",
	args = {
		message = t.text("Text to echo"),
	},
})

local aliasDef = Define.defineCommand({
	name = "alias",
	description = "Defines a client-side alias.",
	group = "utility",
	args = {
		name = t.string("Alias name"),
		expansion = t.text("Command line; $1-$9 substitute arguments"),
	},
})

local unaliasDef = Define.defineCommand({
	name = "unalias",
	description = "Removes a client-side alias.",
	group = "utility",
	args = {
		name = t.string("Alias to remove"),
	},
})

local aliasesDef = Define.defineCommand({
	name = "aliases",
	description = "Lists defined aliases.",
	group = "utility",
})

local bindDef = Define.defineCommand({
	name = "bind",
	description = "Runs a command line whenever a key is pressed.",
	group = "utility",
	args = {
		key = t.userInput("Key to bind"),
		commandLine = t.text("Command to run on press"),
	},
})

local unbindDef = Define.defineCommand({
	name = "unbind",
	description = "Removes a key bind.",
	group = "utility",
	args = {
		key = t.userInput("Key to unbind"),
	},
})

local versionDef = Define.defineCommand({
	name = "version",
	description = "Shows the Kmdr version.",
	group = "help",
})

-- ── Implementations ────────────────────────────────────────────────────

local ClientCommands = {}

--- Builds the client-realm bundles; `clientAny` is the KmdrClient singleton.
function ClientCommands.make(clientAny: any): { any }
	local client = clientAny :: ClientLike

	local bundles: { any } = {
		Define.implement(helpDef, function(ctx, args)
			local commandName = args.command
			if commandName == nil then
				replyCommandList(ctx, client.registry.getEntries())
				return nil
			end
			local entry = client.registry.getEntry(commandName)
			if entry == nil then
				ctx:reply(`Unknown command '{commandName}'`, "error")
				return nil
			end
			ctx:reply(formatSignature(entry), "info")
			local description = entry.meta.description
			if description ~= nil then
				ctx:reply(description, "info")
			end
			if #entry.meta.aliases > 0 then
				ctx:reply(`Aliases: {table.concat(entry.meta.aliases, ", ")}`, "info")
			end
			return nil
		end),

		Define.implement(clearDef, function(_ctx, _args)
			client.clear()
			return nil
		end),

		Define.implement(historyDef, function(ctx, _args)
			local history = client.getHistory()
			if #history == 0 then
				ctx:reply("No history yet", "info")
				return nil
			end
			local first = math.max(1, #history - HISTORY_SHOWN + 1)
			local numberWidth = #tostring(#history)
			for index = first, #history do
				ctx:reply(`{padLeft(tostring(index), numberWidth)}  {history[index]}`, "info")
			end
			return nil
		end),

		Define.implement(echoDef, function(_ctx, args)
			return args.message
		end),

		Define.implement(aliasDef, function(_ctx, args)
			client.addAlias(args.name, args.expansion)
			return `Defined alias '{string.lower(args.name)}' as '{args.expansion}'`
		end),

		Define.implement(unaliasDef, function(ctx, args)
			if client.removeAlias(args.name) then
				return `Removed alias '{string.lower(args.name)}'`
			end
			ctx:reply(`No alias named '{args.name}'`, "error")
			return nil
		end),

		Define.implement(aliasesDef, function(ctx, _args)
			local aliasMap = client.getAliases()
			local names: { string } = {}
			local nameWidth = 0
			for name in aliasMap do
				table.insert(names, name)
				nameWidth = math.max(nameWidth, #name)
			end
			if #names == 0 then
				return "No aliases defined"
			end
			table.sort(names)
			for _, name in names do
				ctx:reply(`{padRight(name, nameWidth)}  {aliasMap[name]}`, "info")
			end
			return nil
		end),

		Define.implement(bindDef, function(ctx, args)
			local key = args.key
			if key.EnumType ~= Enum.KeyCode then
				ctx:reply(`'{key.Name}' is not a key — only KeyCode binds are supported for now`, "error")
				return nil
			end
			local binds = ctx:getStore(BINDS_STORE)
			local existing = binds[key] :: RBXScriptConnection?
			if existing ~= nil then
				existing:Disconnect()
			end
			local commandLine = args.commandLine
			binds[key] = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
				if gameProcessed then
					return
				end
				if input.KeyCode == key then
					client.run(commandLine)
				end
			end)
			return `Bound {key.Name} to '{commandLine}'`
		end),

		Define.implement(unbindDef, function(ctx, args)
			local key = args.key
			local binds = ctx:getStore(BINDS_STORE)
			local connection = binds[key] :: RBXScriptConnection?
			if connection == nil then
				ctx:reply(`{key.Name} is not bound`, "error")
				return nil
			end
			connection:Disconnect()
			binds[key] = nil
			return `Unbound {key.Name}`
		end),

		Define.implement(versionDef, function(_ctx, _args)
			return `Kmdr v{VERSION}`
		end),
	}
	return bundles
end

return ClientCommands
