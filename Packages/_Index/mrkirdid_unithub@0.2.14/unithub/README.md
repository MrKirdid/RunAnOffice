# Unithub

Unithub is a small Roblox service/controller bootstrapper for Wally projects. The server owns the real setup and replicates a lightweight manifest so the client can start with only `Unithub:Init()`.

## Install

```toml
[dependencies]
Unithub = "mrkirdid/unithub@^0.2.0"
```

## Server Bootstrap

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Unithub = require(ReplicatedStorage.Packages.Unithub)

Unithub:Init({
	Services = {
		ServerScriptService.Server.Services,
	},

	Controllers = {
		ReplicatedStorage.Client.Controllers,
	},

	Preload = true,
	Timeout = 10,
})
```

## Client Bootstrap

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unithub = require(ReplicatedStorage.Packages.Unithub)

Unithub:Init()
```

Client `Init` waits for the server manifest and only discovers controllers after every startup service has successfully completed its service lifecycle. If the server reports service failures or does not report readiness within the configured lifecycle budget, client init errors instead of loading controllers early.

Optional client exclusions are local-only:

```luau
Unithub:Init({
	ExcludedUnits = { "PVP" },
})
```

## Controller And Service Modules

Only `ModuleScript` descendants whose direct parent is a `Folder` are discovered. This lets a service or controller module have helper ModuleScripts as children without those helpers being auto-loaded.

```luau
return {
	Name = "Inventory",
	Priority = 10,

	Init = function(self, hub)
		self.Data = hub:GetService("Data")
	end,

	Start = function(self, hub)
		print("Inventory ready")
	end,
}
```

Legacy names still work:

- `Prepare` is an alias for `Init`.
- `Activate` is an alias for `Start`.
- `GetUnit` is an alias for `Get`.
- `EngageUnits` is an alias for `Start`.

## Proxies And State

`GetService`, `GetController`, and `Get` return stable proxies. Proxies exist before modules are required, so circular references through Unithub do not need heartbeat polling.

```luau
local Data = Unithub:GetService("Data")
local Inventory = Unithub:WaitForController("Inventory", 5)

if Unithub:CheckService("Data") then
	print(Unithub:GetStatus("Data").State)
end
```

## Runtime Folders

Folders are watched by default. If a valid module is added while the game is running, Unithub registers it and advances it through the current lifecycle phase.

```luau
Unithub:AddServiceFolder(ServerScriptService.Server.Services)
Unithub:AddControllerFolder(ReplicatedStorage.Client.Controllers)
Unithub:AddFolder(ReplicatedStorage.Shared.SharedControllers, {
	Kind = "Controller",
})
```

## Parallel Luau

Unithub can create a real Parallel Luau dispatcher backed by Roblox `Actor` workers. The dispatcher runs job ModuleScript methods in parallel and resolves a Promise when each job returns.

```luau
local dispatcher = Unithub:CreateDispatcher({
	WorkerCount = 4,
	Timeout = 5,
})

dispatcher:Run(ReplicatedStorage.Shared.Jobs.SumNumbers, {
	A = 10,
	B = 32,
}):andThen(function(result)
	print(result)
end)
```

Job modules are required inside the worker Actor. Export plain functions that only use parallel-safe APIs while they are running in parallel:

```luau
return {
	Run = function(payload, context)
		return payload.A + payload.B
	end,

	Raycast = function(payload, context)
		local result = workspace:Raycast(payload.Origin, payload.Direction, payload.Params)

		context.Synchronize()
		-- Do unsafe DataModel writes here, then call context.Desynchronize() before more parallel work.

		return result
	end,
}
```

Convenience calls use the default dispatcher:

```luau
Unithub:RunParallel(ReplicatedStorage.Shared.Jobs.SumNumbers, { A = 1, B = 2 })
Unithub:DispatchParallel(ReplicatedStorage.Shared.Jobs.SumNumbers, "Run", { A = 1, B = 2 })
Unithub:MapParallel(ReplicatedStorage.Shared.Jobs.SumNumbers, "Run", {
	{ A = 1, B = 2 },
	{ A = 3, B = 4 },
})
```

Raw Luau closures cannot be sent to another Actor VM, so parallel jobs must live in ModuleScripts. Payloads and return values must be safe to send through Roblox Actor/BindableEvent messaging. Timed-out work rejects its Promise, but Roblox does not kill the running Actor callback; that worker becomes available again when the late result returns or when the dispatcher is destroyed. Use `Unithub:GetSharedTable(name, initial?)` or `context.GetSharedTable(name, initial?)` for larger shared state.

## Preload

`Preload = true` aggressively preloads the currently replicated client game with hard time caps. It collects content from `ReplicatedFirst`, `ReplicatedStorage`, `StarterGui`, `StarterPlayer`, current `Workspace` descendants, controller folders, tags, and explicit manifests.

Preload covers images, decals, textures, sounds, animations, meshes, particle textures, beam/trail textures, surface appearances, skyboxes, and video frames. It uses `ContentProvider:PreloadAsync()` callback progress, chunks requests, warms important UI images, records failures, and continues in the background instead of trapping players forever.

```luau
Unithub:Init({
	Preload = {
		Aggressive = true,
		CriticalTimeout = 20,
		ChunkSize = 125,
		CriticalTags = { "PreloadCritical" },
		IgnoreTags = { "PreloadIgnore" },
		ExplicitCriticalAssets = {
			"rbxassetid://123456789",
		},
	},
})
```
