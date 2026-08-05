--!strict
--[[
	ServerCommands.luau — the built-in server command set: moderation
	(teleport, kill, respawn, kick, ban, unban), announce and uptime.

	`make(server)` closes over the server singleton and returns the
	implement() bundles ready for registry.register.
]]

local Players = game:GetService("Players")

local BuiltInTypes = require(script.Parent.Parent.BuiltInTypes)
local Define = require(script.Parent.Parent.Define)
local Types = require(script.Parent.Parent.Types)

type ReplyKind = Types.ReplyKind

local t = BuiltInTypes.handles

--[[
	Structural view of KmdrServer — the real type lives in Server.luau, which
	requires this module back (lazily), so importing it would be a cycle.
]]
type ServerLike = {
	read message: (player: Player?, text: string, kind: ReplyKind?) -> (),
}

local TELEPORT_OFFSET = Vector3.new(0, 0, 3)
local DEFAULT_KICK_REASON = "You have been kicked by a moderator"
local DEFAULT_BAN_REASON = "You have been banned from this experience"

local function pluralize(count: number, noun: string): string
	return if count == 1 then `{count} {noun}` else `{count} {noun}s`
end

--- Formats whole seconds as h/m/s, omitting leading zero units.
local function formatDuration(totalSeconds: number): string
	local seconds = math.floor(totalSeconds)
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local remainder = seconds % 60
	if hours > 0 then
		return `{hours}h {minutes}m {remainder}s`
	elseif minutes > 0 then
		return `{minutes}m {remainder}s`
	end
	return `{remainder}s`
end

-- ── Definitions ────────────────────────────────────────────────────────

local teleportDef = Define.defineCommand({
	name = "teleport",
	aliases = { "tp" },
	description = "Teleports a player to another player.",
	group = "admin",
	args = {
		target = t.player("Player to teleport"),
		destination = t.player("Teleport destination"):optional(),
	},
})

local killDef = Define.defineCommand({
	name = "kill",
	description = "Kills the given players.",
	group = "admin",
	args = {
		targets = t.players("Players to kill"),
	},
})

local respawnDef = Define.defineCommand({
	name = "respawn",
	description = "Respawns the given players.",
	group = "admin",
	args = {
		targets = t.players("Players to respawn"),
	},
})

local kickDef = Define.defineCommand({
	name = "kick",
	description = "Kicks a player from the server.",
	group = "admin",
	args = {
		target = t.player("Player to kick"),
		reason = t.text("Reason shown to the player"):optional(),
	},
})

local banDef = Define.defineCommand({
	name = "ban",
	description = "Bans a player — permanently unless a duration is given.",
	group = "admin",
	args = {
		target = t.player("Player to ban"),
		duration = t.duration("Ban length"):optional(),
		reason = t.text("Reason"):optional(),
	},
})

local unbanDef = Define.defineCommand({
	name = "unban",
	description = "Lifts a ban by UserId.",
	group = "admin",
	args = {
		userId = t.playerId("UserId to unban"),
	},
})

local announceDef = Define.defineCommand({
	name = "announce",
	aliases = { "m" },
	description = "Broadcasts a message to every player's console.",
	group = "admin",
	args = {
		message = t.text("Message to announce"),
	},
})

local uptimeDef = Define.defineCommand({
	name = "uptime",
	description = "Shows how long the server has been running.",
	group = "utility",
})

-- ── Implementations ────────────────────────────────────────────────────

local ServerCommands = {}

--- Builds the server-realm bundles; `serverAny` is the KmdrServer singleton.
function ServerCommands.make(serverAny: any): { any }
	local server = serverAny :: ServerLike

	local bundles: { any } = {
		Define.implement(teleportDef, function(ctx, args)
			local destination: Player? = args.destination or ctx.executor
			if destination == nil then
				ctx:reply("No destination — programmatic runs must pass one explicitly", "error")
				return nil
			end
			local targetCharacter = args.target.Character
			if targetCharacter == nil then
				ctx:reply(`{args.target.Name} has no character to teleport`, "error")
				return nil
			end
			local destinationCharacter = destination.Character
			if destinationCharacter == nil then
				ctx:reply(`{destination.Name} has no character to teleport to`, "error")
				return nil
			end
			local destinationPivot = destinationCharacter:GetPivot()
			targetCharacter:PivotTo(CFrame.new(destinationPivot.Position + TELEPORT_OFFSET))
			return `Teleported {args.target.Name} to {destination.Name}`
		end),

		Define.implement(killDef, function(_ctx, args)
			local killed = 0
			for _, player in args.targets do
				local character = player.Character
				local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
				if humanoid ~= nil then
					humanoid.Health = 0
					killed += 1
				end
			end
			return `Killed {killed} of {pluralize(#args.targets, "player")}`
		end),

		Define.implement(respawnDef, function(_ctx, args)
			local respawned = 0
			for _, player in args.targets do
				local okCall = pcall(function()
					player:LoadCharacter()
				end)
				if okCall then
					respawned += 1
				end
			end
			return `Respawned {respawned} of {pluralize(#args.targets, "player")}`
		end),

		Define.implement(kickDef, function(_ctx, args)
			local reason = args.reason or DEFAULT_KICK_REASON
			args.target:Kick(reason)
			return `Kicked {args.target.Name}: {reason}`
		end),

		Define.implement(banDef, function(ctx, args)
			local target = args.target
			local seconds = args.duration
			if seconds ~= nil and seconds <= 0 then
				ctx:reply("Ban duration must be positive — omit it for a permanent ban", "error")
				return nil
			end
			local executorName = if ctx.executor ~= nil then ctx.executor.Name else "the server"
			local okCall, banError = pcall(function()
				Players:BanAsync({
					UserIds = { target.UserId },
					Duration = if seconds ~= nil then seconds else -1,
					DisplayReason = args.reason or DEFAULT_BAN_REASON,
					PrivateReason = `Banned by {executorName} via Kmdr`,
					ApplyToUniverse = false,
					ExcludeAltAccounts = false,
				})
			end)
			if not okCall then
				ctx:reply(`Ban failed: {banError}`, "error")
				return nil
			end
			return if seconds ~= nil
				then `Banned {target.Name} for {formatDuration(seconds)}`
				else `Banned {target.Name} permanently`
		end),

		Define.implement(unbanDef, function(ctx, args)
			local userId = args.userId
			local okCall, unbanError = pcall(function()
				Players:UnbanAsync({
					UserIds = { userId },
					ApplyToUniverse = false,
				})
			end)
			if not okCall then
				ctx:reply(`Unban failed: {unbanError}`, "error")
				return nil
			end
			return `Unbanned user {userId}`
		end),

		Define.implement(announceDef, function(_ctx, args)
			server.message(nil, args.message, "warning")
			return "Announcement sent"
		end),

		Define.implement(uptimeDef, function(_ctx, _args)
			return `Server uptime: {formatDuration(workspace.DistributedGameTime)}`
		end),
	}
	return bundles
end

return ServerCommands
