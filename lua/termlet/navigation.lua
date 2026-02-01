-- Stack trace navigation module
-- Provides keyboard shortcuts for navigating between detected stack trace file references

local M = {}

-- Default configuration
local config = {
  enabled = true,
  keymaps = {
    next_error = ']e',
    prev_error = '[e',
    open_file = { 'gf', '<CR>' },
    list_errors = '<leader>se',
  },
  open_command = 'split', -- 'split', 'vsplit', 'edit', 'tabedit'
  highlight_duration = 200, -- ms to highlight jumped-to location
  wrap_navigation = true, -- wrap around at boundaries
}

-- Highlight namespace for visual feedback
local ns_id = vim.api.nvim_create_namespace('termlet_navigation')

-- Get all stack trace locations in a buffer, sorted by line number
---@param bufnr number Buffer ID
---@return table[] Array of {line, path, line_num, column, context} sorted by line number
local function get_sorted_locations(bufnr)
  local stacktrace = require('termlet.stacktrace')
  local metadata = stacktrace.get_buffer_metadata(bufnr)

  if not metadata then
    return {}
  end

  local locations = {}
  for line_num, file_info in pairs(metadata) do
    table.insert(locations, {
      line = line_num,
      path = file_info.path,
      line_num = file_info.line,
      column = file_info.column,
      context = file_info.context,
    })
  end

  -- Sort by line number
  table.sort(locations, function(a, b)
    return a.line < b.line
  end)

  return locations
end

-- Find the index of the next location after the cursor
---@param locations table[] Sorted array of locations
---@param cursor_line number Current cursor line
---@return number|nil Index of next location, or nil if none
local function find_next_location_index(locations, cursor_line)
  for i, loc in ipairs(locations) do
    if loc.line > cursor_line then
      return i
    end
  end
  return nil
end

-- Find the index of the previous location before the cursor
---@param locations table[] Sorted array of locations
---@param cursor_line number Current cursor line
---@return number|nil Index of previous location, or nil if none
local function find_prev_location_index(locations, cursor_line)
  for i = #locations, 1, -1 do
    if locations[i].line < cursor_line then
      return i
    end
  end
  return nil
end

-- Highlight a line briefly for visual feedback
---@param bufnr number Buffer ID
---@param line_num number Line number (1-indexed)
local function highlight_line(bufnr, line_num)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear any existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Add highlight (line numbers are 0-indexed for the API)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'Visual', line_num - 1, 0, -1)

  -- Remove highlight after duration
  if config.highlight_duration > 0 then
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      end
    end, config.highlight_duration)
  end
end

-- Jump to the next stack trace location
---@param bufnr number Buffer ID
function M.jump_to_next(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local locations = get_sorted_locations(bufnr)
  if #locations == 0 then
    vim.notify('No stack trace locations found in buffer', vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  local next_idx = find_next_location_index(locations, cursor_line)

  -- Wrap around if at the end
  if not next_idx and config.wrap_navigation then
    next_idx = 1
  end

  if next_idx then
    local loc = locations[next_idx]
    -- Ensure the buffer has enough lines before setting cursor
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if loc.line <= line_count then
      vim.api.nvim_win_set_cursor(0, {loc.line, 0})
      highlight_line(bufnr, loc.line)

      -- Show count in status
      vim.notify(string.format('Error %d/%d', next_idx, #locations), vim.log.levels.INFO)
    else
      vim.notify('Stack trace location is beyond buffer end', vim.log.levels.WARN)
    end
  else
    vim.notify('No more stack trace locations below cursor', vim.log.levels.INFO)
  end
end

-- Jump to the previous stack trace location
---@param bufnr number Buffer ID
function M.jump_to_prev(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local locations = get_sorted_locations(bufnr)
  if #locations == 0 then
    vim.notify('No stack trace locations found in buffer', vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  local prev_idx = find_prev_location_index(locations, cursor_line)

  -- Wrap around if at the beginning
  if not prev_idx and config.wrap_navigation then
    prev_idx = #locations
  end

  if prev_idx then
    local loc = locations[prev_idx]
    -- Ensure the buffer has enough lines before setting cursor
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if loc.line <= line_count then
      vim.api.nvim_win_set_cursor(0, {loc.line, 0})
      highlight_line(bufnr, loc.line)

      -- Show count in status
      vim.notify(string.format('Error %d/%d', prev_idx, #locations), vim.log.levels.INFO)
    else
      vim.notify('Stack trace location is beyond buffer end', vim.log.levels.WARN)
    end
  else
    vim.notify('No more stack trace locations above cursor', vim.log.levels.INFO)
  end
end

-- Open the file at the cursor location
---@param bufnr number Buffer ID
function M.open_file_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Use the existing goto_stacktrace function from termlet
  local termlet = require('termlet')
  return termlet.goto_stacktrace()
end

-- List all stack trace locations in a quickfix or location list
---@param bufnr number Buffer ID
---@param use_loclist boolean|nil Use location list instead of quickfix (default: true)
function M.list_all_locations(bufnr, use_loclist)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  use_loclist = use_loclist ~= false -- default to true

  local locations = get_sorted_locations(bufnr)
  if #locations == 0 then
    vim.notify('No stack trace locations found in buffer', vim.log.levels.INFO)
    return
  end

  -- Build quickfix/loclist entries
  local qf_list = {}
  for _, loc in ipairs(locations) do
    table.insert(qf_list, {
      filename = loc.path,
      lnum = loc.line_num or 0,
      col = loc.column or 0,
      text = loc.context or 'Stack trace entry',
    })
  end

  if use_loclist then
    vim.fn.setloclist(0, qf_list)
    vim.cmd('lopen')
  else
    vim.fn.setqflist(qf_list)
    vim.cmd('copen')
  end

  vim.notify(string.format('Found %d stack trace location(s)', #locations), vim.log.levels.INFO)
end

-- Setup keymaps for a terminal buffer
---@param bufnr number Terminal buffer ID
function M.setup_buffer_keymaps(bufnr)
  if not config.enabled then
    return
  end

  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- Next/Previous error navigation
  vim.keymap.set('n', config.keymaps.next_error, function()
    M.jump_to_next(bufnr)
  end, vim.tbl_extend('force', opts, { desc = 'Jump to next stack trace location' }))

  vim.keymap.set('n', config.keymaps.prev_error, function()
    M.jump_to_prev(bufnr)
  end, vim.tbl_extend('force', opts, { desc = 'Jump to previous stack trace location' }))

  -- Open file keymaps (can be multiple)
  local open_keys = config.keymaps.open_file
  if type(open_keys) == 'string' then
    open_keys = { open_keys }
  end

  for _, key in ipairs(open_keys) do
    vim.keymap.set('n', key, function()
      M.open_file_at_cursor(bufnr)
    end, vim.tbl_extend('force', opts, { desc = 'Open file from stack trace' }))
  end

  -- List all errors
  vim.keymap.set('n', config.keymaps.list_errors, function()
    M.list_all_locations(bufnr)
  end, vim.tbl_extend('force', opts, { desc = 'List all stack trace locations' }))
end

-- Configure the navigation module
---@param user_config table|nil User configuration to merge
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend('force', config, user_config)
  end
  return config
end

-- Get current configuration
---@return table Current configuration
function M.get_config()
  return vim.deepcopy(config)
end

-- Enable navigation
function M.enable()
  config.enabled = true
end

-- Disable navigation
function M.disable()
  config.enabled = false
end

-- Check if navigation is enabled
---@return boolean
function M.is_enabled()
  return config.enabled
end

return M
