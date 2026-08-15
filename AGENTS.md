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
  provides a trusted execution seam; `Core/Compatibility.lua` documents how
  it is used.

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

## Layout — folders by role, TOC in load order

The addon's Lua files are grouped by role: `Utils/` helpers, `Game/` live
game-state readers, `Core/` engine + configuration, `UI/` frames. The TOC
loads them in that order (entry file last) so each file's dependencies are
already loaded. There is no dependency rule between the folders — a file
uses whatever it needs (`Core/Config.lua` calls `ns.RotationButton`, so Core
reaches into UI).

The grouping exists for three reasons:

**1. The engine must be testable without frames.** `Core/` (rotation engine,
profile, conditions) never creates a frame or touches AceGUI — it reads game
state through `Game/` and helpers through `Utils/`, both of which the test
harness fakes with a plain table. That is why the engine lives apart from the
UI: the pure-Lua suite in `tests/run.lua` loads only `Utils`+`Game`+`Core`
and exercises real decision logic against a fake WoW API.

**2. Each fact about this client lives in one place.** The client diverges
from stock WoW in small ways (no spell-ID lookup table; `GetSpellInfo` has no
ID return; fontstrings can't take mouse events). The file owning each fact
is the only place it is encoded:

- `Game/` — how live game state is read (units, auras, casts).
- `Utils/SpellPicker.lua` — the spellbook's name-keyed cache, the single
  owner of "spells are stored by name".
- `Utils/SpellTooltip.lua` — how tooltips get attached, the single owner of
  "use a real mouse frame, not the fontstring".
- `Core/Compatibility.lua` — the only file that knows the injected shim
  exists, the only place a protected call is made. Every other module calls
  `Compatibility.Cast` without knowing how it works, so a change to the
  shim's protocol touches one file.

**3. `Core/` vs `UI/` is data vs frames.** `Core/Config.lua` builds the
declarative AceConfig option tree — data, no widgets — and is therefore
testable. The actual frame code lives in `UI/`: `RotationButton.lua` (the
in-world button), `RotationPanel.lua` (the rule editor), and the one reusable
widget, `Widgets/TitleButtonGroup.lua`. UI code is deliberately kept thin and
explicitly excluded from the test harness, because layout and mouse behaviour
are client behaviour no fake can verify.

`Compatibility/` (the injected DLL + injector, built with mingw) is the one
non-Lua component. It is a native peer of `Core/Compatibility.lua`, not part
of the addon's Lua load order.


## Two non-obvious rules the code comments will not save you from

- **Rebuild the panel only on a deferred one-frame `OnUpdate`, never
  synchronously from a button callback.** Releasing AceGUI children while the
  clicked button's callback is still on the stack pools the very widget being
  clicked and the whole rule list disappears. The panel's
  `NotifyPanelChanged` already does the right thing — preserve that.
- **After an in-place panel rebuild, re-run the parent's layout** so the
  hosting ScrollFrame's content height and scrollbar range track the new
  content length. `RenderPanel` already calls `self.parent:DoLayout()` — keep
  it when touching the render path.

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
