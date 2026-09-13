local assert = require("tests.helpers.assert")

describe("agentic.utils.EnvironmentInfo", function()
    local EnvironmentInfo = require("agentic.utils.environment_info")

    it("reports the Session CWD as the project root", function()
        local project_dir = vim.fn.tempname()
        vim.fn.mkdir(project_dir, "p")

        local info = EnvironmentInfo.get_system_info(project_dir)

        assert.is_not_nil(info:find("- Project root: " .. project_dir, 1, true))
        assert.is_nil(info:find("Git repository", 1, true))
    end)

    it("reads git state from the Session CWD, not the Neovim cwd", function()
        local project_dir = vim.fn.tempname()
        vim.fn.mkdir(project_dir, "p")
        vim.system({ "git", "init", "-q", "-b", "session-cwd-branch" }, {
            cwd = project_dir,
        }):wait()
        vim.fn.writefile({ "" }, project_dir .. "/untracked.lua")

        local info = EnvironmentInfo.get_system_info(project_dir)

        assert.is_not_nil(info:find("- This is a Git repository.", 1, true))
        assert.is_not_nil(info:find("- Project root: " .. project_dir, 1, true))
        assert.is_not_nil(info:find("?? untracked.lua", 1, true))
        assert.is_nil(info:find(vim.fn.getcwd(), 1, true))
    end)
end)
