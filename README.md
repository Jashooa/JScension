# Accessibility

Accessibility is a one-button rotation addon for the **Ascension 3.3.5a World of Warcraft client**.

It evaluates a configurable priority list of spells and conditions, selects a usable target, and casts the first matching action. The project has two cooperating parts:

```text
WoW addon (Lua)
    │  Compatibility global
    ▼
Injected Compatibility shim (Win32 C)
    │  client API and trusted script execution
    ▼
Ascension 3.3.5a client
```

The project is client-build-specific. It is **not a retail WoW addon** and the native shim must not be used against a different client build.

## Components

### `Accessibility/`

The addon contains the rotation engine and user interface:

- `Core/` — profiles, conditions, targeting, rotation evaluation, configuration, and the shim boundary.
- `Game/` — unit, aura, spell, cast, cooldown, and input state.
- `UI/` — rotation button, settings panels, rule editor, and log panel.
- `Utils/` — constants, logging, coercion, spell selection, and tooltip helpers.
- `Libs/` — bundled Ace3 libraries.
- `tests/` — pure Lua contract tests.

The addon exposes:

- `/acc` for the configuration editor and commands;
- a manual “cast next spell” binding;
- an auto-rotation toggle;
- configurable rotations, conditions, target selectors, pulse timing, and failure handling.

`Core/Compatibility.lua` is the only Lua module that touches the raw `Compatibility` global. Keeping that boundary narrow lets the rotation engine remain independent of the native implementation.

### `Compatibility/`

The native component builds two Win32 binaries:

- `compatibility.dll` — injected into the running Ascension client;
- `compatibility.exe` — one-shot injector for the DLL.

The shim provides the trusted Lua bridge used by the addon. It also implements client-specific operations such as:

- protected script execution;
- spell casting and cast cancellation;
- action-bar use;
- object-manager lookup;
- visible-unit enumeration and target selection;
- unit position and scale lookup;
- range counting;
- line-of-sight checks;
- ground-target confirmation.

The shim validates the client layout before registering anything. It refuses to continue when the expected function bytes or client structures do not match the supported build.

## Requirements

Build and deployment currently assume:

- Linux with Bash;
- Wine and a working Ascension 3.3.5a installation;
- Lua 5.1 (`lua5.1`) for addon tests;
- an i686 MinGW-w64 compiler (`i686-w64-mingw32-gcc`);
- the matching i686 MinGW objdump command;
- the game running inside the configured Wine prefix.

The native shim targets the 32-bit client. Its addresses, calling conventions, object layouts, and byte signatures are specific to the supported Ascension build.

## Local setup

Copy the machine-specific configuration template:

```sh
cp scripts/config.example.sh scripts/config.sh
```

Edit `scripts/config.sh` and set at least:

- `PREFIX` — the Wine prefix containing the game;
- `GAME_DIR` — the Ascension installation directory;
- `WINE` — the Wine executable;
- `MINGW_CC` and `MINGW_OBJDUMP` if they are not on `PATH`.

The default paths deploy the addon to:

```text
<Game directory>/Interface/AddOns/Accessibility
```

and the native artifacts to:

```text
<WINE prefix>/drive_c/local
```

The launcher-managed game files are left untouched except for the addon directory.

## Build and test

Run the complete local contract suite:

```sh
scripts/test.sh
```

This runs the native C tests and the Lua tests in `Accessibility/tests/run.lua`.

Build the native artifacts:

```sh
scripts/build.sh
```

Build output is written to `bin/`, which is ignored by Git. The build verifies the callback descriptor bytes required by the Ascension client before installing the artifacts.

## Deploy and run

Deploy both components after building or changing either side:

```sh
scripts/deploy.sh
```

Start the Ascension client and enter at least the login screen. Then inject the shim once:

```sh
scripts/inject.sh
```

The injector locates the Ascension game window, loads `compatibility.dll`, and refuses to inject a duplicate copy. The shim validates the client layout before registering the Lua global. Check the shim log beside the deployed DLL and the in-game compatibility status before enabling auto rotation.

The injector is intended only for the configured Ascension client and Wine prefix. Do not use it with retail WoW or another client build.

## Development notes

- Keep client-specific addresses, signatures, and structure offsets in `Compatibility/client_layout.h` and its validation code.
- Keep addon access to the native bridge inside `Accessibility/Core/Compatibility.lua`.
- Do not call protected game functions directly from addon code.
- Do not byte-patch the client or use `winedbg`.
- Run `scripts/test.sh` before deployment.
- Native artifacts belong in `bin/`; machine-specific configuration belongs in `scripts/config.sh`.

## Repository layout

```text
Accessibility/       Lua addon
Compatibility/       Win32 shim, injector, and native tests
Plan/                Design notes
scripts/             Configuration, build, test, deploy, and injection scripts
bin/                 Ignored native build output
```
