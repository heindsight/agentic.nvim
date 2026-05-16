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

    local function expected_fallback()
        return vim.fs.normalize(vim.fn.fnamemodify(original_cwd, ":p"))
    end

    local CONTEXT = { tab_page_id = 1, bufnr = 1 }

    before_each(function()
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

        assert.equal(expected_fallback(), result)
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

    it("expands tilde-home in resolver output", function()
        Config.cwd = function()
            return "~/code"
        end

        local result = CwdResolver.resolve(CONTEXT)

        local expected = vim.fs.normalize(vim.fn.fnamemodify("~/code", ":p"))
        assert.equal(expected, result)
    end)

    it("absolutizes a relative path in resolver output", function()
        Config.cwd = function()
            return "./subdir"
        end

        local result = CwdResolver.resolve(CONTEXT)

        local expected = vim.fs.normalize(vim.fn.fnamemodify("./subdir", ":p"))
        assert.equal(expected, result)
    end)

    it("strips trailing slash in resolver output", function()
        Config.cwd = function()
            return "/tmp/foo/"
        end

        local result = CwdResolver.resolve(CONTEXT)

        assert.equal("/tmp/foo", result)
    end)

    it("falls back to getcwd() when resolver function returns nil", function()
        Config.cwd = function()
            return nil
        end

        local result = CwdResolver.resolve(CONTEXT)

        assert.equal(expected_fallback(), result)
    end)

    it(
        "falls back to getcwd() when resolver function returns empty string",
        function()
            Config.cwd = function()
                return ""
            end

            local result = CwdResolver.resolve(CONTEXT)

            assert.equal(expected_fallback(), result)
            assert.spy(logger_notify_stub).was.called(0)
        end
    )

    it(
        "falls back to getcwd() and warns when resolver function throws",
        function()
            Config.cwd = function()
                error("boom")
            end

            local result = CwdResolver.resolve(CONTEXT)

            assert.equal(expected_fallback(), result)
            assert.spy(logger_notify_stub).was.called(1)
            assert.equal(vim.log.levels.WARN, logger_notify_stub.calls[1][2])
        end
    )

    it(
        "falls back to getcwd() and warns when resolver returns whitespace-only string",
        function()
            Config.cwd = function()
                return "   \t  "
            end

            local result = CwdResolver.resolve(CONTEXT)

            assert.equal(
                vim.fs.normalize(vim.fn.fnamemodify(original_cwd, ":p")),
                result
            )
            assert.spy(logger_notify_stub).was.called(1)
            assert.equal(vim.log.levels.WARN, logger_notify_stub.calls[1][2])
        end
    )
end)
