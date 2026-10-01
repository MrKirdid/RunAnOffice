# Run an Office

Office tycoon with gacha rolls on one of 8 player plots. Roll desk parts (Keyboard/Monitor/Computer) with rarity variants onto pads, carry and place them on desk slots, buy NPC employees who sit at desks, earn revenue (part value × variant value × employee multiplier) on an interval, spend it on desks and the upgrade tree. Stealing takes employees off other plots; the tree's Defense nodes bank a number nothing reads yet.

## Where things go

- Framework is **Unithub** (`mrkirdid/unithub`). Lifecycle is `Init` then `Start`. Units reach each other with plain `require(script.Parent.X)`.
- Services: `src/Server/Services/`. Controllers: `src/Shared/Controllers/` (Shared, not Client — they replicate).
- Unithub loads only ModuleScripts whose **direct parent is a Folder**; child modules of a module (e.g. `UpgradeTreeController/*.luau`) are not auto-loaded.
- Config: `src/Shared/Configs/`. Admins: `Configs/Admins.luau`.
- Admin console is **Cmdr** (`evaera/cmdr`, a server dependency in `ServerPackages/`), F2 via `Configs/Admins.luau`. Commands are `src/Server/Commands/<Name>.luau` + `<Name>Server.luau`, custom types `src/Server/CmdrTypes/`. Wired by `CmdrService` / `CmdrController`. Kmdr is gone from this project.
- `default.project.json` uses lowercase paths (`src/shared`) while disk is `src/Shared`. Works only because macOS is case-insensitive — don't "fix" one side without the other.

## What Rojo owns

Rojo owns only `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `ServerScriptService.ServerPackages`, `StarterPlayerScripts.Client`. **Everything else lives only in the place**: `ReplicatedStorage.Assets` (PlotTemplate, Parts, Desk, SFX, VFX, Animations, Employees, UI), Workspace (`Map`, `PlotContainer` — a ModuleScript code requires, `Desks`), StarterGui (`CancelUI` — its X now stashes the held part, see `StashController` — `FloorsUI`, `UpgradeTree`). Build those with the `roblox-world` skill.

## Networking

Blink 0.18.8. Edit `network.blink`, run `blink network.blink`. Output (`src/Shared/Networking/networking{Client,Server,Types}.luau`) is generated — never edit it. `Casing = Pascal`; `Yield: Promise` calls return TypedPromise.

- Declaration order sets packet ids.
- Wire ranges are gameplay limits — e.g. roll count is `u8(1..17)`. Change the range in the schema, not with server clamps.

## Data

`src/Shared/PlayerData.luau` — Dataservicetyped over ProfileStore. Keys `dev1.05` (Studio) / `prod1.05` (live). Server `require(PlayerData).server`, client `.client`. Read `Data.Cash()`, write `Data.Cash(Fn)`; server waits with `PlayerData.Service:waitForData(Player)`. Floors reach clients via player attribute (`PublishFloors` in PlotService), revenue via `RateAttribute`.

## UI

Only `UpgradeTreeController` uses Fusion 0.3 (panning in `PanZoom.luau`). Other UI controllers find place-built ScreenGuis in PlayerGui or build instances by hand. `_Index` also holds Fusion 0.2 (pulled in by Kore and Proximityprompt) — never import that one.

## Pacing

Desk prices (`Utilities/DeskPurchase.luau`) and tree costs (`Configs/Upgrades.luau`) are fitted, not hand-picked: `tools/pacing/` is a solo no-Robux bot sim that reads the configs. `python3 tools/pacing/sim.py` reports desk/node/tier timings, `fit.py --write` re-fits prices to the targets inside it, `audit.py` checks spread and player types. Targets: floors done at 8m / 1h / 3h / 7h. Re-run after touching parts, staff, luck, tree effects or prices. Fresh saves start with 1 roll pad (the tree adds 8); desk 2 must stay ≤ 500 so a new player can always afford a hire.

## Upgrade tree editor

`plugins/UpgradeTreeEditor.lua` is a Studio hex-grid editor for `src/Shared/Configs/Upgrades.luau`. It saves by POSTing to `python3 tools/treewriter.py` on `127.0.0.1:8790`. `Upgrades.luau` is **regenerated** by the plugin — keep notes in its header comments only.

## Gotchas

- `src/Shared/Controllers/RollingController.luau` names its table `RollingService`; Unithub registers it by filename.
- Rolls are gated by `Data.RerollPads()` (the schema comment saying `RollsUnlocked` is stale).
- The Studio MCP mouse tool can't start drags, so `UIDragDetector` interactions need manual testing.
