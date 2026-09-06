# QuickCenter.koplugin

**QuickCenter — Quick Actions + Control Center for KOReader.**

A standard KOReader plugin migrated and refactored from the older patch
(`koreader/patches/2-quickcenter.lua`, kept in this repository's history for reference).
Features are fully preserved:

- **Quick Actions (快捷操作)** with 5 action types, plus a menu **recorder** that
  captures any menu navigation as a reusable action
- **Control Center panel** rendered as its own top-level menu tab with frontlight /
  warmth sliders, layout & appearance options (shape, background, button size, labels…)
- **Custom icons & icon picker**: Nerd Font glyphs, system icons and icon files;
  **system icon replacement**
- **UI font switching** (regular / bold / mono font families, whole-UI replacement)
- **Dispatcher gesture actions** and **multi-profile configuration management**

- Author: [Arin-Chin](https://github.com/Arin-Chin)
- License: AGPL-3.0 (same as KOReader)
- Version: 1.1.0 (plugin form, modular layout)

## Installation

1. Copy the contents of this repository (or just the whole folder) into the KOReader
   plugin directory:

   ```bash
   # e.g. clone directly, then symlink/copy
   git clone https://github.com/Arin-Chin/QuickCenter.koplugin.git
   cp -r QuickCenter.koplugin/* <koreader>/plugins/quickcenter.koplugin/
   ```

   Final layout on device:

   ```
   <koreader>/plugins/quickcenter.koplugin/
   ├── main.lua
   ├── qc_config.lua
   ├── qc_icons.lua
   ├── qc_scan.lua
   ├── qc_uifont.lua
   └── _meta.lua
   ```

2. Start KOReader → **Tools (gear) → Plugin manager → User plugins** and make sure
   `QuickCenter` is enabled (enabled by default).
3. Restart KOReader so the plugin gets loaded.

> Uninstall: disable (or delete) the plugin in the Plugin manager and restart.
> Your configuration at `koreader/settings/quickcenter.lua` is kept and reused if you
> re-enable later; delete it manually if no longer needed (the plugin dialog also offers
> a "delete settings" action).

## Repository layout

```
├── main.lua          entry/skeleton: plugin class & lifecycle (registerToMainMenu /
│                     addToMainMenu), action registry & built-in actions, panels /
│                     dialogs, TouchMenu & related patch installation
├── qc_config.lua     configuration leaf module (unit-testable): defaults, serializer,
│                     atomic save/load, setting accessors
├── qc_scan.lua       plugin/patch scanner leaf module: PluginScan, TOUCHMENU_STUB,
│                     menu-item tree search
├── qc_uifont.lua     UI font switcher leaf module: font-family replacement, picker dialogs
├── qc_icons.lua      icons leaf module: Nerd Font, icon cache, file/system icon browser
│                     & picker
├── spec/             busted-style unit tests (qc_config) + dependency-free runner
├── _meta.lua         plugin metadata (shown in the Plugin manager even when disabled)
└── .luacheckrc       luacheck configuration
```

Layering: the four `qc_*` leaf modules only depend on KOReader core APIs and on
`qc_config`; each is `require`d (and cached) once at plugin load. `main.lua` keeps the
body 1:1 with the original patch so it can be diffed against upstream; cross-file
references are wired through the "module assembly" alias block and the `QC` bridge table
at the top — no circular requires, no `_G` pollution.

## Differences from the original patch

| Aspect | Patch (`patches/2-quickcenter.lua`) | This plugin |
| --- | --- | --- |
| Loading | Auto-loaded at startup, no lifecycle | Standard PluginLoader: `main.lua` is only `dofile`d while **enabled**; disabling means it is never loaded |
| Global scope | 18 functions/tables written to `_G` | All moved to module locals: `QC` bridge table + `qc_*` module exports, no `_G` writes |
| Layout | Single ~5700-line file | Entry + 4 leaf modules (logic kept line-by-line, structural moves only) |
| Plugin class | none | `WidgetContainer:extend` + `init()` / `addToMainMenu()` / `onClose()` |
| Menu entry | Injected into the gear menu, patching `*_menu_order` order tables | Standard `registerToMainMenu` + `addToMainMenu` (lands in the *More tools* submenu, managed natively by KOReader) |
| Config file | `settings/quickcenter.lua` | **Unchanged**: same path, same read/write format & keys |
| Gestures | 3 Dispatcher actions + a re-register-on-execute fallback wrapper | Same 3 actions; the `Dispatcher.execute` global rewrite is removed (see below) |

## Notable fixes in this rewrite

1. **Font-patch wrap growth** — the old `applyUIFontChanges()` wrapped
   `menu/touchmenu.updateItems` once *per font change*, growing an unbounded wrapper
   chain that captured stale fonts. Now each module is wrapped exactly once
   (`_qa_font_patch_done` guard) and the wrapper reads the **current** font overrides on
   every run.
2. **Modular split** — leaf modules each get their own local-variable budget (no more
   pressure against Lua's 200-active-locals limit); `main.lua` is ~4100 lines.
3. **Standard menu integration** — no more patching of `FileManagerMenuOrder` /
   `ReaderMenuOrder` or `menu_items`; `addToMainMenu` with `sorting_hint = "more_tools"`
   is used instead (required, otherwise the menu sorter would label the item with a
   `NEW:` prefix and drop it into the first tab). Panel-tab injection is kept — there is
   no official API for it.
4. **Lint + unit tests** — `.luacheckrc` (luajit std) included; `spec/qc_config_spec.lua`
   covers default-generation, cross-restart persistence round-trip, serializer escaping,
   and corrupt-config auto-backup.

Additionally: removed the per-`Dispatcher:execute` re-registration wrapper (it clashed
with third-party wrappers on the same method and was unnecessary given plugin-load
timing), and made the config serializer's key sort use an explicit comparator
(numeric keys first — deterministic, and safe under Lua 5.3+ `table.sort` semantics).

## Usage

- **Menu entry**: Main menu → gear/tools tab → **More tools** → **QuickCenter** — opens
  the full settings dialog (quick actions, panel layout, icon picker, system icon
  replacement, UI font switching, shortcuts…).
- **Control Center panel**: a tab (default star icon, configurable) appears at the front
  of the menu. Hold the empty panel area, or use the "Settings" button, to open the
  QuickCenter settings; panel buttons support tap / long-press editing as before.
- **Gesture actions** (bind under gear → Gesture manager; bindings persist in
  `settings/dispatcher.lua` across restarts):
  - `quick_actions_panel` — open the Control Center panel
  - `qa_settings_action` — open QuickCenter settings
  - `qa_shortcuts_menu` — open the shortcuts menu
- **Configuration**: `koreader/settings/quickcenter.lua` (auto-generated on first run
  when missing; existing files are reused as-is). Icons may be placed in
  `koreader/icons/` or similar directories.

## Enable / disable behavior

- Disable the plugin and restart: menu entry, panel tab, gesture actions and the
  font/icon patches are all gone (they are only injected while the plugin's `main.lua`
  is loaded).
- Note: these injections are method-level wrappers on KOReader UI modules; the plugin
  framework does not unwrap them at runtime, so always restart after toggling. If a
  gesture still references one of the three action names while disabled, executing it is
  a silent no-op and does not affect anything else.

## Development: lint & tests

```bash
# static checks (luarocks install luacheck)
cd quickcenter.koplugin && luacheck .

# unit tests — option A: real busted
busted quickcenter.koplugin/spec/qc_config_spec.lua

# option B: dependency-free runner (Node + fengari: cd spec && npm i fengari)
node quickcenter.koplugin/spec/run_spec.js
```

Tests run against an in-memory filesystem (the runner stubs `io/os/logger/datastorage/json`)
and never touch real disk.

## Version compatibility

The plugin relies on several KOReader internals (TouchMenu panel construction, tab
injection, font replacement) that may change between releases; the compatible range
matches the original patch. After a KOReader upgrade, if the panel or menus misbehave,
check the corresponding internal modules in the KOReader source. Panel-related patches
are concentrated at the tail of `main.lua` (grep for `_qs_patched`).
