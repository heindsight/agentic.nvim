--- @class agentic.utils.EnvironmentInfo
local M = {}

--- @param cmd string[]
--- @param cwd string
--- @return string|nil stdout nil on a non-zero exit or empty output
local function run_git(cmd, cwd)
    local ok, result = pcall(function()
        return vim.system(cmd, { cwd = cwd, text = true }):wait()
    end)
    if not ok or result.code ~= 0 then
        return nil
    end

    local stdout = (result.stdout or ""):gsub("\n$", "")
    if stdout == "" then
        return nil
    end

    return stdout
end

--- @param cwd string Session CWD, reported as the project root
--- @return string
function M.get_system_info(cwd)
    local os_name = vim.uv.os_uname().sysname
    local os_version = vim.uv.os_uname().release
    local os_machine = vim.uv.os_uname().machine
    local shell = os.getenv("SHELL")
    local neovim_version = tostring(vim.version())
    local today = os.date("%Y-%m-%d")

    local res = string.format(
        [[
- Platform: %s-%s-%s
- Shell: %s
- Editor: Neovim %s
- Current date: %s]],
        os_name,
        os_version,
        os_machine,
        shell,
        neovim_version,
        today
    )

    local project_root = cwd

    -- Git commands run in the Session CWD: `vim.fn.system` would inherit
    -- Neovim's process cwd and describe the wrong repository.
    local git_root = vim.fs.root(cwd, ".git")
    if git_root then
        project_root = git_root
        res = res .. "\n- This is a Git repository."

        local branch =
            run_git({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, cwd)
        if branch then
            res = res .. string.format("\n- Current branch: %s", branch)
        end

        local changed = run_git({ "git", "status", "--porcelain" }, cwd)
        if changed then
            local files = vim.split(changed, "\n")
            res = res .. "\n- Changed files:"
            for _, file in ipairs(files) do
                res = res .. "\n  - " .. file
            end
        end

        local commits = run_git({
            "git",
            "log",
            "-3",
            "--oneline",
            "--format=%h (%ar) %an: %s",
        }, cwd)
        if commits then
            local commit_lines = vim.split(commits, "\n")
            res = res .. "\n- Recent commits:"
            for _, commit in ipairs(commit_lines) do
                res = res .. "\n  - " .. commit
            end
        end
    end

    res = res .. string.format("\n- Project root: %s", project_root)

    res = "<environment_info>\n" .. res .. "\n</environment_info>"
    return res
end
return M
