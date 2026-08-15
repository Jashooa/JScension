# Accessibility

A one-button rotation addon for the Ascension 3.3.5a WoW client, plus the
injected shim that lets it cast. This repo is the `Solution/` folder.

## Structure

```
Accessibility/          the addon (Lua + bundled Ace3 libs)
  Utils/                helpers (constants, logging, spellbook cache, tooltips)
  Game/                 game-state readers (units, auras, casts)
  Core/                 engine + config (rotation, profile, conditions, shim seam, options)
  UI/                   frames (cast button, rule editor, one reusable widget)
  Libs/                 vendored Ace3 libraries
  tests/run.lua         pure-Lua test suite (lua5.1 tests/run.lua)
Compatibility/          shim source (C: shim.c, injector.c, build.sh)
bin/                    build output (gitignored)
config.sh               shared paths
deploy.sh               build shim + deploy addon + shim
inject.sh               inject the shim into the running game
```

## Notes

- Never byte-patch the client or use `winedbg`.
- Only write into the game's `Interface/AddOns/`; shim artifacts go to
  `C:\local`.
- Config UI is declarative AceConfig, except the two registered AceGUI
  widgets (`TitleButtonGroup`, `RotationPanel`).
- No abbreviated words in names. Code docs = comments, not READMEs.
  Conventional Commits.
