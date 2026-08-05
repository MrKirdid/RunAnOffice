# Changelog

## 0.1.0 (2026-07-28)

Initial release. Ground-up reimagining of Cmdr:

- Strict typing throughout the engine under the new Luau type solver; command
  callbacks receive an `args` record whose type is derived from the definition by a
  user-defined type function (`ArgsOf`).
- Definitions are pure data; implementations attach at registration
  (`Kmdr.implement`) — no `FooServer.luau` filename conventions, no script
  reparenting. Server→client metadata sync powers autocomplete for server commands.
- Guards replace hooks; commands with server implementations are blocked until a
  guard exists (outside Studio).
- Single-`resolve` argument types (validation + autocomplete + parsing in one path),
  `listOf`/`enumOf` factories, ~30 built-in types.
- Modern command bar: fuzzy matching, cursor-aware completion, prefix-filtered
  history, fish-style ghost text, word-level editing shortcuts, live inline
  validation, signature help.
- Fusion 0.3 interface with critically-damped springs (layout), linear fades
  (transparency), typewriter output and per-letter accent text animation.
- Quote-aware parser with exact character spans; quoted elements inside comma lists
  (fixes Cmdr #398-class issues); greedy `text` type instead of argument mashing.
