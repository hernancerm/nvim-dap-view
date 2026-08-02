local M = {}

local api = vim.api

---@param tabpage integer
---@param term? boolean
local fetch_win_from_tab = function(tabpage, term)
    for _, win in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
        if vim.w[win][term and "dapview_win_term" or "dapview_win"] then
            return win
        end
    end
end

---Look for the window in a 'winlayout' tree, reporting whether any of its ancestors splits along
---`split`, which is what makes room for a resize
---@param node table A node from `vim.fn.winlayout`
---@param winnr integer
---@param split "col"|"row"
---@return boolean found, boolean has_sibling
local function search_layout(node, winnr, split)
    local kind, contents = node[1], node[2]

    if kind == "leaf" then
        return contents == winnr, false
    end

    for _, child in ipairs(contents) do
        local found, has_sibling = search_layout(child, winnr, split)

        if found then
            return true, has_sibling or (kind == split and #contents > 1)
        end
    end

    return false, false
end

---Whether the window can be resized at the expense of another window
---
---Resizing a window that spans the whole editor doesn't take space from any other window: Neovim
---takes it from the command line instead (see `frame_setheight`), which shrinks every window and
---leaves a gap under the statusline. Only windows that have a sibling to take the space from can
---be resized in the first place
---@param winnr integer
---@param dimension "height"|"width"
---@return boolean
M.can_resize = function(winnr, dimension)
    -- Stacked windows give up rows, side by side ones give up columns
    local split = dimension == "height" and "col" or "row"

    local tabnr = vim.fn.win_id2tabwin(winnr)[1]

    if tabnr == 0 then
        return false
    end

    local found, has_sibling = search_layout(vim.fn.winlayout(tabnr), winnr, split)

    return found and has_sibling
end

---@param opts? {current_tab?: boolean, term?: boolean}
---@return integer?
M.fetch_window = function(opts)
    if opts and opts.current_tab then
        return fetch_win_from_tab(0, opts.term)
    end
    for _, tabpage in ipairs(api.nvim_list_tabpages()) do
        local win = fetch_win_from_tab(tabpage, opts and opts.term)
        if win then
            return win
        end
    end
end

return M
