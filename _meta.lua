-- QuickCenter 插件元数据。
-- KOReader 的 PluginLoader（frontend/pluginloader.lua）在插件被「禁用」时加载本文件
-- 以便在插件管理器中显示插件信息；插件「启用」时其中的字段（除 name 外）也会被
-- 合并到插件模块上。内容保持轻量，不依赖其他模块。
return {
    name = "quickcenter",
    fullname = "QuickCenter",
    description = "快捷中心：快捷操作 + 控制中心集成（由 koreader/patches/2-quickcenter.lua 迁移的插件版，配置沿用 koreader/settings/quickcenter.lua）",
}
