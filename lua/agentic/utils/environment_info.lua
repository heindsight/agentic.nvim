--- @class agentic.utils.EnvironmentInfo
local M = {}

--- Build the `<environment_info>` block for a session, with git metadata
--- resolved relative to the session's working directory.
--- @param cwd string Working directory used as project root and for git commands
--- @return string info
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

    local git_root = vim.fs.root(project_root, ".git")
    if git_root then
        project_root = git_root
        res = res .. "\n- This is a Git repository."

        local git_opts = { cwd = cwd, text = true }

        local ok, branch_result = pcall(function()
            return vim.system(
                { "git", "rev-parse", "--abbrev-ref", "HEAD" },
                git_opts
            )
                :wait()
        end)
        if ok and branch_result.code == 0 and branch_result.stdout then
            local branch = vim.trim(branch_result.stdout)
            if branch ~= "" then
                res = res .. string.format("\n- Current branch: %s", branch)
            end
        end

        local changed_ok, changed_result = pcall(function()
            return vim.system({ "git", "status", "--porcelain" }, git_opts)
                :wait()
        end)
        if
            changed_ok
            and changed_result.code == 0
            and changed_result.stdout
        then
            local changed = (changed_result.stdout):gsub("\n$", "")
            if changed ~= "" then
                local files = vim.split(changed, "\n")
                res = res .. "\n- Changed files:"
                for _, file in ipairs(files) do
                    res = res .. "\n  - " .. file
                end
            end
        end

        local commits_ok, commits_result = pcall(function()
            return vim.system({
                "git",
                "log",
                "-3",
                "--oneline",
                "--format=%h (%ar) %an: %s",
            }, git_opts):wait()
        end)
        if
            commits_ok
            and commits_result.code == 0
            and commits_result.stdout
        then
            local commits = (commits_result.stdout):gsub("\n$", "")
            if commits ~= "" then
                local commit_lines = vim.split(commits, "\n")
                res = res .. "\n- Recent commits:"
                for _, commit in ipairs(commit_lines) do
                    res = res .. "\n  - " .. commit
                end
            end
        end
    end

    res = res .. string.format("\n- Project root: %s", project_root)

    res = "<environment_info>\n" .. res .. "\n</environment_info>"
    return res
end

return M
