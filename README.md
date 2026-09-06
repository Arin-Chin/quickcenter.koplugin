# QuickCenter.koplugin

> **Quick Actions + Control Center for KOReader — a fast, configurable, gesture-friendly shortcut hub.**

> **Author**: [Arin-Chin](https://github.com/Arin-Chin) · **License**: AGPL-3.0 · **Compatible**: KOReader (LuaJIT)

---

## 📖 概述 / Overview

QuickCenter is a standard KOReader **plugin** migrated from the patch
`koreader/patches/2-quickcenter.lua` (kept in this repository's history for reference).
It is loaded through the official PluginLoader: `main.lua` is only executed while the
plugin is **enabled**, and it never writes to `_G`.

| Feature | Description |
| :--- | :--- |
| ⚡ **Quick Actions** | Record, edit and manage frequent actions of 5 types; run them from a shortcut menu or by gesture |
| 🎛️ **Control Center** | A one-tap action panel injected as the first menu tab (Filemanager & Reader), with layout, shape, slider, filter and gesture-behavior options |
| 🖼️ **Icons & Fonts** | Icon picker (Nerd Font / SVG / PNG), system icon replacement, and whole-UI font switching (Regular / Bold / Mono) |

<img src="pictures/1.QCpreview.png" alt="QuickCenter preview" width="400" />

### 快速安装 / Quick install

| Step | Action |
| :--- | :--- |
| 1 | Clone this repo and copy its contents to `<koreader>/plugins/quickcenter.koplugin/` |
| 2 | KOReader → gear **Tools → Plugin manager → User plugins** → enable `QuickCenter` |
| 3 | Restart KOReader |

> ⚠️ **Mutually exclusive with the old patch.** Do **not** install
> `2-quickcenter.lua` into `koreader/patches/` while this plugin is enabled — both inject
> the same menu tab and settings entry.

| Scenario | Recommendation |
| :--- | :--- |
| Following upstream patch releases closely | Keep using the patch form (see repository history) |
| Want standard enable/disable via the Plugin manager | Use this plugin |

> 💡 **Inspiration**: [kopatches](https://github.com/gytwo/kopatches) ·
> [quickui.koplugin](https://github.com/gytwo/quickui.koplugin) ·
> [simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin) ·
> [KOReader.patches](https://github.com/joshuacant/KOReader.patches)

---

## 🚀 核心功能 / Core Features

### 1. ⚡ Quick Actions

| Feature | Description |
| :--- | :--- |
| **Custom actions** | 5 types: folder / collection / plugin / system (Dispatcher) / **recorded menu action** |
| **Menu recording** | Record any menu path as a reusable action; its view is customizable when editing |
| **Edit actions** | Add / rename / delete; existing custom actions are grouped under *Existing Actions*; check *Add to Shortcut Menu* to promote one to a shortcut |
| **Shortcut menu** | Manage shortcuts (check/uncheck to remove); a gesture can open the runnable list without a title bar |

<table>
  <tr>
    <td><img src="pictures/02-quick-actions-menu.png" alt="Quick Actions menu" width="400" /></td>
    <td><img src="pictures/03-edit-quick-actions.png" alt="Edit Quick Actions" width="400" /></td>
  </tr>
</table>

<table>
  <tr>
    <td><img src="pictures/04-shortcut-menu.png" alt="Shortcut menu" width="400" /></td>
    <td><img src="pictures/05-shortcut-menu-gesture.png" alt="Gesture-launched shortcut menu" width="400" /></td>
  </tr>
</table>

### 2. 🎛️ Control Center

A customizable action panel injected as the **first tab** of the top menu (Filemanager &
Reader), plus everything about its buttons.

| Setting | Options / Description |
| :--- | :--- |
| **Built-in actions** | Wi-Fi / night mode / rotate / screenshot (4 s) / continue reading / search / restart / quit / power / HTTP server / font list / switch UI font |
| **Arrange buttons** | Reorder panel buttons with ▲ / ▼ (QuickCenter-style box, back navigation) |
| **Add / remove buttons** | Checkbox list of available actions (QuickCenter-style box, back navigation) |
| **Button layout** | Auto (flow by panel width) / fixed grid (**rows × buttons per row**) |
| **Interface filter** | Show / hide actions per context: Filemanager / Reader / Common |
| **Button shape** | Round / Rounded square / Bare |
| **Button background** | Transparent / Solid / Light gray |
| **Slider style** | Line / Segmented |
| **Button size** | 60% ~ 150% (step 5%, default 100%) |
| **Label size** | 50% ~ 200% (step 10%, default 90%) |
| **Show labels** | Toggle |
| **Hold behaviors** | Hold a button → edit · hold the panel → open settings |
| **Frontlight / warmth sliders** | With optional value display and Min / Max shortcuts (requires device support) |

<img src="pictures/06-control-center-panel.png" alt="Control Center panel" width="400" />

<img src="pictures/07-control-center-menu.png" alt="Control Center menu" width="400" />

### 3. ⚙️ Settings

Settings are opened via the menu entry or the `qa_settings_action` gesture.

| Feature | Description |
| :--- | :--- |
| **Enable QuickCenter** | Enable / disable the panel tab (restart required) |
| **Config management** | Named presets: **Save** · **Edit** · **Reset** |
| **Appearance** | Panel tab icon · system icon replacement · UI font switching |

#### Config management

| Function | Description |
| :--- | :--- |
| **Save config** | Store the current configuration as a **named preset** |
| **Edit config** | Browse presets: **long-press to overwrite** with current settings, or open the submenu for update / rename / delete |
| **Reset config** | Restore factory defaults |

> Presets can be saved, overwritten and restored at any time — handy for switching between
> reading / night / travel setups.

<img src="pictures/08-settings-menu.png" alt="Settings menu" width="400" />

<img src="pictures/09-config-management.png" alt="Config management" width="400" />

#### Icon picker

| Source | Description |
| :--- | :--- |
| **Nerd Font** | Auto-scanned glyphs of the symbols font, with codepoint search |
| **SVG / PNG files** | Browse `koreader/icons/` and built-in icon dirs, with name filter |
| **System icon replacement** | Replace KOReader built-in icons (grid preview, batch apply / reset) |

#### UI font switcher

Replace the whole UI font (Regular / Bold / Mono) from installed fonts, with a live
preview and one-tap reset.

---

## 🔧 支持 / Support

| Entry | Location |
| :--- | :--- |
| **QuickCenter settings** | gear **Tools → More tools → QuickCenter** |
| **Control Center panel** | First tab of the top menu (configurable icon) |

| Gesture action | Dispatcher key | Description |
| :--- | :--- | :--- |
| Control Center panel | `quick_actions_panel` | Open the Control Center panel tab |
| QuickCenter settings | `qa_settings_action` | Open QuickCenter settings |
| Shortcut menu | `qa_shortcuts_menu` | Open the runnable shortcut list (no title bar) |

> Gesture bindings survive restarts — bind under gear → Gesture manager, stored in
> `koreader/settings/dispatcher.lua`. Action titles are localized together with the UI
> language.

**Enable / disable**: disable the plugin in the Plugin manager and restart — the menu
entry, panel tab, gesture actions and font/icon patches are no longer injected (they only
exist while the plugin's `main.lua` is loaded). The plugin framework does not unwrap
patches at runtime, so always restart after toggling; a stale gesture on the three action
names is a silent no-op while disabled.

---

## 📁 文件结构 / File Structure

```
QuickCenter.koplugin/            # repository root == plugin root
├── main.lua                     # entry: plugin class & lifecycle, action registry,
│                                #   panels/dialogs, TouchMenu patch installation
├── qc_config.lua                # config leaf module: defaults, serialize, atomic
│                                #   save/load, setting accessors
├── qc_scan.lua                  # plugin/patch scanner leaf module (PluginScan)
├── qc_uifont.lua                # UI font switcher leaf module
├── qc_icons.lua                 # icons leaf module: Nerd Font, pickers, caches
├── spec/                        # unit tests (qc_config) + dependency-free runner
├── _meta.lua                    # plugin metadata (shown when disabled)
├── .luacheckrc                  # luacheck configuration
├── pictures/                    # screenshots (referenced by both READMEs)
├── README.md                    # documentation (English)
└── README.zh_CN.md              # documentation (简体中文)
```

| File | Purpose |
| :--- | :--- |
| `main.lua` | Plugin entry: Quick Actions + Control Center + config management + icon/font tools |
| `qc_config.lua` | Configuration storage & accessors (sole leaf dependency of other modules) |
| `qc_scan.lua` | Plugin/patch discovery & menu-item tree search |
| `qc_uifont.lua` | Whole-UI font replacement & picker dialogs |
| `qc_icons.lua` | Nerd Font glyphs, icon cache, file/system icon pickers |
| `spec/` | Unit tests & runner (in-memory FS, no disk writes) |
| `_meta.lua` | Plugin metadata for the Plugin manager |
| `README.md` / `README.zh_CN.md` | Bilingual docs (mirrored structure) |

---

## ⚙️ 配置 / Configuration

All settings live in `koreader/settings/quickcenter.lua` (auto-generated on first run;
an existing file from the patch era is reused as-is — no migration needed).

| Group | Keys | Description |
| :--- | :--- | :--- |
| Panel | `qa_enabled` / `qa_slots` / `qa_*` | Panel enable, button order, shape, size, labels, sliders |
| Layout | `qa_layout_*` | Fixed button grid (enabled / rows / buttons per row) |
| Shortcuts | `qa_shortcuts` | Actions added to the shortcut menu |
| Presets | `saved_configs` | Named configuration presets |
| Appearance | `qa_tab_icon` / `qa_icon_overrides` / `ui_font_overrides` | Panel tab icon, system icon replacement, UI fonts |

---

## 🌐 国际化 / Internationalization

| Item | Description |
| :--- | :--- |
| Mechanism | UI strings are wrapped with gettext `_()`; labels follow KOReader's UI language |
| Default language | Simplified Chinese (fallback text embedded in code) |
| Translation files | No `.po` catalog shipped in this repository (KOReader l10n flow) |

---

## 📦 更新 / Changelog

| Date | Version | Notes |
| :--- | :--- | :--- |
| 2026-09-06 | 1.1.0 | Plugin form (first release of this repo): patch → plugin migration, modular split into `qc_*` leaf modules, standard menu entry (`addToMainMenu`), font-patch wrap-growth fix, removed `Dispatcher.execute` global rewrite, luacheck + unit tests |
| 2026-08-24 | patch | Deep refactor & fixes of `2-quickcenter.lua`: size −17%, dispatcher/Nerd-Font caches O(n²) → O(n), 3 latent crash fixes, `pcall`-guarded action execution (historical, see patch-era commits) |

---

## 🔌 兼容性 / Compatibility

| Item | Requirement |
| :--- | :--- |
| KOReader | Recent build (LuaJIT); verified on v2026.07 |
| Device | Frontlight / warmth sliders require device support |
| Icons | Nerd Font feature requires a Nerd Font symbols face |
| Dependencies | None beyond KOReader core APIs (no external library, no `os.execute`) |
| Configuration | `quickcenter.lua` schema unchanged since the patch era (`version = 1`) |

---

## 🧑💻 开发者信息 / Developer Info

| Item | Value |
| :--- | :--- |
| Author | [Arin-Chin](https://github.com/Arin-Chin) |
| License | AGPL-3.0 — see [gnu.org/licenses/agpl-3.0.en.html](https://www.gnu.org/licenses/agpl-3.0.en.html) |
| Docs convention | This file and `README.zh_CN.md` are kept in strict correspondence (same sections/tables/rows; identifiers, paths and screenshots byte-identical) |

Lint & tests:

```bash
luacheck .                                   # static checks (luarocks install luacheck)
busted spec/qc_config_spec.lua               # unit tests (busted)
node spec/run_spec.js                        # unit tests (Node + fengari, no install of busted)
```
