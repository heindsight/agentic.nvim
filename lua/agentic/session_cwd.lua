local Config = require("agentic.config")
local Logger = require("agentic.utils.logger")

--- Resolves the Session CWD (see `CONTEXT.md`) for one session creation.
--- The only module allowed to read `vim.fn.getcwd()` (ADR 0009).
--- @class agentic.SessionCwd
local SessionCwd = {}

--- @param path string
--- @return boolean
local function is_absolute(path)
    return vim.startswith(path, "/")
        or path:match("^%a:[/\\]") ~= nil
        or vim.startswith(path, "\\\\")
end

--- `:p` appends a slash to a directory; strip it, keeping a bare root.
--- @param path string
--- @return string
local function normalise(path)
    local absolute = vim.fn.fnamemodify(path, ":p")
    local stripped = absolute:gsub("([^/\\])[/\\]+$", "%1")
    return stripped
end

--- @param candidate any
--- @param origin string Where the value came from, for the notification
--- @return string|nil cwd nil when rejected
local function validate(candidate, origin)
    if type(candidate) ~= "string" or candidate == "" then
        Logger.notify(
            string.format(
                "Ignoring %s: expected an absolute directory path, got %s",
                origin,
                vim.inspect(candidate)
            ),
            vim.log.levels.WARN
        )
        return nil
    end

    if not is_absolute(candidate) then
        Logger.notify(
            string.format(
                "Ignoring %s: '%s' is not an absolute path",
                origin,
                candidate
            ),
            vim.log.levels.WARN
        )
        return nil
    end

    local cwd = normalise(candidate)
    if vim.fn.isdirectory(cwd) ~= 1 then
        Logger.notify(
            string.format(
                "Ignoring %s: '%s' is not a directory",
                origin,
                candidate
            ),
            vim.log.levels.WARN
        )
        return nil
    end

    return cwd
end

--- Priority: `candidate` (an explicit override or an inherited Session CWD),
--- then `Config.settings.session_cwd` on the acting buffer, then the Neovim cwd.
--- Never fails: a rejected value notifies and falls through.
--- @param candidate string|nil
--- @param bufnr integer The buffer current when the entry point ran
--- @return string cwd
function SessionCwd.resolve(candidate, bufnr)
    if candidate ~= nil then
        local cwd = validate(candidate, "session cwd")
        if cwd then
            return cwd
        end
    end

    local rule = Config.settings and Config.settings.session_cwd
    if type(rule) == "function" then
        --- @type agentic.UserConfig.SessionCwdContext
        local ctx = { bufnr = bufnr }
        local ok, derived = pcall(rule, ctx)
        if not ok then
            Logger.notify(
                "Error in settings.session_cwd: " .. tostring(derived),
                vim.log.levels.WARN
            )
        elseif derived ~= nil then
            local cwd = validate(derived, "settings.session_cwd result")
            if cwd then
                return cwd
            end
        end
    end

    return vim.fn.getcwd()
end

return SessionCwd
