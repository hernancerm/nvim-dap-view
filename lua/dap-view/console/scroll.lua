local setup = require("dap-view.setup")
local util = require("dap-view.util")
local state = require("dap-view.state")

local M = {}

local api = vim.api
local go = vim.go

---@type table<integer,boolean>
local termbuf_is_autoscrolling = {}

---@type table<integer,boolean>
local termbuf_is_attached = {}

-- Inspired by nvim-dap-ui
-- https://github.com/rcarriga/nvim-dap-ui/blob/73a26abf4941aa27da59820fd6b028ebcdbcf932/lua/dapui/elements/console.lua#L23-L46

---Last line of a terminal buffer that holds output
---
---A terminal buffer always spans the whole terminal grid, which may be taller than the window
---displaying it. That happens when a session reuses the terminal buffer from a previous session
---(nvim-dap keeps a pool of them): the buffer is already in the window, so nothing makes Neovim
---resize the grid to fit it, and nvim-dap falls back to sizing the grid as half of 'lines'.
---In that case the trailing (blank) rows of the grid take over the whole window, hiding the output
---@param bufnr integer
---@return integer
local function last_output_line(bufnr)
    local line_count = api.nvim_buf_line_count(bufnr)

    -- Only the grid can be padded with blank rows, and it's never taller than the editor itself,
    -- so there's no need to look further back than that (buffers get long, this runs on every write)
    local from = math.max(line_count - go.lines, 0)

    local lines = api.nvim_buf_get_lines(bufnr, from, line_count, false)

    for i = #lines, 1, -1 do
        -- Rows that only hold spaces look just as empty, and they do show up in terminals
        -- (that's how a program erases what it previously wrote)
        if lines[i]:find("%S") then
            return from + i
        end
    end

    return math.max(from, 1)
end

---@param bufnr integer
M.setup_autoscroll = function(bufnr)
    termbuf_is_autoscrolling[bufnr] = true

    api.nvim_create_autocmd({ "InsertEnter", "CursorMoved" }, {
        buffer = bufnr,
        group = api.nvim_create_augroup("nvim-dap-view-scroll-" .. bufnr, {}),
        callback = function()
            local winnr = vim.tbl_contains(setup.config.winbar.sections, "console") and state.winnr or state.term_winnr

            if not util.is_win_valid(winnr) then
                return
            end

            ---@cast winnr integer
            local cursor = api.nvim_win_get_cursor(winnr)

            -- Anywhere past the output counts as being at the bottom, since the rows below it are empty
            termbuf_is_autoscrolling[bufnr] = cursor[1] >= last_output_line(bufnr)
        end,
    })

    -- Terminal buffers are reused across sessions, but the callbacks aren't detached,
    -- so attaching once is enough
    if termbuf_is_attached[bufnr] then
        return
    end

    termbuf_is_attached[bufnr] = true

    api.nvim_buf_attach(bufnr, false, {
        on_detach = function()
            termbuf_is_attached[bufnr] = nil
        end,
        on_lines = function()
            local winnr = vim.tbl_contains(setup.config.winbar.sections, "console") and state.winnr or state.term_winnr

            if not util.is_win_valid(winnr) then
                return
            end

            ---@cast winnr integer
            if M.is_autoscrolling(bufnr) and vim.fn.mode() == "n" then
                api.nvim_win_call(winnr, function()
                    if api.nvim_get_current_buf() == bufnr then
                        -- Ensure the cursor movement happens in the main event loop
                        -- Otherwise the call may happen too early
                        M.scroll_to_bottom(winnr, bufnr)
                    end
                end)
            end
        end,
    })
end

---@param bufnr integer
---@return boolean?
M.is_autoscrolling = function(bufnr)
    return termbuf_is_autoscrolling[bufnr]
end

---@param winnr integer
---@param bufnr integer
M.scroll_to_bottom = function(winnr, bufnr)
    vim.schedule(function()
        if util.is_win_valid(winnr) and util.is_buf_valid(bufnr) then
            api.nvim_win_set_cursor(winnr, { last_output_line(bufnr), 0 })

            termbuf_is_autoscrolling[bufnr] = true
        end
    end)
end

---@param bufnr integer
M.cleanup_autoscroll = function(bufnr)
    if termbuf_is_autoscrolling[bufnr] then
        api.nvim_del_augroup_by_name("nvim-dap-view-scroll-" .. bufnr)

        termbuf_is_autoscrolling[bufnr] = nil
    end
end

return M
