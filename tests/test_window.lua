local mini_test = require("mini.test")

local child = mini_test.new_child_neovim()
local eq = mini_test.expect.equality
local new_set = mini_test.new_set

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })

            child.lua_func(function()
                -- Default `windows.position`, so the window is a horizontal split below the editor
                require("dap-view").setup({})

                ---Any window coming and going triggers a resize, which is what a session does
                ---indirectly: nvim-dap opens a window for the terminal (`belowright new`) and it's
                ---closed right after
                _G.window_churn = function()
                    vim.cmd("split")
                    vim.cmd("close")

                    -- The resize is scheduled
                    vim.wait(100)
                end

                _G.layout = function()
                    local winnr = require("dap-view.state").winnr

                    return {
                        height = vim.api.nvim_win_get_height(winnr),
                        width = vim.api.nvim_win_get_width(winnr),
                        cmdheight = vim.o.cmdheight,
                    }
                end
            end)

            child.lua_func(function()
                require("dap-view").open()
            end)
        end,
        post_once = function()
            child.stop()
        end,
    },
})

T["window"] = new_set()

T["window"]["restores its size when unrelated windows come and go"] = function()
    local before = child.lua_get("_G.layout()")

    child.lua_func(function()
        vim.api.nvim_win_set_height(require("dap-view.state").winnr, 10)
    end)

    eq(child.lua_get("_G.layout()").height, 10)

    child.lua("_G.window_churn()")

    eq(child.lua_get("_G.layout()"), before)
end

-- Restoring a height the window can't give up shrinks every window and dumps the leftover rows into
-- 'cmdheight', leaving a gap under the statusline
T["window"]["keeps its size after being moved to a full height split"] = function()
    child.lua_func(function()
        vim.api.nvim_set_current_win(require("dap-view.state").winnr)
    end)
    child.type_keys("<C-w>H")

    local before = child.lua_get("_G.layout()")

    -- The window now spans the whole editor, so there's nothing above or below to take rows from
    eq(before.cmdheight, 1)

    child.lua("_G.window_churn()")

    eq(child.lua_get("_G.layout()"), before)
end

return T
