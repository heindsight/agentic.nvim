local Config = require("agentic.config")
-- Logger is required lazily inside `resolve` so other tests that clear
-- package.loaded["agentic.utils.logger"] do not leave this module bound
-- to a stale Logger table.

--- @class agentic.utils.CwdResolver
local CwdResolver = {}

--- Resolve the working directory for a new session. Returns an absolute,
--- normalized path. Resolution order:
---   1. `Config.cwd(context)`, if a function is configured and returns a
---      string that is non-empty after trimming whitespace
---   2. `vim.fn.getcwd()` fallback (respects window-local `:lcd`,
---      tab-local `:tcd`, then global cwd)
--- A thrown error from the configured resolver is logged and falls
--- through to step 2. Whitespace-only output is also logged before
--- falling through.
--- @param context agentic.CwdResolverContext
--- @return string cwd Absolute, normalized path
function CwdResolver.resolve(context)
    local Logger = require("agentic.utils.logger")
    local opt = Config.cwd

    if type(opt) == "function" then
        local ok, ret = pcall(opt, context)
        if not ok then
            Logger.notify(
                "[agentic] cwd resolver threw: "
                    .. tostring(ret)
                    .. ". Falling back to vim.fn.getcwd().",
                vim.log.levels.WARN
            )
        elseif type(ret) == "string" and ret ~= "" then
            if vim.trim(ret) ~= "" then
                -- `:p` first so `~user/...` (which only `fnamemodify`
                -- expands) is resolved before `vim.fs.normalize` unifies
                -- separators.
                return vim.fs.normalize(vim.fn.fnamemodify(ret, ":p"))
            else
                Logger.notify(
                    "[agentic] cwd resolver returned whitespace-only "
                        .. "string; falling back to vim.fn.getcwd().",
                    vim.log.levels.WARN
                )
            end
        end
    end

    return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(), ":p"))
end

return CwdResolver
