# Kmdr

A strictly-typed, modern command console for Roblox — a ground-up reimagining of
[evaera's Cmdr](https://github.com/evaera/Cmdr) built for the new Luau type solver
and a command bar that behaves like a modern command palette.

```luau
-- A command is pure data in a shared module…
local teleport = Kmdr.defineCommand({
	name = "teleport",
	aliases = { "tp" },
	description = "Teleport a player to another player.",
	group = "admin",
	args = {
		target = Kmdr.types.player("Player to teleport"),
		destination = Kmdr.types.player("Where to go"):optional(),
	},
})

-- …and its server callback gets fully-typed args, derived by a type function.
server.register(Kmdr.implement(teleport, function(ctx, args)
	-- args : { read target: Player, read destination: Player? }   ← inferred!
	local destination = args.destination or ctx.executor
	...
	return `Teleported {args.target.Name}.`
end))
```

## Why not just Cmdr?

Cmdr is excellent and battle-tested, but it predates typed Luau: stringly-typed
definitions, a `FooServer.luau` filename convention for server code, runtime script
reparenting, an imperative 2018 UI with zero animation, and prefix-only autocomplete
that works only at the end of the line. Kmdr keeps the mental model (registry, types,
dispatcher) and rebuilds everything on modern foundations:

| | Cmdr | Kmdr |
|---|---|---|
| Typing | none (`--!strict` count: 0) | strict everywhere; `run` args **derived** via user-defined type functions |
| Server impls | `xServer.luau` name magic | explicit `Kmdr.implement(def, fn)` |
| Replication | reparents your ModuleScripts | serialized metadata sync; defs are pure data |
| Security | warns if no BeforeRun hook | blocks by default until a guard is registered |
| Autocomplete | prefix-only, end-of-line only | fuzzy, cursor-aware (edit arg 2 mid-line), quoted-aware |
| History | plain up/down | prefix-filtered up/down + fish-style ghost text |
| Editing | native TextBox only | Ctrl+Backspace, Ctrl+←/→, Ctrl+Shift+←/→, Ctrl+U |
| Feedback | error after you run | live inline validation + signature help while typing |
| UI | imperative `Instance.new`, no motion | Fusion 0.3; critically-damped springs, linear fades, typewriter output |

## Install

`wally.toml`:

```toml
[dependencies]
Kmdr = "mrkirdid/kmdr@0.1.0"
```

Then `wally install` and (for types across the wally link) `wally-package-types --sourcemap sourcemap.json Packages/`.

## Bootstrap

```luau
-- ServerScriptService (Script)
local Kmdr = require(ReplicatedStorage.Packages.Kmdr)
local server = Kmdr.server()

server.addGuard(function(ctx)
	-- return a string to deny, nil to allow
	if ctx.group == "admin" and not isAdmin(ctx.executor) then
		return "Admins only"
	end
	return nil
end)

server.registerDefaults()                    -- built-in commands
server.registerFolder(ServerStorage.Commands) -- your own

-- StarterPlayerScripts (LocalScript)
local Kmdr = require(ReplicatedStorage.Packages.Kmdr)
local client = Kmdr.client({ placeLabel = "mygame" })
client.registerDefaults()
```

Press **F2**. Outside Studio, nothing with a server implementation runs until you add
a guard — that's deliberate.

## The command bar

- **Fuzzy matching** — `tpp` finds `teleport`; exact prefixes always rank first.
- **Cursor-aware completion** — arrow back into the middle of the line and edit any
  argument; only the token under the caret is replaced (Tab accepts).
- **Live validation** — the offending token tints red and the reason shows under the
  bar, before you ever press Enter. Signature help highlights the argument you're on.
- **History** — Up/Down cycles history filtered by what you've typed; a dim
  fish-style ghost of the best history match trails the caret (Right/End accepts).
- **Word-level editing** — Ctrl+Backspace, Ctrl+←/→, Ctrl+Shift+←/→, Ctrl+U.
- **Motion** — critically-damped springs for layout, linear fades for transparency,
  per-letter reveals for accent text, fast typewriter output lines.

## Core concepts

### Argument types

```luau
local vibe = Kmdr.defineType({
	name = "vibe",
	resolve = function(text, ctx)
		local match = VIBES[string.lower(text)]
		if match then
			return Kmdr.ok(match)
		end
		return Kmdr.err(`'{text}' is not a vibe`, Kmdr.util.fuzzyFilter(text, VIBE_NAMES))
	end,
})
```

One `resolve` function is validation, autocomplete *and* parsing — it runs on every
keystroke (never yield in it) and once on submit. `Kmdr.listOf(handle)` derives
comma-list types; `Kmdr.enumOf(name, values)` derives enums (typed as the singleton
union of the values). ~30 built-ins live in `Kmdr.types`.

### Guards, not hooks

`server.addGuard(fn, priority?)` — first guard to return a string denies with that
message. `ctx` carries `name`, `group`, `permission`, `executor`, `argValues`.
`server.onRan(fn)` observes completed runs (logging). Client guards exist for fast
local UX; the server always re-checks.

### Definitions are data

A `CommandDefinition` contains no functions, so it can live in ReplicatedStorage and
be registered on both realms. The server syncs metadata for its commands to clients,
so autocomplete knows server commands without replicating any server code. Callbacks
attach at registration: `server.register(Kmdr.implement(def, fn))` /
`client.register(Kmdr.implement(def, fn))`.

## Strictness notes

- The engine and public API are `--!strict` under the **new type solver** (set
  `Workspace.UseNewLuauTypeSolver = Enabled`, and `luau-lsp.fflags.enableNewSolver`
  in your editor for the full experience — including `args` inference in callbacks).
- The Fusion-facing interface layer runs `--!nonstrict` until Fusion ships
  new-solver-ready types (its `UsedAs<T>` union defeats generic inference today).

## License

MIT — see [LICENSE](LICENSE). Derived from Cmdr, © 2018 Eryn L. K.
Design rationale in [DESIGN.md](DESIGN.md).
