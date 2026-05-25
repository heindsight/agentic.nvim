--- @diagnostic disable: invisible
local assert = require("tests.helpers.assert")

local function normalize(p)
    return vim.fn.resolve(vim.fn.fnamemodify(p, ":p"))
end

local function assert_buf_name(expected, bufnr)
    assert.equal(
        normalize(expected),
        normalize(vim.api.nvim_buf_get_name(bufnr))
    )
end

describe("WindowDecoration._set_buffer_name", function()
    --- @type agentic.ui.WindowDecoration
    local WindowDecoration

    --- @type integer[]
    local created_bufs

    before_each(function()
        package.loaded["agentic.ui.window_decoration"] = nil
        WindowDecoration = require("agentic.ui.window_decoration")
        created_bufs = {}
    end)

    after_each(function()
        for _, b in ipairs(created_bufs) do
            pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
    end)

    local function new_buf()
        local b = vim.api.nvim_create_buf(false, true)
        table.insert(created_bufs, b)
        return b
    end

    it("sets name when no buffer holds it", function()
        local bufnr = new_buf()
        local name = vim.fn.tempname() .. "_no_collision"

        WindowDecoration._set_buffer_name(bufnr, name)

        assert_buf_name(name, bufnr)
    end)

    it("renames existing buffer to <name>-old-1 on first collision", function()
        local existing = new_buf()
        local name = vim.fn.tempname() .. "_collision"
        vim.api.nvim_buf_set_name(existing, name)

        local target = new_buf()
        WindowDecoration._set_buffer_name(target, name)

        assert_buf_name(name, target)
        assert_buf_name(name .. "-old-1", existing)
    end)

    it("uses <name>-old-2 when <name>-old-1 also exists", function()
        local oldest = new_buf()
        local name = vim.fn.tempname() .. "_double"
        vim.api.nvim_buf_set_name(oldest, name .. "-old-1")

        local existing = new_buf()
        vim.api.nvim_buf_set_name(existing, name)

        local target = new_buf()
        WindowDecoration._set_buffer_name(target, name)

        assert_buf_name(name, target)
        assert_buf_name(name .. "-old-2", existing)
        assert_buf_name(name .. "-old-1", oldest)
    end)

    it("uses <name>-old-3 when -old-1 and -old-2 exist", function()
        local b1 = new_buf()
        local name = vim.fn.tempname() .. "_triple"
        vim.api.nvim_buf_set_name(b1, name .. "-old-1")

        local b2 = new_buf()
        vim.api.nvim_buf_set_name(b2, name .. "-old-2")

        local existing = new_buf()
        vim.api.nvim_buf_set_name(existing, name)

        local target = new_buf()
        WindowDecoration._set_buffer_name(target, name)

        assert_buf_name(name, target)
        assert_buf_name(name .. "-old-3", existing)
    end)

    it(
        "uses <name>-old-4 when name, -old-1, -old-2, -old-3 all pre-exist",
        function()
            local name = vim.fn.tempname() .. "_quad"

            local b1 = new_buf()
            vim.api.nvim_buf_set_name(b1, name .. "-old-1")
            local b2 = new_buf()
            vim.api.nvim_buf_set_name(b2, name .. "-old-2")
            local b3 = new_buf()
            vim.api.nvim_buf_set_name(b3, name .. "-old-3")

            local existing = new_buf()
            vim.api.nvim_buf_set_name(existing, name)

            local target = new_buf()
            WindowDecoration._set_buffer_name(target, name)

            assert_buf_name(name, target)
            assert_buf_name(name .. "-old-4", existing)
            assert_buf_name(name .. "-old-1", b1)
            assert_buf_name(name .. "-old-2", b2)
            assert_buf_name(name .. "-old-3", b3)
        end
    )

    it("is a no-op when bufnr already holds the target name", function()
        local bufnr = new_buf()
        local name = vim.fn.tempname() .. "_same"
        vim.api.nvim_buf_set_name(bufnr, name)

        WindowDecoration._set_buffer_name(bufnr, name)

        assert_buf_name(name, bufnr)
    end)
end)

describe("WindowDecoration._build_buffer_name", function()
    --- @type agentic.ui.WindowDecoration
    local WindowDecoration

    before_each(function()
        package.loaded["agentic.ui.window_decoration"] = nil
        WindowDecoration = require("agentic.ui.window_decoration")

        -- Close leaked tabpages from earlier test files so single-tab
        -- tests see exactly one tabpage.
        local current = vim.api.nvim_get_current_tabpage()
        for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
            if tp ~= current then
                pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(tp))
            end
        end
    end)

    it("prefixes with session CWD when agentic_session_cwd is set", function()
        local tab_page_id = vim.api.nvim_get_current_tabpage()
        vim.t[tab_page_id].agentic_session_cwd = "/home/user/project"

        local result = WindowDecoration._build_buffer_name(
            "󰻞 Agentic Chat",
            tab_page_id
        )

        assert.equal("/home/user/project/󰻞 Agentic Chat", result)

        vim.t[tab_page_id].agentic_session_cwd = nil
    end)

    it("falls back to bare header when no session CWD is set", function()
        local tab_page_id = vim.api.nvim_get_current_tabpage()
        vim.t[tab_page_id].agentic_session_cwd = nil

        local result = WindowDecoration._build_buffer_name(
            "󰻞 Agentic Chat",
            tab_page_id
        )

        assert.equal("󰻞 Agentic Chat", result)
    end)

    it("includes tab suffix with CWD prefix for multi-tab", function()
        local tab_page_id = vim.api.nvim_get_current_tabpage()
        vim.t[tab_page_id].agentic_session_cwd = "/home/user/project"

        -- Create a second tabpage so total_tabs > 1
        vim.cmd("tabnew")
        local tab2 = vim.api.nvim_get_current_tabpage()

        local result = WindowDecoration._build_buffer_name(
            "󰻞 Agentic Chat",
            tab_page_id
        )

        assert.equal(
            string.format(
                "/home/user/project/󰻞 Agentic Chat (Tab %d)",
                tab_page_id
            ),
            result
        )

        -- Cleanup
        vim.t[tab_page_id].agentic_session_cwd = nil
        vim.api.nvim_set_current_tabpage(tab_page_id)
        vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(tab2))
    end)

    it("returns nil for nil header_text", function()
        local tab_page_id = vim.api.nvim_get_current_tabpage()
        local result = WindowDecoration._build_buffer_name(nil, tab_page_id)
        assert.is_nil(result)
    end)

    it("returns nil for empty header_text", function()
        local tab_page_id = vim.api.nvim_get_current_tabpage()
        local result = WindowDecoration._build_buffer_name("", tab_page_id)
        assert.is_nil(result)
    end)
end)
