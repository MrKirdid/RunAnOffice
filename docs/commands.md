# Console commands

The console is [Cmdr](https://eryn.io/Cmdr/). F2 opens it. In Studio everyone is an admin; in a live
game it is the ids in `Configs/Admins.luau` plus the place owner (`Admins.RestrictInGame`).

`me`, `all`, `others`, `random` and a partial name all work wherever a command takes players.

## Money and stats

| Command | What it does |
| --- | --- |
| `cash <players> <amount>` | Adds cash. Negative takes it away, never below zero. |
| `luck <players> <amount>` | Sets luck outright. 1 is the plain table, 2 doubles the rarest chance, 0 kills the rare end. |
| `rolls <players> [amount]` | Sets unlocked reroll pads, 1 to 17. Defaults to 17. |
| `pay [ticks]` | Runs the revenue tick by hand for everyone. `pay 60` is a minute of idle income at once. |

## Plot

| Command | What it does |
| --- | --- |
| `floors <players> <count>` | Sets how many floors are unlocked. Opens up to the number and closes everything above it. |
| `givedesk <players> [amount] [variant]` | Drops desks into the next free slots, rolled like a purchase unless a variant is named. |
| `cleardesks <players>` | Strips every desk out, employees and all. Floors stay unlocked. |
| `plot <players>` | Puts players back on their own plot's spawn. |

## Employees

| Command | What it does |
| --- | --- |
| `spawnnpcs [amount] [type]` | Drops walking employees at the spawn marker now, instead of waiting out the timer. |
| `seat <players> [amount] [type]` | Sits employees straight down at the lowest free desks, skipping the walk. |
| `clearemployees <players>` | Empties every seat, leaves the desks standing. |
| `employees` | Prints the ladder: tier, multiplier, hire cost and odds. |
| `spawnluck <amount>` | Luck every employee spawn rolls at, server-wide. Not saved. |

Employee names carry spaces, so quote them: `spawnnpcs 3 "Tie Guy"`.

## Upgrades

| Command | What it does |
| --- | --- |
| `giveupgrade <players> <node\|all>` | Grants a tree node free, effect and all. `all` grants the whole tree in parent order. |
| `clearupgrades <players>` | Unowns every node and puts multipliers, defense and pads back to fresh-save values. |

## Data and rolling

| Command | What it does |
| --- | --- |
| `resetdata <players>` | Wipes the save and kicks them, so they rejoin on a fresh profile. |
| `odds <variants\|employees> [rolls] [luck]` | Draws off the real roll path and prints what landed against what should have. |

## Client-side

These run entirely on your own client and never reach the server.

| Command | What it does |
| --- | --- |
| `previewmodel <component> <variant>` | Viewport window of one component model, spinning, with its odds. |
| `partsdemo [build\|clear\|goto]` | Builds the every-variant showcase in the sky, clears it, or drops you at it. |

## Aliases

`floor`, `desk`, `fire`, `hire`, `npc`, `spawnnpc`, `toplot`, `upgrade`, `sim`, `serverluck`,
`preview`. Cmdr's own defaults (`help`, `teleport`, `kill`, `respawn`, `announce`, `bind`, `alias`,
`echo`, `run`, …) are registered too.

## Layout

| Where | What |
| --- | --- |
| `src/Server/Commands/` | One `Name.luau` definition plus a `NameServer.luau` implementation per command. |
| `src/Server/CmdrTypes/` | Argument types — the enums the definitions name by string. |
| `src/Shared/Console/CommandUtil.luau` | Shared helpers. Not in `Commands/`, which Cmdr registers wholesale. |
| `src/Server/Services/CmdrService.luau` | Registration and the admin hook. |
| `src/Shared/Controllers/CmdrController.luau` | Activation key, place name, client-side hook. |

Cmdr moves the definition modules into `ReplicatedStorage.CmdrClient.Commands` at boot, so a
definition may only require replicated things — `Configs`, not `Services`. Anything with `Server` in
its file name stays on the server.

## Adding one

```luau
-- Thing.luau
return {
	Name = "thing",
	Description = "Does the thing.",
	Group = "Admin",
	Args = {
		{ Type = "players", Name = "Players", Description = "Who to do it to" },
	},
}
```

```luau
-- ThingServer.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local CommandUtil = require(Shared.Console.CommandUtil)

return function(_Context, Targets: { Player }): string
	return CommandUtil.ForEach(Targets, function(Target: Player, Data: any): string
		return "did the thing."
	end)
end
```

`CommandUtil.ForEach` is the per-player walk that skips anyone whose save has not loaded.

For a command that runs on the client instead, drop the `Server` file and put a `ClientRun` function
in the definition — keeping its requires inside the function body, since the server loads the
definition too. Client-run commands skip the server's admin hook.
