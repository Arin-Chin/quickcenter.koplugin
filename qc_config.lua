-- qc_config.lua — QuickCenter 配置模块（由 main.lua 拆分而来，逻辑未改动）
-- 职责：默认配置、serialize/原子保存/加载（损坏自动备份）、设置读写与便捷访问器。
-- 只依赖 KOReader 核心 + 标准库，是其余模块共用的“叶子”模块，便于独立单测。
local logger = require("logger")

-- 配置状态（原 main.lua 顶层局部）
local CONFIG_PATH = nil
local CONFIG_DATA = nil
local DEFAULT_CONFIG = nil
local MAX_SLOTS = 66


-- ============================================================
-- 默认配置
-- ============================================================
DEFAULT_CONFIG = {
    qa_tab_icon = "star.empty",
    qa_enabled = true,
    qa_statusbar_enabled = true,
    qa_statusbar_items = { time = true, battery = true },
    qa_statusbar_formats = {},
    qa_slots = { "wifi", "night", "rotate", "screenshot", "continue", "fontlist", "restart", "search", "qa_settings", "qa_add_button", "qa_new" },
    qa_frontlight = true,
    qa_warmth = true,
    qa_shape = "round",
    qa_bg = "flat",
    qa_labels = false,
    qa_label_scale_pct = 90,
    qa_settings_on_hold = true,
    qa_button_size_pct = 100,
    custom_list = {},
    custom = {},
    builtin_overrides = {},
    qa_context_filter = true,
    qa_auto_add_to_panel = true,
    qa_button_hold_edit = true,
    qa_slider_show_value = false,
    qa_slider_style = "line",
    qa_filter_initialized = false,
    qa_icon_overrides = {},
    ui_font_overrides = {},
    qa_shortcuts = {},
    qa_layout_enabled = false,
    qa_layout_rows = 2,
    qa_layout_cols = 4,
    saved_configs = {},
    version = 1,
}

-- ============================================================
-- 配置读写
-- ============================================================
local function getConfigPath()
    if CONFIG_PATH then return CONFIG_PATH end
    local ok, DataStorage = pcall(require, "datastorage")
    CONFIG_PATH = ok and DataStorage and DataStorage:getSettingsDir() .. "/quickcenter.lua" or "quickcenter.lua"
    return CONFIG_PATH
end

-- 序列化为 Lua 表字面量（转义反斜杠/引号/换行，避免写出非法配置）
local function serializeTable(t, indent)
    indent = indent or ""
    local lines, keys = { "{\n" }, {}
    for k in pairs(t) do keys[#keys + 1] = k end
    -- 显式比较器：数字键在前（数组），避免混合键在 Lua 5.3+ 下 table.sort 抛错；
    -- 与 LuaJIT(5.1) 的默认排序语义一致，输出确定性更好。
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    for i, k in ipairs(keys) do
        local v = t[k]
        local ks = type(k) == "string" and string.format('["%s"]', k) or string.format("[%s]", tostring(k))
        local vv
        if type(v) == "table" then
            vv = serializeTable(v, indent .. "  ")
        elseif type(v) == "string" then
            vv = '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
        elseif type(v) == "number" or type(v) == "boolean" then
            vv = tostring(v)
        else
            vv = nil -- 跳过无法序列化的值
        end
        if vv then lines[#lines + 1] = string.format("%s  %s = %s,", indent, ks, vv) end
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines, "\n")
end

-- 原子写入：先写临时文件再改名，避免写入中断导致配置损坏
local function saveConfig()
    if not CONFIG_DATA then return end
    local tmp = CONFIG_PATH .. ".tmp"
    local f = io.open(tmp, "w")
    if f then
        f:write("return " .. serializeTable(CONFIG_DATA))
        f:close()
        os.rename(tmp, CONFIG_PATH)
    end
end

local function loadConfig()
    if CONFIG_DATA then return CONFIG_DATA end
    local path = getConfigPath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            content = content:gsub("^\239\187\191", "") -- 去 BOM
            local chunk, err = load(content)
            if chunk then
                local ok, data = pcall(chunk)
                if ok and type(data) == "table" then
                    CONFIG_DATA = data
                    return CONFIG_DATA
                else
                    logger.warn("[QuickActions] pcall 失败:", err)
                end
            else
                logger.warn("[QuickActions] load 失败:", err)
            end
        end
        -- 配置损坏：备份后使用默认
        logger.warn("[QuickActions] 配置文件损坏，备份原文件后使用默认配置")
        pcall(function() os.rename(path, path .. ".bak") end)
        CONFIG_DATA = DEFAULT_CONFIG
        saveConfig()
        return CONFIG_DATA
    end
    logger.info("[QuickActions] 配置文件不存在，创建默认配置")
    CONFIG_DATA = DEFAULT_CONFIG
    saveConfig()
    return CONFIG_DATA
end

-- ============================================================
-- 配置访问
-- ============================================================
local function getSetting(key)
    local cfg = loadConfig()
    local val = cfg[key]
    if val ~= nil then return val end
    return DEFAULT_CONFIG[key]
end

local function setSetting(key, value)
    loadConfig()[key] = value
    saveConfig()
end

local function getBool(key)
    local val = getSetting(key)
    if type(val) == "boolean" then return val end
    return DEFAULT_CONFIG[key] == true
end
local function setBool(key, value) setSetting(key, value == true) end

local function getString(key)
    local val = getSetting(key)
    if type(val) == "string" then return val end
    return DEFAULT_CONFIG[key] or ""
end
local function setString(key, value) setSetting(key, value) end

local function getNumber(key)
    local val = getSetting(key)
    if type(val) == "number" then return val end
    return DEFAULT_CONFIG[key] or 0
end
local function setNumber(key, value) setSetting(key, value) end

local function getTable(key)
    local val = loadConfig()[key]
    if type(val) == "table" then return val end
    return DEFAULT_CONFIG[key] or {}
end

-- 深拷贝后落盘，避免外部修改直接污染配置
local function setTable(key, value)
    local json = require("json")
    loadConfig()[key] = json.decode(json.encode(value))
    saveConfig()
end

-- ============================================================
-- 便捷配置访问
-- ============================================================
local function isQAEnabled() return getBool("qa_enabled") end
local function getQASlots()
    local slots = getSetting("qa_slots")
    return type(slots) == "table" and slots or DEFAULT_CONFIG.qa_slots
end
local function saveQASlots(slots) setSetting("qa_slots", slots) end
local function showFrontlight() return getBool("qa_frontlight") end
local function showWarmth() return getBool("qa_warmth") end
local function showSliderValue() return getBool("qa_slider_show_value") end
local function getSliderStyle() return getString("qa_slider_style") end
local function getShape() return getString("qa_shape") end
local function getBg() return getString("qa_bg") end
local function showLabels() return getBool("qa_labels") end
local function getLabelScalePct()
    return math.max(50, math.min(200, math.floor(getNumber("qa_label_scale_pct"))))
end
local function getLabelScale() return getLabelScalePct() / 100 end
local function buttonHoldEdit() return getBool("qa_button_hold_edit") end
local function settingsOnHold() return getBool("qa_settings_on_hold") end
local function getButtonSizePct()
    return math.max(60, math.min(150, math.floor(getNumber("qa_button_size_pct"))))
end


-- ---- 导出 ----
return {
    CONFIG_PATH = CONFIG_PATH,
    CONFIG_DATA = CONFIG_DATA,
    DEFAULT_CONFIG = DEFAULT_CONFIG,
    MAX_SLOTS = MAX_SLOTS,
    getConfigPath = getConfigPath,
    saveConfig = saveConfig,
    loadConfig = loadConfig,
    -- 强制重新从磁盘加载（丢弃内存缓存）
    reloadConfig = function()
        CONFIG_DATA = nil
        return loadConfig()
    end,
    -- 以给定表整体替换当前配置并落盘（用于“重设配置”）
    replaceConfig = function(new_table)
        CONFIG_DATA = new_table
        saveConfig()
        return CONFIG_DATA
    end,
    getSetting = getSetting, setSetting = setSetting,
    getBool = getBool, setBool = setBool,
    getString = getString, setString = setString,
    getNumber = getNumber, setNumber = setNumber,
    getTable = getTable, setTable = setTable,
    serializeTable = serializeTable,
    isQAEnabled = isQAEnabled, getQASlots = getQASlots, saveQASlots = saveQASlots,
    showFrontlight = showFrontlight, showWarmth = showWarmth, showSliderValue = showSliderValue,
    getSliderStyle = getSliderStyle, getShape = getShape, getBg = getBg,
    showLabels = showLabels, getLabelScalePct = getLabelScalePct, getLabelScale = getLabelScale,
    buttonHoldEdit = buttonHoldEdit, settingsOnHold = settingsOnHold,
    getButtonSizePct = getButtonSizePct,
}



