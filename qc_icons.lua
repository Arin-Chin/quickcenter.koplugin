-- qc_icons.lua — QuickCenter 图标模块（由 main.lua 拆分，逻辑未改动）
-- 职责：Nerd Font 码位解析/字形扫描（单遍+缓存）、图标文件定位缓存、系统图标
-- 覆盖数据、文件/系统图标浏览与选择（IconBrowser / _InnerIconChooser）。
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = Device.screen
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local BD = require("ui/bidi")
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local Menu = require("ui/widget/menu")
local PathChooser = require("ui/widget/pathchooser")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Notification = require("ui/widget/notification")
local util = require("util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local IconWidget = require("ui/widget/iconwidget")

local qc_config = require("qc_config")
local getTable, setTable = qc_config.getTable, qc_config.setTable
local askRestart = require("qc_uifont").askRestart

-- ============================================================
-- Nerd Font 支持（模块内函数 QC.nerdIconChar：图标码位 ↔ UTF-8 字符）
-- ============================================================
local function nerdIconChar(icon_value)
    if type(icon_value) ~= "string" then return nil end
    local hex = icon_value:match("^nerd:([0-9A-Fa-f]+)$")
    if not hex then return nil end
    local cp = tonumber(hex, 16)
    if not cp or cp < 0 or cp > 0x10FFFF then return nil end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor((cp % 0x40000) / 0x1000),
        0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
end

local function isNerdIcon(icon_value) return nerdIconChar(icon_value) ~= nil end

-- ============================================================
-- Nerd Font 图标列表（从 symbols 字体读取字形，码位区间单遍扫描）
-- ============================================================
local ffi = require("ffi")
ffi.cdef[[
    FT_Error FT_Get_Glyph_Name(FT_Face face, FT_UInt glyph_index, FT_String *buffer, FT_UInt buffer_max);
]]
local ft2 = ffi.loadlib("freetype", "6")

local NERD_RANGES = {
    {0x23FB, 0x23FE}, {0xE700, 0xE7FF}, {0xF000, 0xF3FF}, {0xF500, 0xF8FF},
    {0xE800, 0xE8FF}, {0xE000, 0xE09F}, {0xE100, 0xE2FF}, {0xE400, 0xE6FF},
    {0xF400, 0xF4FF}, {0xE300, 0xE3FF}, {0xE0A0, 0xE0FF},
}

local function getNerdGlyphName(cp, face)
    if not cp or type(cp) ~= "number" then return nil end
    face = face or Font:getFace("symbols", 12)
    local ft_face = face and face.ftsize and face.ftsize.face
    if not ft_face then return nil end
    local glyph_index = ft2.FT_Get_Char_Index(ft_face, cp)
    if glyph_index == 0 then return nil end
    local buffer = ffi.new("FT_String[128]")
    if ft2.FT_Get_Glyph_Name(ft_face, glyph_index, buffer, 128) ~= 0 then return nil end
    return ffi.string(buffer)
end

-- face 只取一次（原来每码点都 Font:getFace，约 900 次查找 → 1 次）
local function getNerdIcons()
    local icons = {}
    local face = Font:getFace("symbols", 12)
    if not (face and face.ftsize) then return icons end
    for _i, range in ipairs(NERD_RANGES) do
        for cp = range[1], range[2] do
            if face.ftsize:hasGlyph(cp) then
                local hex = string.format("%04X", cp)
                icons[#icons + 1] = { type = "nerd", hex = hex, value = "nerd:" .. hex, name = getNerdGlyphName(cp, face) }
            end
        end
    end
    return icons
end

-- ============================================================
-- 图标解析（带缓存：图标文件运行期不变；miss 用哨兵缓存防反复探测）
-- ============================================================
local _icons_dir = nil
local function getIconsDir()
    if _icons_dir then return _icons_dir end
    local ok, DataStorage = pcall(require, "datastorage")
    _icons_dir = ok and DataStorage and DataStorage:getDataDir() .. "/icons" or "./icons"
    return _icons_dir
end

local _icon_cache = { map = {}, miss = {} }

local function getIconFile(icon_name)
    if not icon_name then return nil end
    if isNerdIcon(icon_name) then return icon_name end
    local cached = _icon_cache.map[icon_name]
    if cached ~= nil then return cached == _icon_cache.miss and nil or cached end
    local result
    if icon_name:sub(1, 1) == "/" and lfs.attributes(icon_name, "mode") == "file" then
        result = icon_name
    end
    if not result then
        local ok, DataStorage = pcall(require, "datastorage")
        if ok and DataStorage then
            local full_path = (DataStorage:getDataDir() .. "/" .. icon_name):gsub("/%.", ""):gsub("/+", "/")
            if lfs.attributes(full_path, "mode") == "file" then result = full_path end
        end
    end
    if not result then
        local filename = icon_name:match("([^/]+)$") or icon_name
        local dirs_to_check = { getIconsDir(), "resources/icons/mdlight", "resources/icons", "resources" }
        for _i, dir in ipairs(dirs_to_check) do
            local path = dir .. "/" .. filename
            if lfs.attributes(path, "mode") == "file" then result = path; break end
        end
    end
    _icon_cache.map[icon_name] = result or _icon_cache.miss
    return result
end

local function getIconWidget(icon_path, size)
    size = size or Screen:scaleBySize(24)
    if isNerdIcon(icon_path) then
        local nerd_char = nerdIconChar(icon_path)
        if nerd_char then
            return TextWidget:new{
                text = nerd_char,
                face = Font:getFace("symbols", math.floor(size * 0.6)),
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            }
        end
    end
    local file_path = getIconFile(icon_path)
    if file_path and lfs.attributes(file_path, "mode") == "file" then
        local iw = ImageWidget:new{ file = file_path, width = size, height = size, alpha = true, is_icon = true }
        local ok_render = pcall(function() iw:_render() end)
        if ok_render then return iw end
        iw:free()
    end
    return nil
end

-- ============================================================
-- 图标文件浏览器
-- ============================================================
local THUMB_SIZE = Screen:scaleBySize(32)
local THUMB_GAP = Screen:scaleBySize(6)

local _InnerIconChooser = PathChooser:extend{
    select_directory = false,
    select_file = true,
    state_w = THUMB_SIZE + THUMB_GAP,
    path = getIconsDir(),
    onConfirm = nil,
    _filter_text = "",
    _all_items = nil,
    stop_events_propagation = true,
}

function _InnerIconChooser:init()
    self.title = _('选择图标')
    self.file_filter = function(filename)
        local ext = filename:lower()
        return ext:match('%.svg$') ~= nil or ext:match('%.png$') ~= nil
    end
    self.state_w = THUMB_SIZE + THUMB_GAP
    PathChooser.init(self)
    if not self._all_items then self:refreshPath() end
end

function _InnerIconChooser:getCollate()
    return self.collates.strcoll, "strcoll"
end

function _InnerIconChooser:refreshPath()
    local _, folder_name = util.splitFilePathName(self.path)
    Screen:setWindowTitle(folder_name)
    self._all_items = self:genItemTableFromPath(self.path)
    self:_applyCurrentFilter()
end

function _InnerIconChooser:_applyCurrentFilter()
    local filter_text = self._filter_text or ""
    local items
    if filter_text == "" then
        items = self._all_items
    else
        items = {}
        local pattern = filter_text:lower()
        for _i, item in ipairs(self._all_items) do
            if item.is_go_up or (item.text and item.text:lower():find(pattern, 1, true)) then
                items[#items + 1] = item
            end
        end
    end
    local itemmatch
    if self.focused_path then itemmatch = { path = self.focused_path }; self.focused_path = nil end
    local subtitle = BD.directory(filemanagerutil.abbreviate(self.path))
    self:switchItemTable(nil, items, filter_text == "" and self.path_items[self.path] or 1, itemmatch, subtitle)
end

function _InnerIconChooser:applyFilter(text)
    self._filter_text = text or ""
    if self._all_items then self:_applyCurrentFilter() end
end

function _InnerIconChooser:_recalculateDimen(no_recalculate_dimen)
    Menu._recalculateDimen(self, no_recalculate_dimen)
    if not self.item_dimen then return end
    if self._filter_bar_height and self._filter_bar_height > 0 and not no_recalculate_dimen then
        self.available_height = self.available_height - self._filter_bar_height
        self.item_dimen.h = math.floor(self.available_height / self.perpage)
    end
    local content_w = math.max(0, self.item_dimen.w - 2 * Size.padding.fullscreen)
    local max_state_w = math.max(1, math.floor(content_w / 4))
    local ts, tg = THUMB_SIZE, THUMB_GAP
    self.state_w = math.min(ts + tg, max_state_w)
    self._thumb_size = math.max(0, math.min(ts, self.state_w - tg))
end

function _InnerIconChooser:updateItems(select_number, no_recalculate_dimen)
    Menu.updateItems(self, select_number, no_recalculate_dimen)
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
    local eff_thumb = self._thumb_size or 0
    if eff_thumb <= 0 then return end
    local item_h = self.item_dimen and self.item_dimen.h or eff_thumb
    local center_y = math.max(0, math.floor((item_h - eff_thumb) / 2))
    for _i, item_widget in ipairs(self.item_group) do
        local entry = item_widget.entry
        if not entry then goto continue end
        local filepath = entry.path or ""
        if not filepath:lower():match("%.svg$") and not filepath:lower():match("%.png$") then goto continue end
        local uc = item_widget._underline_container
        local hg = uc and uc[1]
        local og = hg and hg[1]
        if og then
            -- 缩略图插到行首（与 PathChooser 原布局一致）
            table.insert(og, 1, ImageWidget:new{
                file = filepath,
                width = eff_thumb,
                height = eff_thumb,
                alpha = true,
                overlap_offset = { 0, center_y },
            })
            og._size = nil
        end
        ::continue::
    end
end

function _InnerIconChooser:onMenuSelect(item)
    local path = item.path or ""
    if path:lower():match("%.svg$") or path:lower():match("%.png$") then
        if self.show_parent then self.show_parent:onClose() end
        if self.onConfirm then self.onConfirm(path) end
        return true
    end
    return PathChooser.onMenuSelect(self, item)
end

function _InnerIconChooser:onMenuHold(item)
    local path = item.path or ""
    if path:lower():match("%.svg$") or path:lower():match("%.png$") then return true end
    return PathChooser.onMenuHold(self, item)
end

local IconBrowser = WidgetContainer:extend{
    path = getIconsDir(),
    onConfirm = nil,
    is_always_active = true,
}

function IconBrowser:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local final_path = nil
    for _i, path in ipairs({ self.path, "./resources/icons/mdlight", "./" }) do
        if lfs.attributes(path, "mode") == "directory" then
            final_path = path
            break
        end
    end
    if not final_path then
        UIManager:show(InfoMessage:new{ text = _("找不到图标目录，无法打开图标浏览器"), timeout = 3 })
        return
    end
    self.path = final_path
    self._filter_input = InputText:new{
        text = "",
        hint = _("按名称筛选…"),
        width = self.dimen.w - 4 * Size.padding.default,
        height = nil,
        face = Font:getFace("smallinfofont"),
        padding = Size.padding.small,
        margin = 0,
        bordersize = Size.border.inputtext,
        parent = self,
        scroll = false,
        focused = false,
        edit_callback = function() self:_applyFilter() end,
    }
    self._filter_input.addChars = function(inp, chars)
        if chars == "\n" then
            inp:onCloseKeyboard()
            return
        end
        InputText.addChars(inp, chars)
    end
    self._filter_bar = FrameContainer:new{
        padding = Size.padding.default,
        padding_top = Size.padding.small,
        padding_bottom = Size.padding.small,
        bordersize = 0,
        self._filter_input,
    }
    local filter_h = self._filter_bar:getSize().h
    self._chooser = _InnerIconChooser:new{
        show_parent = self,
        path = self.path,
        onConfirm = self.onConfirm,
        height = self.dimen.h,
        close_callback = function() self:onClose() end,
    }
    table.insert(self._chooser.content_group, 2, self._filter_bar)
    self._chooser._filter_bar_height = filter_h
    self._chooser:refreshPath()
    self[1] = self._chooser
end

function IconBrowser:_applyFilter()
    if not self._chooser then return end
    local text = self._filter_input and self._filter_input:getText() or ""
    self._chooser:applyFilter(text)
end

-- 保持不可聚焦（防止实体按键焦点跳到浏览器内部）
function IconBrowser:getFocusableWidgetXY() return nil, nil end

function IconBrowser:onClose()
    if self._filter_input then self._filter_input:onCloseKeyboard() end
    UIManager:close(self)
end

-- ============================================================
-- 扫描图标目录中的 SVG/PNG 文件
-- ============================================================
local function scanAllIconDirs(mode)
    local all_files, seen = {}, {}
    local dirs_to_scan
    if mode == "system" then
        dirs_to_scan = { "resources/icons/mdlight" }
    elseif mode == "replacement" then
        -- 替换系统图标时的候选库：快捷中心图标库（用户图标 + 通用内置图标），
        -- 排除系统图标目录 mdlight，避免与待替换项重名混淆
        dirs_to_scan = { getIconsDir(), "resources/icons", "resources" }
    else
        dirs_to_scan = { getIconsDir(), "resources/icons/mdlight", "resources/icons", "resources" }
    end
    for _i, dir in ipairs(dirs_to_scan) do
        if lfs.attributes(dir, "mode") == "directory" then
            for file in lfs.dir(dir) do
                if file ~= "." and file ~= ".." then
                    local ext = file:lower()
                    if ext:match("%.svg$") or ext:match("%.png$") then
                        local name = file:gsub("%.[^%.]+$", "")
                        if not seen[name] then
                            seen[name] = true
                            all_files[#all_files + 1] = {
                                path = dir .. "/" .. file,
                                name = name,
                                display_name = name:gsub("_", " "),
                                ext = ext,
                                type = "file",
                            }
                        end
                    end
                end
            end
        end
    end
    if mode == "replacement" and #all_files == 0 then
        return scanAllIconDirs("system") -- 兜底：库为空时仍可浏览系统图标
    end
    return all_files
end

local cached_file_icons = nil
local function getFileIcons()
    if cached_file_icons == nil then cached_file_icons = scanAllIconDirs() end
    return cached_file_icons
end

local picker_cache = {}
local function clearFileIconsCache()
    picker_cache = {}
    cached_file_icons = nil
end

local system_temp_overrides = nil
local function getSystemTempOverrides()
    if system_temp_overrides == nil then
        system_temp_overrides = {}
        for k, v in pairs(getTable("qa_icon_overrides")) do system_temp_overrides[k] = v end
    end
    return system_temp_overrides
end
local function resetSystemTempOverrides() system_temp_overrides = nil end

-- ============================================================
-- 图标选择器（网格 + 筛选 + 分页；屏幕尺寸变化自动重算布局）
-- ============================================================
local function showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(24)
    local brd = Screen:scaleBySize(1)
    local cache_key = (filter or "all") .. "_" .. (mode or parent_mode or "normal")
    local use_cache = picker_cache[cache_key] ~= nil

    local icons_list, page_widgets, total_pages
    local frame_x, frame_y, frame_w, frame_h
    local content_w, title_bar_h, button_bar_h, footer_h
    local cols, rows, per_page, h_gap, v_gap
    local cell_w, cell_h, icon_sz, font_size, cell_pad, grid_w, grid_h
    local dialog = nil
    local cur_page = 1
    local filter_keyword = ""
    local filtered_icons_list = nil
    local search_dialog = nil

    local function getDisplayList()
        -- 防御：icons_list 意外为 nil 时返回空表，避免 #nil 崩溃（历史回归点）
        if filter_keyword == "" then return icons_list or {} end
        if filtered_icons_list == nil then
            filtered_icons_list = {}
            local pattern = filter_keyword:lower()
            for _i, icon in ipairs(icons_list or {}) do
                local hay = icon.type == "nerd" and icon.name or icon.display_name
                local match = false
                if icon.type == "nerd" then
                    if icon.hex:lower():find(pattern, 1, true) then match = true end
                end
                if not match and hay and hay:lower():find(pattern, 1, true) then match = true end
                if not match and icon.type ~= "nerd" and icon.name and icon.name:lower():find(pattern, 1, true) then match = true end
                if match then filtered_icons_list[#filtered_icons_list + 1] = icon end
            end
        end
        return filtered_icons_list
    end

    local function rebuildPicker()
        filtered_icons_list = nil
        local display_list = getDisplayList()
        local new_total_pages = math.max(1, math.ceil(#display_list / per_page))
        local new_page_widgets = {}
        for p = 1, new_total_pages do
            local page_vg = VerticalGroup:new{ align = "left" }
            local start_idx = (p - 1) * per_page + 1
            for row = 0, rows - 1 do
                local row_hg = HorizontalGroup:new{ align = "top" }
                for col = 0, cols - 1 do
                    local idx = start_idx + row * cols + col
                    if idx <= #display_list then
                        local icon = display_list[idx]
                        local icon_widget
                        if icon.type == "nerd" then
                            icon_widget = TextWidget:new{
                                text = nerdIconChar(icon.value) or "?",
                                face = Font:getFace("symbols", font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                        else
                            local icon_path = icon.path
                            if mode == "system" and icon.is_overridden and icon.override_path then icon_path = icon.override_path end
                            icon_widget = IconWidget:new{ file = icon_path, width = icon_sz, height = icon_sz, alpha = true }
                            pcall(function() icon_widget:_render() end)
                        end
                        local cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad * 2 - 2, h = cell_h - cell_pad * 2 - 2 },
                            icon_widget,
                        }
                        local border_color, border_size = Blitbuffer.COLOR_LIGHT_GRAY, 1
                        if mode == "system" and icon.is_overridden then border_color, border_size = Blitbuffer.COLOR_BLACK, 2 end
                        local cell = FrameContainer:new{
                            width = cell_w,
                            height = cell_h,
                            bordersize = border_size,
                            color = border_color,
                            background = Blitbuffer.COLOR_WHITE,
                            radius = Screen:scaleBySize(4),
                            padding = cell_pad,
                            cell_content,
                        }
                        row_hg[#row_hg + 1] = cell
                        if col < cols - 1 then row_hg[#row_hg + 1] = HorizontalSpan:new{ width = h_gap } end
                    end
                end
                page_vg[#page_vg + 1] = row_hg
                if row < rows - 1 then page_vg[#page_vg + 1] = VerticalSpan:new{ width = v_gap } end
            end
            new_page_widgets[p] = page_vg
        end
        page_widgets = new_page_widgets
        total_pages = new_total_pages
        if cur_page > total_pages then cur_page = 1 end
        if dialog then UIManager:setDirty(dialog, function() return "ui", dialog.dimen end) end
    end

    local function showSearchDialog()
        if search_dialog then UIManager:close(search_dialog); search_dialog = nil end
        local function onStrike()
            if search_dialog then
                filter_keyword = search_dialog:getInputText() or ""
                filtered_icons_list = nil
                rebuildPicker()
                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
            end
        end
        search_dialog = InputDialog:new{
            title = _("筛选图标"),
            input = filter_keyword,
            input_hint = _("输入名称或码位..."),
            strike_callback = onStrike,
            buttons = {
                {
                    {
                        text = _("清除"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                            filter_keyword = ""
                            filtered_icons_list = nil
                            rebuildPicker()
                            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                        end,
                    },
                    {
                        text = _("关闭"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                        end,
                    },
                }
            },
        }
        UIManager:show(search_dialog)
        pcall(function() search_dialog:onShowKeyboard() end)
    end

    local temp_overrides = {}
    if mode == "system" then temp_overrides = getSystemTempOverrides() end

    local cache_valid = false
    if use_cache and mode ~= "system" and parent_mode ~= "system" then
        local cached = picker_cache[cache_key]
        -- 校验缓存完整性：尺寸一致且 icons_list 存在（防缓存结构变化导致 nil）
        if cached.sw == sw and cached.sh == sh and cached.icons_list then
            cache_valid = true
            icons_list, page_widgets, total_pages = cached.icons_list, cached.page_widgets, cached.total_pages
            frame_x, frame_y, frame_w, frame_h = cached.frame_x, cached.frame_y, cached.frame_w, cached.frame_h
            content_w, title_bar_h, button_bar_h, footer_h = cached.content_w, cached.title_bar_h, cached.button_bar_h, cached.footer_h
            cols, rows, per_page, h_gap, v_gap = cached.cols, cached.rows, cached.per_page, cached.h_gap, cached.v_gap
            cell_w, cell_h, icon_sz, font_size, cell_pad, grid_w, grid_h = cached.cell_w, cached.cell_h, cached.icon_sz, cached.font_size, cached.cell_pad, cached.grid_w, cached.grid_h
        end
    end

    if not cache_valid then
        if use_cache and mode ~= "system" and parent_mode ~= "system" and picker_cache[cache_key].icons_list then
            icons_list = picker_cache[cache_key].icons_list
        else
            icons_list = {}
            if (not filter or filter == "nerd") and mode ~= "system" then
                for _i, icon in ipairs(getNerdIcons()) do
                    icons_list[#icons_list + 1] = { type = "nerd", hex = icon.hex, value = "nerd:" .. icon.hex, name = icon.name }
                end
            end
            if not filter or filter == "file" then
                local file_icons
                if mode == "system" then
                    file_icons = scanAllIconDirs("system")
                elseif parent_mode == "system" then
                    file_icons = scanAllIconDirs("replacement")
                else
                    file_icons = getFileIcons()
                end
                for _i, file in ipairs(file_icons) do
                    local item = { type = "file", path = file.path, name = file.name, display_name = file.display_name, value = file.path }
                    if mode == "system" then
                        local override_icon = temp_overrides[file.name]
                        item.is_overridden = override_icon ~= nil
                        if override_icon then
                            local override_path = getIconsDir() .. "/" .. override_icon
                            if lfs.attributes(override_path, "mode") == "file" then item.override_path = override_path end
                        end
                    end
                    icons_list[#icons_list + 1] = item
                end
            end
        end
        if sw > sh then cols, rows, frame_h = 9, 4, math.floor(sh * 0.85)
        else cols, rows, frame_h = 7, 5, math.floor(sh * 0.70) end
        per_page = cols * rows
        h_gap, v_gap = Screen:scaleBySize(15), Screen:scaleBySize(15)
        frame_w = math.floor(sw * 0.90)
        content_w = frame_w - 2 * pad - 2 * brd
        title_bar_h = Screen:scaleBySize(50)
        button_bar_h = Screen:scaleBySize(50)
        footer_h = Screen:scaleBySize(40)
        cell_w = math.floor((content_w - (cols - 1) * h_gap) / cols)
        local available_h = frame_h - pad - title_bar_h - button_bar_h - footer_h - pad
        cell_h = math.max(44, math.floor((available_h - (rows - 1) * v_gap) / rows))
        icon_sz = math.floor(cell_h * 0.55)
        font_size = math.floor(icon_sz * 0.85)
        cell_pad = math.max(4, math.floor(cell_h * 0.2))
        grid_w = cols * cell_w + (cols - 1) * h_gap
        grid_h = cell_h * rows + (rows - 1) * v_gap
        frame_x = math.floor((sw - frame_w) / 2)
        frame_y = math.max(0, math.floor((sh - frame_h) / 2))
        rebuildPicker()
        if mode ~= "system" and parent_mode ~= "system" then
            picker_cache[cache_key] = {
                icons_list = icons_list,
                page_widgets = page_widgets,
                total_pages = total_pages,
                sw = sw,
                sh = sh,
                frame_x = frame_x,
                frame_y = frame_y,
                frame_w = frame_w,
                frame_h = frame_h,
                content_w = content_w,
                title_bar_h = title_bar_h,
                button_bar_h = button_bar_h,
                footer_h = footer_h,
                cols = cols,
                rows = rows,
                per_page = per_page,
                h_gap = h_gap,
                v_gap = v_gap,
                cell_w = cell_w,
                cell_h = cell_h,
                icon_sz = icon_sz,
                font_size = font_size,
                cell_pad = cell_pad,
                grid_w = grid_w,
                grid_h = grid_h,
            }
        end
    end

    -- 系统图标模式：重置全部 / 应用替换
    local function countReplaced()
        local n = 0
        for _i, item in ipairs(icons_list) do
            if temp_overrides[item.name] then n = n + 1 end
        end
        return n
    end

    -- 注意：这两个函数被后面的 PickerDlg 手势处理器引用，必须在 if 块外声明
    local resetIcons, applyIcons
    local btn_row
    if mode == "system" then
        resetIcons = function()
            if countReplaced() == 0 then
                UIManager:show(InfoMessage:new{ text = _("没有已替换的图标需要重置"), timeout = 2 })
                return
            end
            resetSystemTempOverrides()
            setTable("qa_icon_overrides", {})
            picker_cache = {}
            UIManager:show(Notification:new{ text = _("已重置所有图标，重启后生效"), timeout = 2 })
            askRestart()
        end
        applyIcons = function()
            local n = countReplaced()
            if n == 0 then
                UIManager:show(InfoMessage:new{ text = _("没有已替换的图标需要应用"), timeout = 2 })
                return
            end
            local overrides = getTable("qa_icon_overrides")
            for k, _ in pairs(overrides) do overrides[k] = nil end
            for k, v in pairs(temp_overrides) do if v then overrides[k] = v end end
            setTable("qa_icon_overrides", overrides)
            resetSystemTempOverrides()
            picker_cache = {}
            UIManager:show(Notification:new{ text = string.format(_("已应用 %d 个图标替换"), n), timeout = 2 })
            askRestart()
        end
        btn_row = HorizontalGroup:new{
            align = "center",
            Button:new{ text = string.format(_("重置全部 (%d)"), countReplaced()), width = math.floor(content_w / 2) - 4, show_parent = nil, callback = resetIcons },
            HorizontalSpan:new{ width = 8 },
            Button:new{ text = string.format(_("应用替换 (%d)"), countReplaced()), width = math.floor(content_w / 2) - 4, show_parent = nil, callback = applyIcons },
        }
    else
        local btn_width = math.floor(content_w / 4) - 5
        local show_browse_btn = not filter or filter == "file"
        btn_row = HorizontalGroup:new{
            align = "center",
            Button:new{
                text = _("应用默认"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    if on_select then on_select(nil) end
                end,
            },
            HorizontalSpan:new{ width = 8 },
            Button:new{
                text = "刷新↻",
                width = btn_width,
                show_parent = nil,
                callback = function()
                    clearFileIconsCache()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
                end,
            },
            HorizontalSpan:new{ width = 8 },
            Button:new{
                text = (filter == "file") and _("显示完整图标") or _("仅显示file图标"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    showIconPicker(on_select, saved_icon, (filter == "file") and nil or "file")
                end,
            },
            (show_browse_btn and HorizontalSpan:new{ width = 8 } or nil),
            (show_browse_btn and Button:new{
                text = _("浏览文件"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    clearFileIconsCache()
                    UIManager:show(IconBrowser:new{
                        path = getIconsDir(),
                        onConfirm = function(file_path)
                            if on_select then on_select(file_path) end
                        end,
                    })
                end,
            } or nil),
        }
    end

    local inner_frame = FrameContainer:new{
        width = frame_w,
        height = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        radius = Screen:scaleBySize(8),
        padding = pad,
        VerticalGroup:new{ align = "center" },
    }

    local PickerDlg = InputContainer:extend{}
    function PickerDlg:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self:registerTouchZones({
            {
                id = "picker_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local fd = inner_frame.dimen
                    if not fd or not ges.pos:intersectWith(fd) then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    local gx, gy = ges.pos.x, ges.pos.y
                    local btn_hit = 80
                    -- 左上角：返回（系统模式回到系统图标预览；其他模式重新选择当前图标）
                    if gx >= frame_x + pad and gx < frame_x + pad + btn_hit
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        if parent_mode == "system" then
                            showIconPicker(nil, nil, nil, "system")
                        elseif on_select then
                            on_select(saved_icon)
                        end
                        return true
                    end
                    -- 右上角：筛选
                    if gx >= frame_x + frame_w - pad - btn_hit and gx < frame_x + frame_w - pad
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        showSearchDialog()
                        return true
                    end
                    -- 底部按钮行
                    local btn_y = frame_y + pad + title_bar_h
                    if gy >= btn_y and gy < btn_y + button_bar_h then
                        if mode == "system" then
                            local bw = math.floor(content_w / 2) - 4
                            local bx = frame_x + pad
                            if gx >= bx and gx < bx + bw then
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                resetIcons()
                                return true
                            elseif gx >= bx + bw + 8 and gx < bx + (bw + 8) * 2 then
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                applyIcons()
                                return true
                            end
                        else
                            local bw = math.floor(content_w / 4) - 5
                            local bx = frame_x + pad
                            local idx = 0
                            -- 四个按钮逐个命中检测
                            for i = 0, 3 do
                                if i == 3 and not (not filter or filter == "file") then break end
                                local x0 = bx + (bw + 8) * i
                                if gx >= x0 and gx < x0 + bw then
                                    UIManager:close(self)
                                    UIManager:setDirty("all", "full")
                                    if i == 0 then
                                        if on_select then on_select(nil) end
                                    elseif i == 1 then
                                        clearFileIconsCache()
                                        showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
                                    elseif i == 2 then
                                        showIconPicker(on_select, saved_icon, (filter == "file") and nil or "file")
                                    else
                                        clearFileIconsCache()
                                        UIManager:show(IconBrowser:new{
                                            path = getIconsDir(),
                                            onConfirm = function(file_path)
                                                if on_select then on_select(file_path) end
                                            end,
                                        })
                                    end
                                    return true
                                end
                            end
                        end
                        return true
                    end
                    -- 页脚：上一页 / 下一页 / 跳页
                    local bar_y = frame_y + pad + title_bar_h + button_bar_h + grid_h
                    if gy >= bar_y and gy < bar_y + footer_h then
                        local chev_w = 120
                        if gx < frame_x + pad + chev_w then
                            if cur_page > 1 then
                                cur_page = cur_page - 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        elseif gx > frame_x + frame_w - pad - chev_w then
                            if cur_page < total_pages then
                                cur_page = cur_page + 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        else
                            local dlg
                            dlg = InputDialog:new{
                                title = _("跳转到第几页"),
                                input = tostring(cur_page),
                                input_hint = string.format("1 - %d", total_pages),
                                input_type = "number",
                                buttons = {
                                    {
                                        {
                                            text = _("取消"),
                                            callback = function() UIManager:close(dlg) end,
                                        },
                                        {
                                            text = _("跳转"),
                                            is_enter_default = true,
                                            callback = function()
                                                local page = tonumber(dlg:getInputText())
                                                if page and page >= 1 and page <= total_pages then
                                                    cur_page = page
                                                    UIManager:close(dlg)
                                                    UIManager:setDirty(self, function() return "ui", self.dimen end)
                                                else
                                                    UIManager:show(InfoMessage:new{
                                                        text = string.format(_("请输入 1 到 %d 之间的数字"), total_pages),
                                                        timeout = 2,
                                                    })
                                                end
                                            end,
                                        },
                                    }
                                },
                            }
                            UIManager:show(dlg)
                            pcall(function() dlg:onShowKeyboard() end)
                            return true
                        end
                    end
                    -- 网格：选中图标
                    local grid_start_x = frame_x + pad + (content_w - grid_w) / 2
                    local grid_y = frame_y + pad + title_bar_h + button_bar_h
                    if gx >= grid_start_x and gx < grid_start_x + grid_w
                            and gy >= grid_y and gy < grid_y + grid_h then
                        local col = math.floor((gx - grid_start_x) / (cell_w + h_gap))
                        local row = math.floor((gy - grid_y) / (cell_h + v_gap))
                        local display_list = getDisplayList()
                        local idx = (cur_page - 1) * per_page + row * cols + col + 1
                        if idx >= 1 and idx <= #display_list then
                            local selected_icon = display_list[idx]
                            if mode == "system" then
                                local system_icon_name = selected_icon.name
                                local current = temp_overrides[system_icon_name]
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                showIconPicker(
                                    function(selected)
                                        if selected == current then return end
                                        if selected then
                                            temp_overrides[system_icon_name] = selected:match("([^/]+)$") or selected
                                        else
                                            temp_overrides[system_icon_name] = nil
                                        end
                                        picker_cache = {}
                                        showIconPicker(nil, nil, nil, "system")
                                    end,
                                    current,
                                    "file",
                                    nil,
                                    "system"
                                )
                            else
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                if on_select then on_select(selected_icon.value) end
                            end
                            return true
                        end
                    end
                    return true
                end,
            },
            {
                id = "picker_swipe",
                ges = "swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local dir = ges.direction
                    if dir == "west" then
                        if cur_page < total_pages then
                            cur_page = cur_page + 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    elseif dir == "east" then
                        if cur_page > 1 then
                            cur_page = cur_page - 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    else
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    return true
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        inner_frame.dimen = Geom:new{ x = frame_x, y = frame_y, w = frame_w, h = frame_h }
        inner_frame:paintTo(bb, frame_x, frame_y)
        local content_x, content_y = frame_x + pad, frame_y + pad
        local title_text
        if mode == "system" then title_text = _("系统图标预览")
        elseif parent_mode == "system" then title_text = _("选择替换图标")
        elseif filter == "file" then title_text = _("选择图标文件")
        else title_text = _("选择图标") end
        if filter_keyword ~= "" then title_text = title_text .. " [" .. _("筛选") .. ": \"" .. filter_keyword .. "\"]" end
        local title_tw = TextWidget:new{ text = title_text, face = Font:getFace("smallinfofont"), bold = true }
        title_tw:paintTo(bb, content_x + (content_w - title_tw:getSize().w) / 2, content_y + 12)
        local back_tw = TextWidget:new{ text = "↶", face = Font:getFace("cfont", 24), fgcolor = Blitbuffer.COLOR_BLACK }
        back_tw:paintTo(bb, content_x, content_y + 5)
        local search_tw = TextWidget:new{ text = nerdIconChar("nerd:F002") or "?", face = Font:getFace("symbols", 22), fgcolor = Blitbuffer.COLOR_BLACK }
        search_tw:paintTo(bb, content_x + content_w - 35, content_y + 5)
        btn_row:paintTo(bb, content_x, content_y + title_bar_h)
        local grid_start_x = content_x + (content_w - grid_w) / 2
        local grid_start_y = content_y + title_bar_h + button_bar_h
        local display_list = getDisplayList()
        if #display_list == 0 then
            local empty_tw = TextWidget:new{ text = _("没有匹配的图标"), face = Font:getFace("cfont"), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
            empty_tw:paintTo(bb, grid_start_x + (grid_w - empty_tw:getSize().w) / 2, grid_start_y + grid_h / 2 - 20)
        else
            page_widgets[cur_page]:paintTo(bb, grid_start_x, grid_start_y)
        end
        if total_pages > 1 then
            local bar_y = grid_start_y + grid_h + (footer_h - 20) / 2
            local left = TextWidget:new{ text = "◀", face = Font:getFace("cfont", 20), fgcolor = Blitbuffer.COLOR_BLACK }
            left:paintTo(bb, content_x + 10, bar_y)
            local right = TextWidget:new{ text = "▶", face = Font:getFace("cfont", 20), fgcolor = Blitbuffer.COLOR_BLACK }
            right:paintTo(bb, frame_x + frame_w - pad - 50, bar_y)
            local page_text = TextWidget:new{ text = string.format("%d / %d", cur_page, total_pages), face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.gray(0.5) }
            page_text:paintTo(bb, frame_x + (frame_w - page_text:getSize().w) / 2, bar_y)
        end
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
end


-- ---- 导出 ----
return {
    nerdIconChar = nerdIconChar,
    isNerdIcon = isNerdIcon,
    getIconsDir = getIconsDir,
    getIconFile = getIconFile,
    getIconWidget = getIconWidget,
    getFileIcons = getFileIcons,
    clearFileIconsCache = clearFileIconsCache,
    resetSystemTempOverrides = resetSystemTempOverrides,
    showIconPicker = showIconPicker,
}




