---@brief [[
--- Fyler.nvim is a file manager which can edit file system like a buffer.
---
--- How it different from |oil.nvim|?
--- - It provides tree view
---@brief ]]

---@tag fyler.nvim
---@config { ["name"] = "INTRODUCTION" }

local RenderNode = require 'fyler.lib.rendernode'
local Window = require 'fyler.lib.window'
local algos = require 'fyler.algos'
local config = require 'fyler.config'
local state = require 'fyler.state'
local utils = require 'fyler.utils'
local luv = vim.uv or vim.loop

local M = {}

function M.hide()
    utils.hide_window(state.window.main)
end

-- Helper function to get the current file path
local function get_current_file_path()
    local current_bufnr = vim.api.nvim_get_current_buf()
    local current_file = vim.api.nvim_buf_get_name(current_bufnr)

    -- Only return if it's a real file (not empty, not a special buffer)
    if current_file ~= '' and vim.fn.filereadable(current_file) == 1 then
        return vim.fn.fnamemodify(current_file, ':p') -- Get absolute path
    end

    return nil
end

-- Helper function to find and highlight the current file
local function highlight_current_file(render_node, window, current_file_path)
    if not current_file_path then
        return
    end

    -- Use the reveal_file_path method to reveal all parent directories
    render_node:reveal_file_path(current_file_path)

    -- Re-render the tree with expanded directories
    render_node:get_equivalent_text():remove_trailing_empty_lines():render(window.bufnr)

    -- Find the line number for the current file
    local lines = vim.api.nvim_buf_get_lines(window.bufnr, 0, -1, false)
    local target_line = nil

    for i, line in ipairs(lines) do
        -- Extract the file path from the line and compare
        local meta_key = algos.extract_meta_key(line)
        if meta_key and state.meta_data[meta_key] then
            local metadata = state.meta_data[meta_key]
            if metadata.path == current_file_path then
                target_line = i
                break
            end
        end
    end

    -- Move cursor to the found line
    if target_line then
        vim.api.nvim_win_set_cursor(window.winid, { target_line, 0 })
    end
end

function M.show()
    -- Check if already open
    if state.window.main then
        utils.hide_window(state.window.main)
    end

    -- Get current file before switching windows
    local current_file_path = get_current_file_path()
    -- Check if existing render_node otherwise create new
    local cwd = luv.cwd() or vim.fn.getcwd(0)
    local render_node = vim.tbl_isempty(state.render_node[cwd])
        and RenderNode.new {
            name = vim.fn.fnamemodify(luv.cwd() or '', ':t'),
            path = cwd,
            type = 'directory',
            revealed = true,
        }
        or state.render_node[cwd]

    local window = Window.new {
        enter = true,
        width = config.values.window_config.width,
        split = config.values.window_config.split,
    }

    -- Sync states
    state.window.main = window
    state.window_id.user = vim.api.nvim_get_current_win()
    state.render_node[render_node.path] = render_node
    utils.show_window(window)

    -- Setup options
    utils.set_buf_option(window, 'filetype', 'fyler-main')
    utils.set_buf_option(window, 'syntax', 'fyler')
    utils.set_win_option(window, 'number', config.values.window_options.number)
    utils.set_win_option(window, 'relativenumber', config.values.window_options.relativenumber)
    utils.set_win_option(window, 'cursorline', true)
    utils.set_win_option(window, 'conceallevel', 3)
    utils.set_win_option(window, 'concealcursor', 'nvic')
    utils.create_autocmd('WinClosed', {
        buffer = window.bufnr,
        callback = function()
            -- Switch to the user's original window before hiding
            if state.window_id.user and vim.api.nvim_win_is_valid(state.window_id.user) then
                vim.api.nvim_set_current_win(state.window_id.user)
            end

            utils.hide_window(window)
        end,
    })

    -- Constrain cursor position
    utils.create_autocmd('CursorMoved', {
        buffer = window.bufnr,
        callback = function()
            local current_line = vim.api.nvim_get_current_line()
            local meta_key = algos.extract_meta_key(current_line)
            if not meta_key then
                return
            end

            local node = render_node:find(state.meta_data[meta_key].path)
            if not node then
                return
            end

            local current_row, current_col = unpack(vim.api.nvim_win_get_cursor(0))
            local bound, _ = current_line:find '%s+/%d+'
            if bound and current_col >= bound - 1 then
                vim.api.nvim_win_set_cursor(0, { current_row, bound - 1 })
            end

            state.cursor = { current_row, current_col }
        end,
    })

    -- Apply mappings
    for mode, mappings in pairs(require('fyler.mappings').default_mappings.main or {}) do
        for k, v in pairs(mappings) do
            utils.set_keymap {
                mode = mode,
                lhs = k,
                rhs = v,
                options = {
                    buffer = window.bufnr,
                },
            }
        end
    end

    render_node:get_equivalent_text():remove_trailing_empty_lines():render(window.bufnr)

    if not vim.tbl_isempty(state.cursor) then
        vim.api.nvim_win_set_cursor(window.winid, state.cursor)
    end

    highlight_current_file(render_node, window, current_file_path)
end

function M.setup(options)
    config.set_defaults(options)
end

vim.api.nvim_create_user_command('Fyler', M.show, { nargs = 0 })

return M
