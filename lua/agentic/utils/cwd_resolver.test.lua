local assert = require("tests.helpers.assert")
local spy = require("tests.helpers.spy")

describe("CwdResolver.resolve", function()
    --- @type agentic.utils.CwdResolver
    local CwdResolver
    local Config
    local Logger

    --- @type TestStub
    local logger_notify_stub

    --- @type string
    local original_cwd

    --- @type agentic.UserConfig.CwdResolver|nil
    local original_config_cwd

    local CONTEXT = { tab_page_id = 1, bufnr = 1 }

    before_each(function()
        -- Other tests in the suite (e.g. session_restore.test.lua) clear
        -- package.loaded["agentic.utils.logger"], leaving CwdResolver
        -- bound to a stale Logger table. Reload CwdResolver so its
        -- internal Logger reference matches the current module.
        package.loaded["agentic.utils.cwd_resolver"] = nil

        CwdResolver = require("agentic.utils.cwd_resolver")
        Config = require("agentic.config")
        Logger = require("agentic.utils.logger")

        logger_notify_stub = spy.stub(Logger, "notify")

        original_config_cwd = Config.cwd
        original_cwd = vim.fn.getcwd()
    end)

    after_each(function()
        logger_notify_stub:revert()
        Config.cwd = original_config_cwd
        vim.fn.chdir(original_cwd)
    end)

    it("falls back to vim.fn.getcwd() when Config.cwd is nil", function()
        Config.cwd = nil

        local result = CwdResolver.resolve(CONTEXT)

        assert.equal(original_cwd, result)
    end)

    it("invokes the resolver function with the given context", function()
        --- @type agentic.CwdResolverContext|nil
        local received_ctx = nil
        Config.cwd = function(ctx)
            received_ctx = ctx
            return "/tmp"
        end

        CwdResolver.resolve(CONTEXT)

        assert.is_not_nil(received_ctx)
        --- @cast received_ctx agentic.CwdResolverContext
        assert.equal(CONTEXT.tab_page_id, received_ctx.tab_page_id)
        assert.equal(CONTEXT.bufnr, received_ctx.bufnr)
    end)

    it(
        "returns expanded path when resolver function returns a string",
        function()
            Config.cwd = function()
                return "/tmp"
            end

            local result = CwdResolver.resolve(CONTEXT)

            assert.equal("/tmp", result)
        end
    )

    it("falls back to getcwd() when resolver function returns nil", function()
        Config.cwd = function()
            return nil
        end

        local result = CwdResolver.resolve(CONTEXT)

        assert.equal(original_cwd, result)
    end)

    it(
        "falls back to getcwd() when resolver function returns empty string",
        function()
            Config.cwd = function()
                return ""
            end

            local result = CwdResolver.resolve(CONTEXT)

            assert.equal(original_cwd, result)
        end
    )

    it(
        "falls back to getcwd() and warns when resolver function throws",
        function()
            Config.cwd = function()
                error("boom")
            end

            local result = CwdResolver.resolve(CONTEXT)

            assert.equal(original_cwd, result)
            assert.spy(logger_notify_stub).was.called(1)
            assert.equal(vim.log.levels.WARN, logger_notify_stub.calls[1][2])
        end
    )
end)
