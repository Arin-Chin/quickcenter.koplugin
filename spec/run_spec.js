// run_spec.js — 用 fengari 跑 busted 风格的 qc_config_spec（内存文件模拟，不碰磁盘）
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const fs = require('fs');
const path = require('path');

const PLUGIN = path.join(__dirname, '..');
const SPEC = path.join(PLUGIN, 'spec', 'qc_config_spec.lua');
const specSrc = fs.readFileSync(SPEC, 'utf8');

const bootstrap = `
-- ===== 内存文件系统（模拟 io / os，避免依赖真实磁盘）=====
_STORE = {}
do
    local real_os_rename = os.rename
    os.rename = function(from, to)
        _STORE[to] = _STORE[from]
        _STORE[from] = nil
        return true
    end
    os.remove = function(p) _STORE[p] = nil; return true end
    local real_os_exit = os.exit
    local function mkfile(path)
        local file = {}
        file.content = _STORE[path] or ''
        function file:write(s)
            if type(s) == 'table' then s = table.concat(s) end
            self.content = self.content .. tostring(s)
            return true
        end
        function file:close() _STORE[path] = self.content; return true end
        function file:flush() return true end
        function file:read(fmt)
            if fmt == '*all' or fmt == nil then return self.content end
            return nil
        end
        return file
    end
    io = { -- 替换整表（fengari 浏览器版 io.open 本来就缺失）
        open = function(path, mode)
            if mode and mode:sub(1,1) == 'w' then
                local f = mkfile(path); _STORE[path] = ''
                return f
            elseif mode and mode:sub(1,1) == 'r' then
                if _STORE[path] == nil then return nil end
                return mkfile(path)
            end
            return nil
        end,
        lines = function() return function() return nil end end,
        write = function() return true end,
        close = function() return true end,
        type = function() return 'file' end,
    }
end
-- ===== 依赖 stub =====
package.preload["logger"] = function()
    return { info = function() end, warn = function() end, err = function() end, dbg = function() end }
end
package.preload["datastorage"] = function()
    return { getSettingsDir = function() return "/sandbox" end, getDataDir = function() return "/sandbox" end }
end
package.preload["json"] = function()
    local function cp(v) return v end -- 测试用浅拷贝即可
    return { encode = cp, decode = cp }
end
package.path = ${JSON.stringify(path.join(PLUGIN, '?.lua'))} .. ";" .. package.path
-- ===== busted 极简 shim（真 busted 下不会走到这里）=====
if type(assert) ~= 'table' then
    local std_assert = assert
    _G.assert = setmetatable({
        are_equal = function(a, b, msg) std_assert(a == b, msg or (tostring(a) .. " ~= " .. tostring(b))) end,
        is_true = function(v, msg) std_assert(v == true, msg or "expected true, got " .. tostring(v)) end,
        is_false = function(v, msg) std_assert(v == false, msg or "expected false") end,
        is_nil = function(v, msg) std_assert(v == nil, msg or "expected nil, got " .. tostring(v)) end,
        is_not_nil = function(v, msg) std_assert(v ~= nil, msg or "expected non-nil") end,
    }, {
        __call = function(self, v, msg) return std_assert(v, msg) end,
    })
end
if describe == nil then
    local passed, failed, current = 0, 0, nil
    function describe(name, fn) current = name; fn() end
    function it(name, fn)
        local ok, err = pcall(fn)
        if ok then passed = passed + 1
            print("  ✓ " .. current .. " > " .. name)
        else
            failed = failed + 1
            print("  ✗ " .. current .. " > " .. name)
            print("      " .. tostring(err))
        end
    end
    local function finish()
        print(string.format("\\n%d passed, %d failed", passed, failed))
        os.exit(failed == 0 and 0 or 1)
    end
    -- spec 文件末尾需要触发收尾
    _SPEC_FINISH = finish
else
    _SPEC_FINISH = function() end
end
`;

const specWithFinish = specSrc + '\nif _SPEC_FINISH then _SPEC_FINISH() end\n';
const program = bootstrap + '\n-- ===== 被测 spec =====\n' + specWithFinish;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const status = lauxlib.luaL_dostring(L, to_luastring(program));
if (status !== lua.LUA_OK) {
  try { lauxlib.luaL_tolstring(L, -1, null); console.error('SPEC RUN ERROR:', lua.lua_tojsstring(L, -1)); }
  catch (e) { console.error('SPEC RUN ERROR:', e.message); }
  process.exit(1);
}
