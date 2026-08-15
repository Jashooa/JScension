# Accessibility

A one-button rotation addon for the Ascension 3.3.5a WoW client, plus the
injected shim that lets it cast protected spells. This repo is the
`Solution/` folder.

## The two components

- **`Accessibility/`** — the addon (Lua + bundled Ace3 libs), loaded by
  `Accessibility.toc` with `Accessibility.lua` as the entry point.
- **`Compatibility/`** — C source for a Win32 shim DLL and an injector EXE
  (built with mingw-w64). The shim is injected into the game and exposes the
  trusted `Compatibility` global that the addon casts through.

## The addon's folders

- **`Utils/`** — helpers that don't depend on live game state: constants,
  logging, coercion, the spellbook cache, the tooltip helper.
- **`Game/`** — how live game state is read: units, auras, casts.
- **`Core/`** — the engine and configuration: the rotation rule engine, the
  profile, the condition registry, the shim seam, and the options tree.
- **`UI/`** — frames: the in-world cast button, the rule editor panel, and
  one reusable widget (`Widgets/TitleButtonGroup.lua`).
- **`Libs/`** — vendored Ace3 libraries.
- **`tests/run.lua`** — pure-Lua test suite (`lua5.1 tests/run.lua`); it
  fakes the WoW API and exercises the engine without frames.

## Root scripts

- `deploy.sh` — build the shim into `bin/`, deploy the addon to the game's
  `Interface/AddOns/`, install the shim to `C:\local`.
- `inject.sh` — inject the shim into the running game (after every restart).
- `config.sh` — shared paths (prefix, game dir, wine, file names).

## Notes

- Never byte-patch the client or use `winedbg`.
- Only write into the game's `Interface/AddOns/`; shim artifacts go to
  `C:\local`, which the launcher does not manage.
- Config UI is declarative AceConfig, except the two registered AceGUI
  widgets (`TitleButtonGroup`, `RotationPanel`).
- No abbreviated words in names. Code docs = comments, not READMEs.
  Conventional Commits.
