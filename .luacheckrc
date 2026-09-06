-- QuickCenter luacheck 配置
-- 运行：cd quickcenter.koplugin && luacheck .
-- （luacheck 安装：luarocks install luacheck）
std = "luajit"                 -- KOReader 运行于 LuaJIT(5.1)
max_line_length = false       -- 源文件保留原补丁的长行风格
quiet = false

-- 读取的已知全局（其余全局按未定义变量告警，便于抓笔误）
read_globals = {
    "G_reader_settings",
}

-- 忽略：诊断用的 unused（模块化后存在跨文件别名/顶层状态，由人工维护）
unused = false
unused_args = false

files["qc_config.lua"] = {}
files["qc_scan.lua"] = {}
files["qc_uifont.lua"] = {}
files["qc_icons.lua"] = {}
files["main.lua"] = {}
exclude_files = {
    "spec/",
    "README.md",
    "_meta.lua",   -- 纯数据表（会被插件管理器禁用时 dofile）
}
