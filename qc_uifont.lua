-- qc_uifont.lua — QuickCenter UI 字体切换模块（由 main.lua 拆分；含一次性守卫修复）
-- 职责：常规/粗体/等宽三种字体族整体替换、字体选择对话框、重启确认。
-- applyUIFontChanges() 在本模块被 require 时执行一次（等价原补丁启动时调用）。
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Notification = require("ui/widget/notification")
local util = require("util")
local FontList = require("fontlist")

local qc_config = require("qc_config")
local getTable, setTable = qc_config.getTable, qc_config.setTable

-- ============================================================
-- UI 字体切换（三种字体类型，自动替换所有对应 key）
-- ============================================================
local _font_picker_dialog = nil
local _font_main_dialog = nil

local function getAvailableFonts()
    local result = {}
    for idx, path in ipairs(FontList:getFontList()) do
        local fname, name = util.splitFilePathName(path)
        if name and (name:match("%.ttf$") or name:match("%.otf$")) then
            result[#result + 1] = {
                name = name,
                display = name:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " "),
            }
        end
    end
    table.sort(result, function(a, b) return a.display:lower() < b.display:lower() end)
    return result
end

local UI_FONT_ITEMS = {
    { key = "regular", label = _("常规字体"), default = "NotoSans-Regular.ttf" },
    { key = "bold", label = _("粗体字体"), default = "NotoSans-Bold.ttf" },
    { key = "mono", label = _("等宽字体"), default = "DroidSansMono.ttf" },
}
local FONT_TYPE_MAP = {
    regular = { "cfont", "ffont", "smallffont", "largeffont", "rifont", "pgfont", "hfont", "infofont", "smallinfofont", "x_smallinfofont", "xx_smallinfofont" },
    bold = { "tfont", "smalltfont", "x_smalltfont", "smallinfofontbold" },
    mono = { "scfont", "hpkfont", "infont", "smallinfont" },
}

local function applyUIFontChanges()
    local overrides = getTable("ui_font_overrides") or {}
    local font_exists = {}
    for idx, path in ipairs(FontList:getFontList()) do
        local fname, name = util.splitFilePathName(path)
        if name then font_exists[name] = true end
    end
    local defaults = { regular = "NotoSans-Regular.ttf", bold = "NotoSans-Bold.ttf", mono = "DroidSansMono.ttf" }
    for kind, keys in pairs(FONT_TYPE_MAP) do
        local font_name = overrides[kind] or defaults[kind]
        if font_exists[font_name] then
            for _i, k in ipairs(keys) do Font.fontmap[k] = font_name end
        end
    end
    Font.faces = {}
    -- 统一覆盖各组件默认字体（face/fface 字段）
    local function overrideFace(modname, field, font_key, default_size)
        local ok, mod = pcall(require, modname)
        if ok and mod and mod[field] then
            mod[field] = Font:getFace(font_key, mod[field].orig_size or default_size)
        end
    end
    overrideFace("ui/widget/touchmenu", "fface", "cfont", 24)
    overrideFace("ui/widget/confirmbox", "face", "cfont", 22)
    overrideFace("ui/widget/infomessage", "face", "infofont", 22)
    overrideFace("ui/widget/notification", "face", "x_smallinfofont", 18)
    overrideFace("ui/widget/buttondialog", "title_face", "tfont", 20)
    overrideFace("ui/widget/buttondialog", "info_face", "infofont", 22)
    overrideFace("ui/widget/inputdialog", "input_face", "infont", 16)
    overrideFace("ui/widget/multiinputdialog", "title_face", "tfont", 20)
    overrideFace("ui/widget/multiinputdialog", "info_face", "infofont", 22)
    Button.text_font_face = overrides.regular or defaults.regular
    -- 菜单/触摸菜单项字体补丁（两处逻辑相同，合并）
    -- ponytail/fix: 修复 #1 —— 原实现每次 applyUIFontChanges()（含每次改字体）都会
    -- 对同一模块的 updateItems 再包一层，包装链无限增长，且捕获的是“当时”的字体
    -- 覆盖（陈旧捕获）。现在改为：每个模块只包装一次（_qa_font_patch_done 守卫），
    -- 包装体在每次执行时读取最新覆盖，新旧实例都拿到当前字体，无需重复包装。
    local function patchMenuUpdateItems(modname)
        local ok_mod, mod = pcall(require, modname)
        if not (ok_mod and mod and mod.updateItems) then return end
        if mod._qa_font_patch_done then return end
        mod._qa_font_patch_done = true
        local orig_update = mod.updateItems
        mod.updateItems = function(self, ...)
            if not self._font_patched then
                local live_overrides = getTable("ui_font_overrides") or {}
                local regular = live_overrides.regular or "NotoSans-Regular.ttf"
                for i = 1, #self.item_group do
                    local widget = self.item_group[i]
                    if widget and widget.face then
                        local cls = getmetatable(widget)
                        if cls then cls.font = regular; cls.infont = regular end
                    end
                end
                self._font_patched = true
            end
            return orig_update(self, ...)
        end
    end
    patchMenuUpdateItems("ui/widget/menu")
    patchMenuUpdateItems("ui/widget/touchmenu")
end

local function setUIFontOverride(key, font_name)
    local overrides = getTable("ui_font_overrides") or {}
    if font_name then overrides[key] = font_name else overrides[key] = nil end
    setTable("ui_font_overrides", overrides)
    applyUIFontChanges()
    UIManager:setDirty("all", "full")
end

local function resetAllUIFonts()
    setTable("ui_font_overrides", {})
    UIManager:show(Notification:new{ text = _("已重置所有UI字体，重启后生效"), timeout = 2 })
    UIManager:show(ConfirmBox:new{
        text = _("重启后生效。立即重启？"),
        ok_text = _("重启"),
        cancel_text = _("稍后"),
        ok_callback = function() UIManager:restartKOReader() end,
    })
end

-- 重启确认框（多处共用）
local function askRestart(text)
    UIManager:show(ConfirmBox:new{
        text = text or _("重启后生效。立即重启？"),
        ok_text = _("重启"),
        cancel_text = _("稍后"),
        ok_callback = function() UIManager:restartKOReader() end,
    })
end

local function showFontPickerForUIKey(ui_key, ui_label, on_select, on_cancel)
    if _font_picker_dialog then UIManager:close(_font_picker_dialog); _font_picker_dialog = nil end
    local all_fonts = getAvailableFonts()
    local current = getTable("ui_font_overrides")[ui_key] or ""
    local buttons = {}
    local function closePicker()
        if _font_picker_dialog then UIManager:close(_font_picker_dialog); _font_picker_dialog = nil end
    end
    buttons[#buttons + 1] = {{ text = _("应用默认"), callback = function() closePicker(); if on_select then on_select(nil) end end }}
    buttons[#buttons + 1] = {{ text = _("返回"), callback = function() closePicker(); if on_cancel then on_cancel() end end }}
    buttons[#buttons + 1] = {}
    if #all_fonts == 0 then
        buttons[#buttons + 1] = {{ text = _("没有可用的字体文件"), enabled = false }}
    else
        for i, font in ipairs(all_fonts) do
            local is_current = (font.name == current)
            buttons[#buttons + 1] = {{
                text = (is_current and "✓ " or "  ") .. font.display,
                callback = function()
                    closePicker()
                    if on_select then on_select(font.name) end
                end,
            }}
        end
    end
    _font_picker_dialog = ButtonDialog:new{
        title = string.format(_("选择 %s 字体"), ui_label),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(_font_picker_dialog)
end

local function showUIFontSwitcher()
    if _font_main_dialog then UIManager:close(_font_main_dialog); _font_main_dialog = nil end
    if _font_picker_dialog then UIManager:close(_font_picker_dialog); _font_picker_dialog = nil end
    local overrides = getTable("ui_font_overrides") or {}
    local replaced_count = 0
    for i, item in ipairs(UI_FONT_ITEMS) do
        if overrides[item.key] then replaced_count = replaced_count + 1 end
    end
    local buttons = {}
    local function closeMain()
        if _font_main_dialog then UIManager:close(_font_main_dialog); _font_main_dialog = nil end
    end
    buttons[#buttons + 1] = {{
        text = string.format(_("重置全部 (%d/%d)"), replaced_count, #UI_FONT_ITEMS),
        callback = function() closeMain(); resetAllUIFonts() end,
    }}
    buttons[#buttons + 1] = {}
    for i, item in ipairs(UI_FONT_ITEMS) do
        local override = overrides[item.key]
        local display = (override or item.default):gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
        local text = item.label .. ": " .. display
        if override then
            local default_display = item.default:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
            text = item.label .. ": " .. default_display .. " → " .. display
        end
        buttons[#buttons + 1] = {{
            text = text,
            callback = function()
                closeMain()
                showFontPickerForUIKey(
                    item.key,
                    item.label,
                    function(new_font)
                        if new_font then
                            setUIFontOverride(item.key, new_font)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s 已设置为 %s"), item.label, new_font),
                                timeout = 2,
                            })
                        else
                            setUIFontOverride(item.key, nil)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s 已重置为默认"), item.label),
                                timeout = 2,
                            })
                        end
                        showUIFontSwitcher()
                    end,
                    function() showUIFontSwitcher() end
                )
            end,
        }}
    end
    _font_main_dialog = ButtonDialog:new{
        title = _("UI字体切换"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(_font_main_dialog)
end

applyUIFontChanges()


-- ---- 导出 ----
return {
    getAvailableFonts = getAvailableFonts,
    applyUIFontChanges = applyUIFontChanges,
    setUIFontOverride = setUIFontOverride,
    resetAllUIFonts = resetAllUIFonts,
    askRestart = askRestart,
    showFontPickerForUIKey = showFontPickerForUIKey,
    showUIFontSwitcher = showUIFontSwitcher,
}
