-- qc_scan.lua — QuickCenter 插件/补丁扫描模块（由 main.lua 拆分，逻辑未改动）
-- 职责：独立于 PluginLoader 的插件枚举/探测（TOUCHMENU_STUB 桩、addToMainMenu 探测、
-- 菜单项树搜索、补丁动作发现），结果带缓存。不依赖本插件其它模块。
local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")

-- ============================================================
-- 插件 / 补丁扫描（独立实现，扫描结果缓存：插件列表运行期不变）
-- ============================================================
-- 菜单回调的桩对象：插件 addToMainMenu 会向其写入菜单项
local TOUCHMENU_STUB = {
    closeMenu = function() end,
    onClose = function() end,
    updateItems = function() end,
    handleEvent = function() return false end,
}

local PluginScan = {}
PluginScan.SENTINEL = "__menu_callback"
PluginScan.SUBMENU = "__menu_submenu"

local EXCLUDED_PLUGINS = { zen_ui = true }
local LAUNCH_METHODS = { "onShow", "show", "open", "launch", "onOpen" }

local function plugin_loader()
    local ok, loader = pcall(require, "pluginloader")
    return ok and loader or nil
end

local function live_uis()
    local out = {}
    local fm_mod = package.loaded["apps/filemanager/filemanager"]
    if fm_mod and fm_mod.instance then out[#out + 1] = fm_mod.instance end
    local reader_mod = package.loaded["apps/reader/readerui"]
    if reader_mod and reader_mod.instance then out[#out + 1] = reader_mod.instance end
    return out
end

local function enabled_plugin_names()
    local names = {}
    local loader = plugin_loader()
    if not (loader and type(loader.loadPlugins) == "function") then return names end
    local ok, enabled = pcall(loader.loadPlugins, loader)
    if not ok or type(enabled) ~= "table" then return names end
    for _i, plugin in ipairs(enabled) do
        if type(plugin) == "table" and type(plugin.name) == "string" then names[plugin.name] = true end
    end
    names.zen_ui = nil
    return names
end

local function is_callable(value)
    if type(value) == "function" then return true end
    local mt = type(value) == "table" and getmetatable(value) or nil
    return type(mt) == "table" and type(mt.__call) == "function"
end

-- 用空表探测插件的 addToMainMenu，取到该插件的主菜单项
local function probe_menu_entry(mod, key)
    if type(mod.addToMainMenu) ~= "function" then return nil end
    local probe = {}
    local ok = pcall(mod.addToMainMenu, mod, probe)
    if not ok then return nil end
    local entry = probe[key]
    if entry == nil and type(mod.name) == "string" then entry = probe[mod.name] end
    if entry == nil then
        local only, count = nil, 0
        for _k, value in pairs(probe) do
            if type(value) == "table" then count = count + 1; only = value end
        end
        if count == 1 then entry = only end
    end
    return type(entry) == "table" and entry or nil
end

local function text_without_glyph(text)
    if type(text) ~= "string" then return nil end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function entry_text(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.text_func) == "function" then
        local ok, text = pcall(entry.text_func)
        if ok then return text_without_glyph(text) end
    end
    return text_without_glyph(entry.text)
end

local function find_method(mod, key)
    for _i, method in ipairs(LAUNCH_METHODS) do
        if is_callable(mod[method]) then return method end
    end
    local camel = "on" .. key:sub(1, 1):upper() .. key:sub(2)
    if is_callable(mod[camel]) then return camel end
    local entry = probe_menu_entry(mod, key)
    if entry then
        if type(entry.callback) == "function" then return PluginScan.SENTINEL end
        if entry.sub_item_table ~= nil or entry.sub_item_table_func ~= nil then return PluginScan.SUBMENU end
    end
end

local function add_candidate(out, seen, key, mod)
    if type(key) ~= "string" or key == "" or EXCLUDED_PLUGINS[key] or seen[key] or type(mod) ~= "table" then return end
    local method = find_method(mod, key)
    if not method then return end
    seen[key] = true
    local entry = probe_menu_entry(mod, key)
    local title = entry_text(entry)
    if not title or title == "" then title = key:sub(1, 1):upper() .. key:sub(2) end
    out[#out + 1] = { key = key, method = method, title = title }
end

-- 解析菜单项的子菜单表（兼容 sub_item_table / sub_item_table_func）
local function menuSubTable(item)
    if type(item) ~= "table" then return nil end
    local sub = item.sub_item_table
    if sub == nil and type(item.sub_item_table_func) == "function" then
        local ok, res = pcall(item.sub_item_table_func, TOUCHMENU_STUB)
        if ok then sub = res end
    end
    return type(sub) == "table" and sub or nil
end

-- 按标题在菜单项树中查找可执行项（补丁动作复用）
local function findMenuItem(items, title)
    if type(items) ~= "table" then return nil end
    for _i, item in ipairs(items) do
        if type(item) == "table" then
            if entry_text(item) == title and type(item.callback) == "function" then return item.callback end
            local sub = menuSubTable(item)
            if sub then
                local cb = findMenuItem(sub, title)
                if cb then return cb end
            end
        end
    end
    return nil
end

function PluginScan.scan()
    if PluginScan._scan_cache then return PluginScan._scan_cache end
    local ok, results = pcall(function()
        local out, seen = {}, {}
        local loader = plugin_loader()
        if loader and type(loader.loaded_plugins) == "table" then
            for key, mod in pairs(loader.loaded_plugins) do add_candidate(out, seen, key, mod) end
        end
        local names = enabled_plugin_names()
        if loader and type(loader.getPluginInstance) == "function" then
            for key in pairs(names) do
                local ok_plugin, plugin = pcall(loader.getPluginInstance, loader, key)
                if ok_plugin then add_candidate(out, seen, key, plugin) end
            end
        end
        for _i, ui in ipairs(live_uis()) do
            for key in pairs(names) do add_candidate(out, seen, key, ui[key]) end
        end
        -- 扫描补丁：直接遍历菜单项的 callback 项
        local function scanPatchItems(items, parent_title)
            if type(items) ~= "table" then return end
            for _i, item in ipairs(items) do
                if type(item) == "table" then
                    local text = entry_text(item)
                    local sub = menuSubTable(item)
                    if sub and #sub > 0 then
                        scanPatchItems(sub, text) -- 递归：传递当前 text 为父级
                    elseif text and type(item.callback) == "function" then
                        local display_title = parent_title and (parent_title .. " · " .. text) or text
                        local patch_key = "patch_" .. display_title
                        if not seen[patch_key] then
                            seen[patch_key] = true
                            out[#out + 1] = { key = patch_key, method = PluginScan.SENTINEL, title = text, display_title = display_title, is_patch = true }
                        end
                    end
                end
            end
        end
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        if fm and fm.menu and fm.menu.menu_items then scanPatchItems(fm.menu.menu_items) end
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        if reader and reader.menu and reader.menu.menu_items then scanPatchItems(reader.menu.menu_items) end
        table.sort(out, function(a, b) return a.title < b.title end)
        return out
    end)
    PluginScan._scan_cache = ok and results or {}
    return PluginScan._scan_cache
end

local function live_plugin(key)
    local loader = plugin_loader()
    local loaded = loader and loader.loaded_plugins
    if type(loaded) == "table" and type(loaded[key]) == "table" then return loaded[key] end
    if loader and type(loader.getPluginInstance) == "function" then
        local ok, plugin = pcall(loader.getPluginInstance, loader, key)
        if ok and type(plugin) == "table" then return plugin end
    end
    for _i, ui in ipairs(live_uis()) do
        if type(ui[key]) == "table" then return ui[key] end
    end
end

function PluginScan.resolve(key, method)
    -- 补丁动作：按标题查找菜单项回调
    if type(key) == "string" and string.sub(key, 1, 6) == "patch_" then
        local menu_title = string.sub(key, 7):gsub("^.* · ", "")
        local callback = nil
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        if fm and fm.menu and fm.menu.menu_items then callback = findMenuItem(fm.menu.menu_items, menu_title) end
        if not callback then
            local RUI = require("apps/reader/readerui")
            local reader = RUI and RUI.instance
            if reader and reader.menu and reader.menu.menu_items then callback = findMenuItem(reader.menu.menu_items, menu_title) end
        end
        if callback then
            return function() return callback(TOUCHMENU_STUB) end
        end
        return nil
    end
    if type(key) ~= "string" or type(method) ~= "string" then return nil end
    local mod = live_plugin(key)
    if type(mod) ~= "table" then return nil end
    if method == PluginScan.SENTINEL then
        local entry = probe_menu_entry(mod, key)
        local callback = entry and entry.callback
        if type(callback) ~= "function" then return nil end
        return function() return callback(TOUCHMENU_STUB) end
    end
    if method == PluginScan.SUBMENU then
        local entry = probe_menu_entry(mod, key)
        if not entry then return nil end
        local sub_items = menuSubTable(entry)
        if not sub_items then return nil end
        local title = type(entry.text) == "string" and entry.text or key
        return function()
            local ok_host, menu_host = pcall(require, "modules/menu/app_launcher/menu_host")
            if ok_host and menu_host and type(menu_host.show) == "function" then
                return menu_host.show{ title = title, item_table = sub_items }
            end
            local buttons = {}
            for _i, item in ipairs(sub_items) do
                local cb = item.callback
                local text = item.text
                if type(item.text_func) == "function" then text = item.text_func() end
                if type(text) == "string" then
                    buttons[#buttons + 1] = {{
                        text = text,
                        callback = function() if cb then cb() end end,
                    }}
                end
            end
            UIManager:show(ButtonDialog:new{
                title = title,
                title_align = "center",
                buttons = buttons,
                width = math.floor(Screen:getWidth() * 0.7),
            })
        end
    end
    if not is_callable(mod[method]) then return nil end
    return function() return mod[method](mod) end
end


-- ---- 导出 ----
return {
    TOUCHMENU_STUB = TOUCHMENU_STUB,
    PluginScan = PluginScan,
    live_plugin = live_plugin,
    findMenuItem = findMenuItem,
    probe_menu_entry = probe_menu_entry,
    menuSubTable = menuSubTable,
    entry_text = entry_text,
}
