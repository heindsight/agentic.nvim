local assert = require("tests.helpers.assert")
local spy = require("tests.helpers.spy")

local EnvironmentInfo = require("agentic.utils.environment_info")

describe("agentic.utils.EnvironmentInfo", function()
    describe("get_system_info", function()
        --- @type TestStub
        local system_stub
        --- @type TestStub
        local fs_root_stub

        before_each(function()
            system_stub = spy.stub(vim, "system")
            system_stub:invokes(function()
                return {
                    wait = function()
                        return { code = 1, stdout = "", stderr = "" }
                    end,
                }
            end)
            fs_root_stub = spy.stub(vim.fs, "root")
            fs_root_stub:returns("/fake/repo")
        end)

        after_each(function()
            system_stub:revert()
            fs_root_stub:revert()
        end)

        it("uses the given cwd for git commands", function()
            EnvironmentInfo.get_system_info("/fake/repo")

            assert.is_true(system_stub.call_count >= 1)
            for i = 1, system_stub.call_count do
                local call = system_stub.calls[i]
                local opts = call[2]
                assert.equal("/fake/repo", opts.cwd)
            end
        end)

        it("does not throw when vim.system raises a spawn error", function()
            system_stub:invokes(function()
                error("ENOENT: no such file or directory")
            end)

            local info
            assert.has_no_errors(function()
                info = EnvironmentInfo.get_system_info("/fake/repo")
            end)

            assert.truthy(info:match("environment_info"))
            assert.truthy(info:match("Git repository"))
            assert.truthy(info:match("Project root"))
        end)

        it("includes Project root from the given cwd in output", function()
            fs_root_stub:returns(nil)

            local info = EnvironmentInfo.get_system_info("/some/project/root")

            assert.truthy(info:match("Project root: /some/project/root"))
        end)
    end)
end)
