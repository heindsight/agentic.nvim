local Config = require("agentic.config")
local Logger = require("agentic.utils.logger")

--- @class agentic.utils.CwdResolver
local CwdResolver = {}

--- Resolve the working directory for a new session. Returns an absolute,
--- normalized path. Resolution order:
---   1. `Config.cwd(context)`, if a function is configured and returns
---      a non-empty string
---   2. `vim.fn.getcwd()` fallback
--- A thrown error from the configured resolver is logged and falls
--- through to step 2.
--- @param context agentic.CwdResolverContext
--- @return string cwd Absolute, normalized path
function CwdResolver.resolve(context)
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
            return vim.fs.normalize(ret)
        end
    end

    return vim.fs.normalize(vim.fn.getcwd())
end

return CwdResolver
