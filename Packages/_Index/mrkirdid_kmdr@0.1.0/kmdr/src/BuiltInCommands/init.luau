--!strict
--[[
	BuiltInCommands — the default command set, split per realm. The realm
	singletons call `makeServer`/`makeClient` from registerDefaults, passing
	themselves; each returns an array of implement() bundles ready for
	registry.register.
]]

local ClientCommands = require(script.ClientCommands)
local ServerCommands = require(script.ServerCommands)

return {
	--- Server realm: moderation (teleport, kill, respawn, kick, ban, unban), announce, uptime.
	makeServer = ServerCommands.make,
	--- Client realm: help, clear, history, echo, aliases, key binds, version.
	makeClient = ClientCommands.make,
}
