--- @diagnostic disable: invisible
local assert = require("tests.helpers.assert")
local spy = require("tests.helpers.spy")

local FilePicker = require("agentic.ui.file_picker")

--- Computes the differences between two tables
--- @param left table
--- @param right table
--- @return string[] only_in_left Items only in left table
--- @return string[] only_in_right Items only in right table
local function table_diff(left, right)
    local left_set = {}
    for _, v in ipairs(left) do
        left_set[v] = true
    end

    local right_set = {}
    for _, v in ipairs(right) do
        right_set[v] = true
    end

    local only_in_left = {}
    for _, v in ipairs(left) do
        if not right_set[v] then
            table.insert(only_in_left, v)
        end
    end

    local only_in_right = {}
    for _, v in ipairs(right) do
        if not left_set[v] then
            table.insert(only_in_right, v)
        end
    end

    return only_in_left, only_in_right
end

describe("FilePicker:scan_files", function()
    --- @type TestStub|nil
    local system_stub
    local original_cmd_rg
    local original_cmd_fd
    local original_cmd_git

    --- @type agentic.ui.FilePicker
    local picker

    before_each(function()
        original_cmd_rg = FilePicker.CMD_RG[1]
        original_cmd_fd = FilePicker.CMD_FD[1]
        original_cmd_git = FilePicker.CMD_GIT[1]
        picker = FilePicker:new(
            vim.api.nvim_create_buf(false, true),
            vim.fn.getcwd()
        ) --[[@as agentic.ui.FilePicker]]
    end)

    after_each(function()
        if system_stub then
            system_stub:revert()
            system_stub = nil
        end
        FilePicker.CMD_RG[1] = original_cmd_rg
        FilePicker.CMD_FD[1] = original_cmd_fd
        FilePicker.CMD_GIT[1] = original_cmd_git
    end)

    --- Build a `vim.system` stub-shim returning a `:wait()`-able fake
    --- that yields the given results in sequence.
    --- @param results { code: integer, stdout: string, stderr?: string }[]
    local function stub_vim_system(results)
        --- @type integer
        local idx = 0
        local stub = spy.stub(vim, "system")
        stub:invokes(function()
            idx = idx + 1
            local res = results[idx] or { code = 1, stdout = "", stderr = "" }
            return {
                wait = function()
                    return res
                end,
            }
        end)
        return stub
    end

    describe("mocked commands", function()
        it("should stop at first successful command", function()
            -- Make all commands available by setting them to executables that exist
            FilePicker.CMD_RG[1] = "echo"
            FilePicker.CMD_FD[1] = "echo"
            FilePicker.CMD_GIT[1] = "echo"

            -- _build_scan_commands runs `git rev-parse --git-dir` first
            -- (success enables git ls-files), so the order of vim.system calls is:
            -- 1. git rev-parse (precheck) — make it succeed so git is added
            -- 2. rg (first command) — empty success means it returns no files
            -- 3. fd (second command) — returns files
            system_stub = stub_vim_system({
                { code = 0, stdout = "" }, -- git precheck
                { code = 0, stdout = "" }, -- rg (empty -> falls through)
                { code = 0, stdout = "file1.lua\nfile2.lua\nfile3.lua\n" }, -- fd
            })

            local files = picker:scan_files()

            -- 1 precheck + 2 scan commands = 3 calls
            assert.equal(3, system_stub.call_count)
            assert.equal(3, #files)
        end)

        it("runs scan commands with cwd = session_cwd", function()
            FilePicker.CMD_RG[1] = "echo"
            FilePicker.CMD_FD[1] = "nonexistent_fd"
            FilePicker.CMD_GIT[1] = "nonexistent_git"

            local sentinel = "/tmp/sentinel-cwd"
            picker.session_cwd = sentinel

            system_stub = stub_vim_system({
                { code = 0, stdout = "lua/foo.lua\n" }, -- rg
            })

            picker:scan_files()

            assert.is_true(system_stub.call_count >= 1)
            for i = 1, system_stub.call_count do
                local opts = system_stub.calls[i][2]
                assert.equal(sentinel, opts.cwd)
            end
        end)

        it("renders scan output relative to session_cwd", function()
            FilePicker.CMD_RG[1] = "echo"
            FilePicker.CMD_FD[1] = "nonexistent_fd"
            FilePicker.CMD_GIT[1] = "nonexistent_git"

            local sentinel = "/tmp/sentinel-abs"
            picker.session_cwd = sentinel

            system_stub = stub_vim_system({
                { code = 0, stdout = "lua/foo.lua\n" },
            })

            local files = picker:scan_files()

            assert.equal(1, #files)
            -- Display path is anchored to session_cwd so picker output
            -- is consistent regardless of where vim has been :cd'd.
            assert.equal("@lua/foo.lua", files[1].word)
        end)

        it(
            "renders scan output relative to session_cwd when vim CWD is a descendant",
            function()
                FilePicker.CMD_RG[1] = "echo"
                FilePicker.CMD_FD[1] = "nonexistent_fd"
                FilePicker.CMD_GIT[1] = "nonexistent_git"

                -- Use real directories so chdir succeeds. The project root
                -- is session_cwd; vim is cd'd into a real subdirectory.
                local project_root = vim.fn.getcwd()
                local descendant = project_root .. "/lua/agentic/ui"
                picker.session_cwd = project_root

                system_stub = stub_vim_system({
                    {
                        code = 0,
                        stdout = "doc/agentic.txt\nlua/agentic/ui/file_picker.lua\n",
                    },
                })

                local original_cwd = vim.fn.getcwd()
                local ok, err = pcall(function()
                    vim.fn.chdir(descendant)
                    local files = picker:scan_files()

                    assert.equal(2, #files)
                    -- Without the fix, files outside vim CWD render via
                    -- :~ (e.g. "~/code/agentic.nvim/doc/agentic.txt") and
                    -- files inside it collapse to bare basenames
                    -- (e.g. "file_picker.lua"). After the fix, both anchor
                    -- to session_cwd and round-trip cleanly when sent to
                    -- the agent (whose cwd is session_cwd).
                    assert.equal("@doc/agentic.txt", files[1].word)
                    assert.equal(
                        "@lua/agentic/ui/file_picker.lua",
                        files[2].word
                    )
                end)
                vim.fn.chdir(original_cwd)
                if not ok then
                    error(err)
                end
            end
        )
    end)

    describe("vim.system spawn errors", function()
        it(
            "scan_files skips a command that throws and tries the next",
            function()
                FilePicker.CMD_RG[1] = "echo"
                FilePicker.CMD_FD[1] = "echo"
                FilePicker.CMD_GIT[1] = "nonexistent_git"

                local call_idx = 0
                system_stub = spy.stub(vim, "system")
                system_stub:invokes(function()
                    call_idx = call_idx + 1
                    if call_idx == 1 then
                        error("ENOENT: no such file or directory")
                    end
                    return {
                        wait = function()
                            return {
                                code = 0,
                                stdout = "a.lua\nb.lua\n",
                            }
                        end,
                    }
                end)

                local files = picker:scan_files()

                assert.equal(2, #files)
            end
        )

        it("_build_scan_commands excludes git when rev-parse throws", function()
            FilePicker.CMD_RG[1] = "nonexistent_rg"
            FilePicker.CMD_FD[1] = "nonexistent_fd"
            FilePicker.CMD_GIT[1] = "echo"

            system_stub = spy.stub(vim, "system")
            system_stub:invokes(function()
                error("ENOENT: no such file or directory")
            end)

            local commands = picker:_build_scan_commands()

            assert.equal(0, #commands)
        end)
    end)

    describe("real commands", function()
        local original_exclude_patterns

        before_each(function()
            original_exclude_patterns =
                vim.tbl_extend("force", {}, FilePicker.GLOB_EXCLUDE_PATTERNS)
        end)

        after_each(function()
            FilePicker.GLOB_EXCLUDE_PATTERNS = original_exclude_patterns
        end)

        it("should return same files in same order for all commands", function()
            -- Test rg
            FilePicker.CMD_RG[1] = original_cmd_rg
            FilePicker.CMD_FD[1] = "nonexistent_fd"
            FilePicker.CMD_GIT[1] = "nonexistent_git"
            local files_rg = picker:scan_files()

            -- Test fd
            FilePicker.CMD_RG[1] = "nonexistent_rg"
            FilePicker.CMD_FD[1] = original_cmd_fd
            FilePicker.CMD_GIT[1] = "nonexistent_git"
            local files_fd = picker:scan_files()

            -- Test git
            FilePicker.CMD_RG[1] = "nonexistent_rg"
            FilePicker.CMD_FD[1] = "nonexistent_fd"
            FilePicker.CMD_GIT[1] = original_cmd_git
            local files_git = picker:scan_files()

            -- All commands should return more than 0 files
            assert.is_true(#files_rg > 0)
            assert.is_true(#files_fd > 0)
            assert.is_true(#files_git > 0)

            -- git ls-files emits tracked symlinks-to-directories as a single
            -- entry (e.g. ".claude/skills/"), which to_smart_path renders with
            -- a trailing slash. rg/fd list the files *through* the symlink and
            -- never emit the bare entry, so drop trailing-slash words to keep
            -- the cross-command comparison symmetric.
            local function words_without_dirs(files)
                local words = {}
                for _, f in ipairs(files) do
                    if not f.word:match("/$") then
                        table.insert(words, f.word)
                    end
                end
                return words
            end

            -- Extract just the word (filename) for comparison
            local words_rg = words_without_dirs(files_rg)
            local words_fd = words_without_dirs(files_fd)
            local words_git = words_without_dirs(files_git)

            local rg_only, fd_only = table_diff(words_rg, words_fd)
            assert.are.same(rg_only, fd_only)

            local fd_only2, git_only = table_diff(words_fd, words_git)
            assert.are.same(fd_only2, git_only)

            assert.are.equal(#words_rg, #words_fd)
            assert.are.equal(#words_fd, #words_git)
        end)

        it("should use glob fallback when all commands fail", function()
            -- First, get files from rg for comparison
            FilePicker.CMD_RG[1] = original_cmd_rg
            FilePicker.CMD_FD[1] = "nonexistent_fd"
            FilePicker.CMD_GIT[1] = "nonexistent_git"
            local files_rg = picker:scan_files()

            -- Disable all commands to force glob fallback
            FilePicker.CMD_RG[1] = "nonexistent_rg"
            FilePicker.CMD_FD[1] = "nonexistent_fd"
            FilePicker.CMD_GIT[1] = "nonexistent_git"

            -- deps is the temp folder where mini.nvim is installed during tests
            table.insert(FilePicker.GLOB_EXCLUDE_PATTERNS, "deps/")
            -- lazy_repro is the temp folder where plugins are installed during tests
            table.insert(FilePicker.GLOB_EXCLUDE_PATTERNS, "lazy_repro/")
            -- .local is the folder where Neovim is installed during tests in CI
            table.insert(FilePicker.GLOB_EXCLUDE_PATTERNS, "%.local/")
            -- settings.local.json is gitignored but glob fallback doesn't respect .gitignore
            table.insert(
                FilePicker.GLOB_EXCLUDE_PATTERNS,
                "settings%.local%.json"
            )
            -- Local headless Neovim runs can create nvim.log after rg scanned.
            table.insert(FilePicker.GLOB_EXCLUDE_PATTERNS, "nvim%.log$")
            -- Scheduled-task runs create .claude/scheduled_tasks.lock; gitignored
            -- but glob fallback doesn't respect .gitignore.
            table.insert(
                FilePicker.GLOB_EXCLUDE_PATTERNS,
                "scheduled_tasks%.lock$"
            )
            -- .opencode/.gitignore ignores specific files (bun.lock, package.json, etc.)
            -- rg/fd/git respect nested .gitignore but glob fallback doesn't
            table.insert(FilePicker.GLOB_EXCLUDE_PATTERNS, "%.opencode/bun")
            table.insert(FilePicker.GLOB_EXCLUDE_PATTERNS, "%.opencode/package")
            table.insert(
                FilePicker.GLOB_EXCLUDE_PATTERNS,
                "%.opencode/%.gitignore"
            )

            local files_glob = picker:scan_files()

            assert.is_true(#files_glob > 0)

            -- Extract just the word (filename) for comparison
            local words_rg = vim.tbl_map(function(f)
                return f.word
            end, files_rg)
            local words_glob = vim.tbl_map(function(f)
                return f.word
            end, files_glob)

            local rg_only, glob_only = table_diff(words_rg, words_glob)
            assert.are.same(rg_only, glob_only)

            assert.are.equal(#words_rg, #words_glob)
        end)
    end)
end)

describe("FilePicker auto_trigger", function()
    local Config = require("agentic.config")

    --- @type TestStub
    local create_autocmd_stub
    local original_auto_trigger
    local original_enabled

    before_each(function()
        original_auto_trigger = Config.file_picker.auto_trigger
        original_enabled = Config.file_picker.enabled
        Config.file_picker.enabled = true
        create_autocmd_stub = spy.stub(vim.api, "nvim_create_autocmd")
    end)

    after_each(function()
        Config.file_picker.auto_trigger = original_auto_trigger
        Config.file_picker.enabled = original_enabled
        create_autocmd_stub:revert()
    end)

    local function textchangedi_call_count()
        local count = 0
        for _, call in ipairs(create_autocmd_stub.calls) do
            if call[1] == "TextChangedI" then
                count = count + 1
            end
        end
        return count
    end

    it("registers TextChangedI autocmd when auto_trigger is true", function()
        Config.file_picker.auto_trigger = true
        local buf = vim.api.nvim_create_buf(false, true)
        FilePicker:new(buf, vim.fn.getcwd())
        assert.equal(1, textchangedi_call_count())
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it(
        "does not register TextChangedI autocmd when auto_trigger is false",
        function()
            Config.file_picker.auto_trigger = false
            local buf = vim.api.nvim_create_buf(false, true)
            FilePicker:new(buf, vim.fn.getcwd())
            assert.equal(0, textchangedi_call_count())
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    )
end)

describe("FilePicker keymap fallback", function()
    local child = require("tests.helpers.child").new()

    --- Setup a tracking expr keymap using vimscript (fully typed, no child.lua needed)
    --- @param key string The key to map (e.g., "<Tab>", "<CR>")
    --- @param global_name string The global variable name (g:) to track calls
    local function setup_tracking_keymap(key, global_name)
        child.g[global_name] = false
        -- vimscript expr: execute() returns "" on success, concat with return value
        local rhs = ("execute('let g:%s = v:true') .. '%s_CALLED'"):format(
            global_name,
            key:upper():gsub("[<>]", "")
        )
        child.api.nvim_set_keymap("i", key, rhs, { expr = true })
    end

    --- Load FilePicker in child process to void polluting main test env
    local function load_file_picker()
        child.lua([[require("agentic.ui.file_picker"):new(0, vim.fn.getcwd())]])
    end

    before_each(function()
        child.setup()
    end)

    after_each(function()
        child.stop()
    end)

    it("should accept completion when completion menu is visible", function()
        local prop_name = "tab_called"
        setup_tracking_keymap("<Tab>", prop_name)
        load_file_picker()

        -- Set up buffer with multiple completion candidates
        child.api.nvim_buf_set_lines(
            0,
            0,
            -1,
            false,
            { "hello help helicopter", "" }
        )
        child.api.nvim_win_set_cursor(0, { 2, 0 })

        -- Type partial word and trigger keyword completion
        child.type_keys("i", "hel", "<C-x><C-n>")

        -- Verify completion menu is actually visible
        assert.equal(1, child.fn.pumvisible())

        -- Now press Tab while menu is visible - should accept completion, not call fallback
        child.type_keys("<Tab>")

        assert.is_false(child.g[prop_name])
    end)
end)
