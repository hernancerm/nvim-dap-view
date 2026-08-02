local mini_test = require("mini.test")

local child = mini_test.new_child_neovim()
local eq = mini_test.expect.equality
local new_set = mini_test.new_set

local OUTPUT = "Hello, World!"

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })

            child.lua_func(function(output)
                local dap = require("dap")

                dap.adapters.mock = {
                    type = "executable",
                    command = vim.v.progpath,
                    args = { "-l", "tests/mock_adapter.lua" },
                }

                -- Tells the adapter the debuggee is over, see `tests/mock_adapter.lua`
                _G.done_file = vim.fn.tempname()

                dap.configurations["*"] = {
                    {
                        type = "mock",
                        request = "launch",
                        name = "mock",
                        done = _G.done_file,
                        -- The mock adapter asks us to run this in an integrated terminal.
                        -- Waiting before writing the output ensures it lands while the session is running,
                        -- like it would for a real debuggee
                        command = {
                            "sh",
                            "-c",
                            ("sleep 0.5; echo %s; touch %s"):format(
                                vim.fn.shellescape(output),
                                vim.fn.shellescape(_G.done_file)
                            ),
                        },
                    },
                }

                require("dap-view").setup({
                    winbar = {
                        default_section = "console",
                        sections = { "console" },
                    },
                })

                ---Run the session and wait for the session, the terminal command and its output to be over
                ---
                ---The terminal command must be over for the next session to be able to reuse its buffer
                _G.run = function()
                    _G.terminated = false

                    vim.fn.delete(_G.done_file)

                    dap.listeners.after.event_terminated["test"] = function()
                        _G.terminated = true
                    end

                    dap.run(dap.configurations["*"][1])

                    local finished = vim.wait(10000, function()
                        if not _G.terminated then
                            return false
                        end

                        local bufnr = _G.console_buf()
                        local job = vim.b[bufnr].terminal_job_id
                        local running = job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1

                        return not running
                            and vim.iter(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)):any(function(line)
                                return line == output
                            end)
                    end, 10)

                    -- Autoscrolling is scheduled, give it a chance to run
                    vim.wait(100)

                    return finished
                end

                _G.console_buf = function()
                    return vim.api.nvim_win_get_buf(require("dap-view.state").winnr)
                end

                ---Lines the console window is actually displaying
                _G.visible_lines = function()
                    local winnr = require("dap-view.state").winnr

                    return vim.api.nvim_buf_get_lines(
                        vim.api.nvim_win_get_buf(winnr),
                        vim.fn.line("w0", winnr) - 1,
                        vim.fn.line("w$", winnr),
                        false
                    )
                end
            end, OUTPUT)

            child.lua_func(function()
                require("dap-view").open()
            end)
        end,
        post_once = function()
            child.stop()
        end,
    },
})

T["console"] = new_set()

T["console"]["shows the output of a session"] = function()
    eq(child.lua_get("_G.run()"), true)

    eq(vim.tbl_contains(child.lua_get("_G.visible_lines()"), OUTPUT), true)
end

-- Terminal buffers are reused across sessions, and the reused buffer may span more lines than the
-- console window can display, which used to leave the window showing only its trailing empty lines
T["console"]["shows the output of a session that reuses a terminal"] = function()
    eq(child.lua_get("_G.run()"), true)
    eq(child.lua_get("_G.run()"), true)

    eq(vim.tbl_contains(child.lua_get("_G.visible_lines()"), OUTPUT), true)
end

return T
