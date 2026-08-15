# Accessibility — one-button rotation for the Ascension 3.3.5a client

## What this is

A personal accessibility addon for the WoW 3.3.5a private-server client used
by Ascension ("Conquest of Azeroth"). The player has a disability, so the
addon reduces the rotation to one button: it walks a rule list and casts the
first rule whose gates (cooldown, range, mana, auras, conditions) pass.

The client is a custom fork (VMProtect-protected) of 3.3.5a. It diverges from
stock WoW in small but load-bearing ways — verify every API fact against
`research/addons/APIDocumentation/` (the game's own doc dump) or in-game,
never against third-party addons written for retail.

Two components live here:

- `Accessibility/` — the addon (Lua + bundled Ace3 libs).
- `Compatibility/` — the shim: a Win32 DLL injected into the game plus a
  small injector EXE, built with mingw-w64. The game's protected
  environment blocks addon code from calling secure functions, so the shim
  provides a trusted execution seam (see below).

## Hard constraints

- **Never byte-patch the client.** 409 runtime hooks + VMProtect; a patch
  would be detected or crash. `winedbg` is banned (crashes the protected
  client).
- **Never write into the game directory** except `Interface/AddOns/`. The
  launcher repairs its own files and deletes anything unknown. Shim
  artifacts go to `C:\local` (`$PREFIX/drive_c/local`), which the launcher
  does not manage.
- **Never change launcher config.**
- The addon's config UI is **declarative AceConfig only**. The only custom
  widgets are `UI/Widgets/TitleButtonGroup.lua` (a registered AceGUI
  container) and `UI/RotationPanel.lua` (the rule editor, also a registered
  AceGUI widget). No bespoke frame hacks beyond those.
- All artifacts and output in this conversation are ASCII-only.
- Test account is throwaway (`weirded.rsbot@gmail.com`); risky in-game tests
  happen only on it, and only after telling the user.

## Layout

```
Solution/
  Accessibility/
    Accessibility.lua        entry point (AceAddon)
    Accessibility.toc        load order: Utils -> Game -> Core -> UI -> entry
    Utils/                   cross-cutting helpers (may touch WoW API)
      Constants.lua Compare.lua Coerce.lua Log.lua
      SpellPicker.lua        cached spellbook resolver
      SpellTooltip.lua       GameTooltip attachment helper
    Game/                    live game-state readers
      Unit.lua Aura.lua Cast.lua
    Core/                    engine and configuration
      Compatibility.lua      the only seam to the injected shim
      Profile.lua            saved-variable schema + CRUD
      Conditions.lua         condition registry (types, fields, eval, describe)
      Rotation.lua           the rotation engine (NextRule / CastBest)
      Config.lua             declarative AceConfig option tree
    UI/
      Widgets/TitleButtonGroup.lua   reusable titled container with title-bar buttons
      RotationButton.lua     the in-world one-button cast button
      RotationPanel.lua      the rule editor (registered AceGUI widget)
    Libs/                    bundled Ace3 (AceConfig, AceGUI, ...) — vendored, committed
    tests/run.lua            pure-Lua test harness (lua5.1 tests/run.lua)
  Compatibility/
    shim.c                   the injected DLL (exposes the Compatibility global)
    injector.c               injects the DLL into the running game
    compatibility.def build.sh
  bin/                       build output (gitignored)
  config.sh                  shared paths (prefix, game dir, wine, names)
  deploy.sh                  build shim + deploy addon + shim
  inject.sh                  inject the shim into the running game
  research/                  RE notes, packet captures, API documentation
```

## The compatibility seam

`Core/Compatibility.lua` is the only file that touches the `Compatibility`
global installed by the injected DLL. Everything else calls through it:

- `Compatibility.Call(fmt, ...)` builds one Lua script string (values
  escaped with `%q`) and runs it through the shim in a trusted context.
- `Compatibility.Cast(name, id, selfCast)` wraps `CastSpellByName` /
  `CastSpellByID` — the addon never calls a protected function directly.
- `Compatibility.IsCompatible()` caches an `issecure()` probe result. The
  shim can attach after addon load, so a cached false re-probes once the
  `Compatibility` global appears. `/acc status` prints the live value.

The injector must be re-run after every game start: `./inject.sh` (or the
game restarts without the seam). Watch `drive_c/local/compatibility.log`.

## The rotation engine

Rules live in the profile as an ordered list. `Rotation.NextRule()` returns
the first rule that passes every gate; `Rotation.CastBest()` casts it. Gates:
target exists/alive, spell known, usable, cooldown, in range, every
condition, anti-spam. Conditions are data driven from `Core/Conditions.lua`'s
registry — adding a condition type touches only that file.

The panel (`UI/RotationPanel.lua`) renders the rule editor as a registered
AceGUI widget. It rebuilds in place on a deferred one-frame `OnUpdate` (never
synchronously from a button callback — releasing widgets mid-callback pools
the clicked button and breaks the UI). The hosting ScrollFrame is re-laid-out
after each rebuild so the scrollbar tracks content length.

## Conventions

- **No abbreviated words** in names: `healthPercent` not `healthPct`,
  `Compatibility` not `Compat`, `condition` not `cond`. Enforced by the user;
  do not regress it.
- **Code documentation = code comments**, not READMEs. ASD-STE100 style:
  short declarative sentences, one idea per comment.
- **Modular files.** No long code files; split logic into small modules.
- **Git commits: Conventional Commits** (`feat:`, `fix:`, `refactor:`,
  `test:`, `style:`, `chore:`).
- No git init, no formatter/linter runs — the user's tooling does that.
- Use the bundled Ace3 libs; never add a new external dependency.
- Python deps via `uv` if ever needed.

## Workflow

```sh
./deploy.sh   # build shim into bin/, deploy addon to Interface/AddOns,
              # install shim to C:\local
./inject.sh   # inject the shim into the running game (after every restart)
lua5.1 Accessibility/tests/run.lua   # run the pure-Lua test suite
```

The game must be restarted to pick up new files (the TOC is read at startup);
`/reload` suffices for changed existing files. The addon is deployed to
`$ADDON_DEST` (see `config.sh`).

The tests cover only what a fake WoW API can faithfully exercise: profile
sanitization, conditions, the rotation engine, the spellbook, the
Compatibility seam, and the Config option shape. Widget behaviour (layout,
mouse, tooltips, AceGUI pooling) is client behaviour and is verified in-game,
not by the harness.
