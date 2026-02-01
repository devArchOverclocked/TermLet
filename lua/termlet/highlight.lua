-- Visual highlighting module for stack trace file paths
-- Provides configurable highlighting of detected file paths in terminal buffers
-- lua/termlet/highlight.lua

local M = {}

-- Default configuration
local config = {
  enabled = true,
  style = "underline", -- "underline", "color", "both", "none"
  hl_group = "TermLetStackTracePath",
}

-- Namespace for extmarks
local ns_id = nil

-- Initialize the module
local function init()
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("termlet_stacktrace")
  end

  -- Define default highlight group based on background
  local bg = vim.o.background
  local default_hl = {
    underline = true,
  }

  if bg == "dark" then
    default_hl.fg = "#61afef" -- Light blue for dark themes
  else
    default_hl.fg = "#0066cc" -- Darker blue for light themes
  end

  -- Set the default highlight group if it doesn't exist
  vim.api.nvim_set_hl(0, config.hl_group, default_hl)
end

-- Setup function to configure the highlight module
-- @param user_config table User configuration
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  init()
end

-- Apply highlighting to a file path in a buffer
-- @param bufnr number The buffer number
-- @param line_num number The line number (1-indexed)
-- @param start_col number The starting column (0-indexed)
-- @param end_col number The ending column (0-indexed, exclusive)
function M.highlight_file_path(bufnr, line_num, start_col, end_col)
  if not config.enabled or config.style == "none" then
    return
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not ns_id then
    init()
  end

  -- Create a dynamic highlight group based on the current style
  -- This allows us to change styling without modifying the base highlight group
  local hl_name = config.hl_group
  if config.style == "underline" then
    hl_name = config.hl_group .. "Underline"
    vim.api.nvim_set_hl(0, hl_name, { underline = true })
  elseif config.style == "color" then
    hl_name = config.hl_group
    -- Use the base highlight group which has color
  elseif config.style == "both" then
    hl_name = config.hl_group .. "Both"
    local bg = vim.o.background
    local hl_opts = { underline = true }
    if bg == "dark" then
      hl_opts.fg = "#61afef"
    else
      hl_opts.fg = "#0066cc"
    end
    vim.api.nvim_set_hl(0, hl_name, hl_opts)
  end

  -- Build extmark options
  local extmark_opts = {
    end_col = end_col,
    hl_group = hl_name,
  }

  -- Set the extmark (0-indexed line number for the API)
  local ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line_num - 1, start_col, extmark_opts)
  if not ok then
    -- Silently ignore errors (e.g., buffer was deleted)
    return
  end
end

-- Highlight a detected file reference in a buffer line
-- @param bufnr number The buffer number
-- @param line_num number The line number (1-indexed)
-- @param line_text string The full line text
-- @param file_info table File information with path, line, column
-- @return boolean Success status
function M.highlight_stacktrace_line(bufnr, line_num, line_text, file_info)
  if not config.enabled or config.style == "none" then
    return false
  end

  if not file_info or not file_info.original_path then
    return false
  end

  -- Find the file path in the line text
  -- Use original_path (not resolved path) since that's what appears in the output
  local path_to_find = file_info.original_path

  -- Try to find the path in the line
  local start_pos, end_pos = line_text:find(path_to_find, 1, true)

  if not start_pos then
    return false
  end

  -- Convert to 0-indexed columns for extmark API
  local start_col = start_pos - 1
  local end_col = end_pos

  M.highlight_file_path(bufnr, line_num, start_col, end_col)
  return true
end

-- Clear all highlights from a buffer
-- @param bufnr number The buffer number
function M.clear_buffer(bufnr)
  if not ns_id then
    return
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

-- Clear all highlights from all buffers
function M.clear_all()
  if not ns_id then
    return
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end
  end
end

-- Check if highlighting is enabled
-- @return boolean
function M.is_enabled()
  return config.enabled
end

-- Enable highlighting
function M.enable()
  config.enabled = true
end

-- Disable highlighting
function M.disable()
  config.enabled = false
end

-- Get current configuration
-- @return table Configuration copy
function M.get_config()
  return vim.deepcopy(config)
end

-- Get namespace ID
-- @return number Namespace ID
function M.get_namespace()
  if not ns_id then
    init()
  end
  return ns_id
end

return M
