-- qc_config_spec.lua — QuickCenter qc_config 模块单元测试
-- 风格：busted（describe/it）；也兼容轻量 runner（.check/run_spec.js 自带 describe/it shim）。
-- 运行方式：
--   1) busted quickcenter.koplugin/spec（需安装 busted）
--   2) node .check/run_spec.js （无需安装，纯 fengari 内存文件模拟）
-- 说明：测试在“内存文件系统”上进行（runner 会先替换 io/os 并 stub logger/datastorage/json），
-- 因此不会触碰真实磁盘，可反复运行。

describe("qc_config", function()

    it("默认配置可访问，缺文件时自动生成", function()
        local cfg = require("qc_config")
        -- 首次访问应触发“创建默认配置文件”逻辑
        assert.are_equal("star.empty", cfg.getString("qa_tab_icon"))
        assert.is_true(cfg.getBool("qa_enabled"))
        assert.are_equal(66, cfg.MAX_SLOTS)
        -- 配置文件应已写入内存盘
        assert.is_not_nil(_STORE["/sandbox/quickcenter.lua"])
    end)

    it("设置写入后可跨‘重启’持久化（save/load 往返）", function()
        local cfg = require("qc_config")
        cfg.setString("qa_shape", "bare")
        cfg.setNumber("qa_button_size_pct", 120)
        assert.are_equal("bare", cfg.getString("qa_shape"))
        -- 模拟重启：清 module 缓存后重新 require，应读到落盘值
        package.loaded["qc_config"] = nil
        cfg = require("qc_config")
        assert.are_equal("bare", cfg.getString("qa_shape"))
        assert.are_equal(120, cfg.getNumber("qa_button_size_pct"))
    end)

    it("serializeTable 转义往返：引号/反斜杠/换行/Unicode/嵌套", function()
        local cfg = require("qc_config")
        local tricky = {
            s1 = 'he said "hi"',
            s2 = "back\\slash",
            s3 = "line1\nline2\r\n",
            s4 = "中文·ünïcode ✓",
            n = 3.14,
            b = false,
            nested = { a = { b = { c = "deep" } }, [5] = "idx" },
        }
        local ser = cfg.serializeTable(tricky)
        local chunk, err = load("return " .. ser)
        assert.is_nil(err)
        local loaded = chunk()
        assert.are_equal(tricky.s1, loaded.s1)
        assert.are_equal(tricky.s2, loaded.s2)
        assert.are_equal(tricky.s3, loaded.s3)
        assert.are_equal(tricky.s4, loaded.s4)
        assert.are_equal(tricky.n, loaded.n)
        assert.is_false(loaded.b)
        assert.are_equal(tricky.nested.a.b.c, loaded.nested.a.b.c)
        assert.are_equal(tricky.nested[5], loaded.nested[5])
    end)

    it("配置文件损坏时自动备份并回退默认", function()
        -- 写入垃圾内容模拟损坏
        _STORE["/sandbox/quickcenter.lua"] = "this is {{{ not valid lua"
        package.loaded["qc_config"] = nil
        local cfg = require("qc_config")
        -- 仍能读取默认值（回退路径）
        assert.are_equal("star.empty", cfg.getString("qa_tab_icon"))
        -- 原文件应被备份
        assert.is_not_nil(_STORE["/sandbox/quickcenter.lua.bak"])
        -- 恢复现场
        _STORE["/sandbox/quickcenter.lua"] = nil
        _STORE["/sandbox/quickcenter.lua.bak"] = nil
        package.loaded["qc_config"] = nil
        cfg = require("qc_config")
        assert.are_equal("star.empty", cfg.getString("qa_tab_icon"))
    end)

end)
