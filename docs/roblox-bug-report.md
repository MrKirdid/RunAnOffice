# Studio playtest drops to ~10 FPS whenever the window is focused

**Category:** Studio Bugs → Performance

## Summary

Since **August 27**, every playtest (F5/Play) in Studio runs at **~10 FPS (90–100 ms/frame)
while the Studio window is focused**, and at full speed (100+ FPS) the moment the window
loses focus. Edit mode is unaffected. The Roblox Player client is unaffected. Every place
shows it, including near-empty ones.

## Cause: server-side experiment channel

My account is enrolled in the channel **`zfrmdrawmoderatetarget30to60fpsaug27`**
(confirmed in Studio logs: `[FLog::ClientRunInfo] The channel is zfrmdrawmoderatetarget30to60fpsaug27`).

A friend with near-identical hardware, the same Studio version (**0.736.0.7361346**,
`version-268c7d941ba34c1a`), and no enrollment (empty `SFStringRCCChannelName`) does not
have the problem. Diffing our `StudioAppSettings.json` files shows the experiment delivers,
among others:

```
FStringFRMLockstepProfileOverride = {"FrameTime":{"2-13":34,"14":29,"15":24,"16-21":19}, ...}
DFStringChannelName = ZFRMDrawModerateTarget30To60FpsAug27
```

On my machine the lockstep profile lands at ~95 ms/frame focused (not the intended 30–60 FPS
band), and inverted: focused is throttled, background runs free.

## Measurements

- Focused playtest: 90–100 ms/frame constant (median over 30 s windows), <1 ms of that is
  script time; GPU ~1.3 ms; render thread ~2.2 ms — main thread blocked, not loaded.
- Unfocused same playtest: 7–10 ms/frame.
- Edit mode focused: normal.
- Roblox Player client, same machine, same game: normal.
- Reproduces after full Studio reinstall, PC reboot, all plugins removed, on multiple places.

## System

- Windows 11 Home 10.0.26200, RTX 3070 (driver 32.0.16.1656), 32 GB RAM
- Monitors: 3840×2160 @ 240 Hz + 3440×1440 @ 165 Hz
- Studio 0.736.0.7361346 (`version-268c7d941ba34c1a`)

## Request

Please pull my account out of this experiment or fix/kill the
`ZFRMDrawModerateTarget30To60FpsAug27` rollout — it makes Studio unusable for playtesting.

Related report with the same symptom:
https://devforum.roblox.com/t/significant-fps-drop-in-roblox-studio-when-the-engine-window-is-focused/4706040
