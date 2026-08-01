# Kore

A professional Roblox Luau game framework. Structured service/controller loader for all server and client scripts, with built-in typed dynamic networking, lifecycle management, multithreading support, and a comprehensive suite of QOL utilities.

## Installation

### Wally
```toml
[dependencies]
Kore = "mrkirdid/kore@0.1.6"
```

The package now exposes a standard Wally entrypoint at `init.luau`, so consumers can require it directly from their linked package alias:

```lua
local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Kore = require(Packages.Kore)
```

### Rojo
This repository still keeps `default.project.json` for local development, but it is not part of the published Wally package.

## Quick Start

### Server (KoreServer.server.luau)
```lua
local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Kore = require(Packages.Kore)

Kore.Start():andThen(function()
  print("Server started!")
end)
```

### Client (KoreClient.client.luau)
```lua
local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Kore = require(Packages.Kore)

Kore.Start():andThen(function()
  print("Client started!")
end)
```

### Defining a Service
```lua
-- src/server/services/MyService.luau
local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Kore = require(Packages.Kore)

return {
  Name = "MyService",

  Client = {
    GetData = function(self, player, id)
      return { id = id, value = 42 }
    end,

    DataUpdated = Kore.NetEvent,
  },

  Init = function(self, ctx)
    ctx.Log.Info("Initializing!")
  end,

  Start = function(self, ctx)
    ctx.Log.Info("Started!")
  end,
}
```

### Defining a Controller
```lua
-- src/client/controllers/MyController.luau
return {
  Name = "MyController",
  Dependencies = { "MyService" },

  Init = function(self, ctx)
  end,

  Start = function(self, ctx)
    local MyService = ctx.Kore.GetService("MyService")
    MyService.GetData(1):andThen(function(data)
      print(data)
    end)
  end,
}
```

## Modules

| Module | Description |
|--------|-------------|
| `Kore.Promise` | Promise/A+ (evaera/promise) |
| `Kore.Signal` | Lightweight signal with optional networking |
| `Kore.Log` | Structured tagged logger |
| `Kore.Timer` | Debounce, Throttle, Delay, Every |
| `Kore.Symbol` | Unique opaque sentinel values |
| `Kore.Util.Table` | Table manipulation utilities |
| `Kore.Util.String` | String manipulation utilities |
| `Kore.Util.Math` | Math utilities |
| `Kore.Tween` | Builder pattern tween with Promise |
| `Kore.Curve` | Keyframe curve sampler |
| `Kore.Data` | ProfileStore bridge |
| `Kore.Thread` | Weave parallel execution wrapper |
| `Kore.Mock` | Test isolation (TestEZ/Hoarcekat) |
| `Kore.Janitor` | Cleanup management |
| `Kore.Fusion` | Re-export of Fusion |
| `Kore.Net` | Networking internals |

## VS Code Extension

The companion extension provides:
- Autocomplete for `Kore.GetService()` and `Kore.GetController()`
- Automatic type generation (`Types.luau`)
- Service/Controller snippets
- Diagnostics (name mismatches, unknown deps, duplicates)
- Hover documentation

See `extension/README.md` for details.

### Kore.toml

The extension reads its project config from `Kore.toml` in the workspace root. If the file is missing, Kore-specific extension features stay disabled until you run `Kore: Init Project (Create Kore.toml)`.

`Kore.toml` supports three sections:

```toml
[paths]
services = "src/server/services"
controllers = "src/client/controllers"
types = "src/shared/Kore/Types.luau"
shared = "src/shared"

[require]
kore = "game.ReplicatedStorage.Shared.Packages.kore"
# types = "game.ReplicatedStorage.Shared.Packages.kore.Types"

[options]
autoTemplate = true
diagnostics = true
snippets = true
generateTypes = true
prefix = "!"
debug = false
```

Omitted keys fall back to the extension defaults. The file name is case-sensitive on the extension side: use `Kore.toml` in the workspace root.

> **Note:** Each key must be under the correct section header (`[paths]`, `[require]`, `[options]`). The extension will still pick up option keys placed under the wrong section, but it will log a warning telling you to move them.

#### `[paths]`

| Key | Default | Description |
|-----|---------|-------------|
| `services` | `src/server/services` | Conventional services directory. Used for service discovery, watcher setup, and auto-templating when new service files are created there. |
| `controllers` | `src/client/controllers` | Conventional controllers directory. Used for controller discovery, watcher setup, and auto-templating for new controller files. |
| `types` | `src/shared/Kore/Types.luau` | Output file written by the extension when type generation is enabled. |
| `shared` | `src/shared` | Shared-code root used for module indexing and require completions. |

Notes:
- Paths are relative to the workspace root.
- The extension also performs a global `.luau` scan, so services and controllers outside the configured folders can still be detected by content. The configured `services` and `controllers` paths still matter for templates and the fast-path watchers.

#### `[require]`

| Key | Default | Description |
|-----|---------|-------------|
| `kore` | `game.ReplicatedStorage.Shared.Packages.kore` | Luau require expression used when the extension inserts `local Kore = require(...)` into generated snippets and templates. |
| `types` | empty | Optional explicit require expression for the generated `Types` module. If omitted, the extension derives it from `require.kore`. |

`require.kore` supports both styles:

```toml
[require]
kore = "game.ReplicatedStorage.Packages.Kore"
```

```toml
[require]
kore = "@Packages/Kore"
```

If `require.types` is omitted, the extension derives it like this:
- `game.ReplicatedStorage.Packages.Kore` -> `game.ReplicatedStorage.Packages.Kore.Types`
- `@Packages/Kore` -> `"@Packages/Kore/Types"`

Set `require.types` explicitly if your types module lives somewhere else.

#### `[options]`

| Key | Default | Description |
|-----|---------|-------------|
| `autoTemplate` | `true` | Automatically fills new empty `.luau` files created inside the configured services/controllers folders with Kore service or controller boilerplate. |
| `diagnostics` | `true` | Enables Kore-specific diagnostics such as name mismatches, duplicate definitions, and unknown dependencies. |
| `snippets` | `true` | Enables Kore snippets and prefix-based quick insert commands such as service/controller presets. |
| `generateTypes` | `true` | Regenerates `Types.luau` when services or controllers change and writes the initial types file during activation. |
| `prefix` | `!` | Trigger prefix for quick completion commands such as `!getservice`, `!getcontroller`, `!service`, `!controller`, `!preset`, `!kore`, and `!require`. |
| `debug` | `false` | Enables verbose logging in the Kore output channel. |

#### Example for this repo layout

For a standard Rojo-style project with shared Kore code in `src/shared`, this is a reasonable starting point:

```toml
[paths]
services = "src/server/services"
controllers = "src/client/controllers"
types = "src/shared/Kore/Types.luau"
shared = "src/shared"

[require]
kore = "game.ReplicatedStorage.Shared.Packages.kore"

[options]
autoTemplate = true
diagnostics = true
snippets = true
generateTypes = true
prefix = "!"
debug = false
```

## License

MIT
