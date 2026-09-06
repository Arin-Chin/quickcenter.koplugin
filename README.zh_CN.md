# QuickCenter.koplugin

**QuickCenter（快捷中心）—— KOReader 快捷操作 + 控制中心插件。**

由旧补丁 `koreader/patches/2-quickcenter.lua`（旧版文件保留在本仓库历史中，供对照）
迁移并重构而来的标准 KOReader 插件，功能与原补丁完全一致：

- **快捷操作（Quick Actions）**：5 种动作类型 + **菜单录制器**（把任意菜单操作路径录制成可复用动作）
- **控制中心面板**：作为独立菜单标签页呈现，含前光/色温滑杆与外观设置（形状、背景、按钮尺寸、文字标签等）
- **自定义图标与图标选择器**：Nerd Font 字形、系统图标、图标文件；**系统图标替换**
- **UI 字体切换**：常规/粗体/等宽三类字体族整体替换
- **Dispatcher 手势动作** 与 **多套配置方案保存/恢复**

- 作者：[Arin-Chin](https://github.com/Arin-Chin)
- 许可证：AGPL-3.0（与 KOReader 一致）
- 版本：1.1.0（插件形态 + 模块化重构）

## 安装

1. 把本仓库内容复制到 KOReader 插件目录（仓库根即插件本体）：

   ```bash
   git clone https://github.com/Arin-Chin/QuickCenter.koplugin.git
   cp -r QuickCenter.koplugin/* <koreader>/plugins/quickcenter.koplugin/
   ```

   设备上最终结构：

   ```
   <koreader>/plugins/quickcenter.koplugin/
   ├── main.lua
   ├── qc_config.lua
   ├── qc_icons.lua
   ├── qc_scan.lua
   ├── qc_uifont.lua
   └── _meta.lua
   ```

2. 启动 KOReader → **工具（齿轮）→ 插件管理 → User plugins**，确认 `QuickCenter`
   处于启用状态（默认启用）。
3. 重启 KOReader 使插件生效。

> 卸载：在插件管理器中禁用（或删除）该插件后重启即可。
> 配置 `koreader/settings/quickcenter.lua` 会被保留，重新启用后继续沿用；
> 不需要时可手动删除（插件管理对话框也提供「删除设置」入口）。

## 目录结构

```
├── main.lua          入口/骨架：插件类与生命周期（registerToMainMenu/addToMainMenu）、
│                     动作注册表与内置动作、面板与对话框主体、TouchMenu 等补丁安装
├── qc_config.lua     配置模块（叶子，可独立单测）：默认值/序列化/原子保存/加载/便捷访问器
├── qc_scan.lua       插件/补丁扫描模块（叶子）：PluginScan、TOUCHMENU_STUB、菜单项树搜索
├── qc_uifont.lua     UI 字体切换模块（叶子）：字体族整体替换、选择对话框、重启确认
├── qc_icons.lua      图标模块（叶子）：Nerd Font、图标缓存、文件/系统图标浏览器与选择器
├── spec/             busted 风格的单元测试（qc_config）+ 免安装 runner
├── _meta.lua         插件元数据（禁用时仍可在插件管理器中显示）
└── .luacheckrc       luacheck 配置
```

分层原则：`qc_*` 四个叶子模块只依赖 KOReader 核心 API 与 `qc_config`，在插件加载时
`require` 一次并缓存；`main.lua` 保留与原补丁一一对应的正文（便于对照上游），跨文件
引用通过顶部「子模块装配」别名块 + `QC` 桥接表接入——无循环依赖、不写 `_G`。

## 与原补丁的差异

| 项目 | 补丁版 | 本插件 |
| --- | --- | --- |
| 加载方式 | 启动时自动加载，无生命周期 | PluginLoader 标准加载：`main.lua` 仅在插件「启用」时被 dofile，禁用即完全不加载 |
| 全局污染 | 18 个函数/表写入 `_G` | 全部收敛为模块局部：`QC` 桥接表 + `qc_*` 子模块导出，不写 `_G` |
| 代码形态 | 单文件 ~5700 行 | 入口 + 4 个叶子模块（逻辑逐行保留，仅结构性搬移） |
| 插件类 | 无 | `WidgetContainer:extend` + `init()`/`addToMainMenu()`/`onClose()` |
| 菜单入口 | 注入工具菜单并改 `*_menu_order` 顺序表 | 标准 `registerToMainMenu` + `addToMainMenu`（归入 **More tools** 子菜单，由 KOReader 原生管理） |
| 配置文件 | `settings/quickcenter.lua` | **不变**：路径、读写格式与字段完全一致 |
| 手势 | 3 个动作 + 每次 execute 前重注册的兜底包装 | 动作不变；删除 `Dispatcher.execute` 全局重写（见下） |

## 本次重构的修复项

1. **字体补丁套娃**：原 `applyUIFontChanges()` 每次改字体都会给 `menu/touchmenu.updateItems`
   再包一层，包装链无限增长且捕获旧字体；现改为每个模块只包装一次（`_qa_font_patch_done`
   守卫），包装体每次执行时读取**当前**字体覆盖。
2. **模块化拆分**：叶子模块各自拥有独立局部变量预算（不再逼近 Lua 200 活跃局部变量上限），
   `main.lua` 降至约 4100 行。
3. **菜单入口标准化**：不再补丁 `FileManagerMenuOrder/ReaderMenuOrder` 与 `menu_items`，
   改用 `addToMainMenu` + `sorting_hint = "more_tools"`（否则 MenuSorter 会给条目加
   `NEW:` 前缀并丢进第一个标签页）。面板标签注入因无官方 API 而保留。
4. **lint 与单测**：`.luacheckrc`（luajit 标准）已就绪；`spec/qc_config_spec.lua` 覆盖
   默认值生成、跨重启持久化往返、序列化转义、损坏配置自动备份。

另：删除每次 `Dispatcher:execute` 都重注册动作的全局包装（避免与第三方插件对同一方法的
包装冲突；插件加载时机已保证注册），并让配置序列化的键排序使用显式比较器（数字键在前，
输出确定，且兼容 Lua 5.3+ 的 `table.sort` 语义）。

## 使用入口

- **菜单入口**：主菜单 → 工具（齿轮）标签 → **More tools** → **快捷中心** ——
  打开完整设置对话框（快捷操作、面板布局、图标选择、系统图标替换、UI 字体、快捷方式等）。
- **控制中心面板**：菜单顶部出现带 ⭐（可配置图标）的「控制中心」标签页；长按面板空白处
  或点“设置”按钮打开快捷中心设置；面板按钮支持点击/长按编辑（同补丁行为）。
- **手势动作**（工具 → 手势管理 绑定；绑定存于 `settings/dispatcher.lua`，重启保留）：
  - `quick_actions_panel` —— 打开控制中心面板
  - `qa_settings_action` —— 打开快捷中心设置
  - `qa_shortcuts_menu` —— 打开快捷操作菜单
- **配置文件**：`koreader/settings/quickcenter.lua`（缺失自动生成；已有配置直接复用）。
  图标可放在 `koreader/icons/` 等目录。

## 禁用/启用行为

- 禁用插件并重启后：菜单入口、控制中心标签、手势动作、字体/图标补丁全部不再生效
  （都只在插件 `main.lua` 被加载时注入）。
- 说明：注入为 KOReader 界面模块的方法级包装，插件机制不支持运行期解包，请修改后重启。
  手势若仍引用三个动作名，禁用后执行会静默无效果，不影响其它功能。

## 开发：lint 与测试

```bash
# 静态检查（需 luarocks install luacheck）
cd quickcenter.koplugin && luacheck .

# 单元测试：方式 A —— 真 busted
busted quickcenter.koplugin/spec/qc_config_spec.lua

# 方式 B —— 免安装 runner（需 Node + fengari：cd spec && npm i fengari）
node quickcenter.koplugin/spec/run_spec.js
```

测试在“内存文件系统”上运行（runner 会 stub `io/os/logger/datastorage/json`），
不会读写真实磁盘。

## 版本兼容性提示

插件深度依赖 KOReader 内部结构（TouchMenu 面板构建、标签注入、字体替换等），
兼容范围与原补丁相同；升级 KOReader 后若面板/菜单表现异常，请以 KOReader 实际行为
为准。面板相关补丁集中在 `main.lua` 尾部（可 grep `_qs_patched`）。
