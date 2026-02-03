-- Output filtering and highlighting module
-- Provides non-destructive filtering and custom highlighting for terminal output
-- lua/termlet/filter.lua

local M = {}

-- Default configuration
local config = {
  enabled = false,
  show_only = {}, -- Only show lines matching these patterns
  hide = {}, -- Hide lines matching these patterns
  highlight = {}, -- Custom highlighting rules
}

-- Namespace for extmarks
local ns_id = nil

-- Cache of original unfiltered lines per buffer
-- Stores the full original content so it can be restored when filters are toggled off
local original_lines_cache = {}

-- Initialize the module
local function init()
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("termlet_filter")
  end
end

-- Setup function to configure the filter module
-- @param user_config table User configuration
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end
  init()
end

-- Check if a line should be shown based on filters
-- @param line string The line text
-- @param filters table Filter configuration
-- @return boolean True if line should be shown
local function should_show_line(line, filters)
  if not filters or not filters.enabled then
    return true
  end

  -- If show_only is configured, line must match at least one pattern
  if filters.show_only and #filters.show_only > 0 then
    local matched = false
    for _, pattern in ipairs(filters.show_only) do
      if line:lower():find(pattern:lower(), 1, true) then
        matched = true
        break
      end
    end
    if not matched then
      return false
    end
  end

  -- If hide is configured, line must not match any pattern
  if filters.hide and #filters.hide > 0 then
    for _, pattern in ipairs(filters.hide) do
      if line:lower():find(pattern:lower(), 1, true) then
        return false
      end
    end
  end

  return true
end

-- Find all highlight matches in a line
-- @param line string The line text
-- @param highlight_rules table Highlight configuration
-- @return table List of {start, end, color, pattern} matches
local function find_highlights(line, highlight_rules)
  if not highlight_rules or #highlight_rules == 0 then
    return {}
  end

  local matches = {}
  for _, rule in ipairs(highlight_rules) do
    local pattern = rule.pattern
    local search_start = 1

    while search_start <= #line do
      local start_pos, end_pos = line:lower():find(pattern:lower(), search_start, true)
      if not start_pos then
        break
      end

      table.insert(matches, {
        start = start_pos - 1, -- 0-indexed for extmarks
        ["end"] = end_pos, -- exclusive end for extmarks
        color = rule.color,
        pattern = pattern,
      })

      search_start = end_pos + 1
    end
  end

  return matches
end

-- Apply highlighting to a line in a buffer
-- @param bufnr number The buffer number
-- @param line_num number The line number (1-indexed)
-- @param line_text string The line text
-- @param highlight_rules table Highlight configuration
function M.highlight_line(bufnr, line_num, line_text, highlight_rules)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not ns_id then
    init()
  end

  local matches = find_highlights(line_text, highlight_rules)

  for _, match in ipairs(matches) do
    -- Create a unique highlight group for this color
    local hl_name = "TermLetFilter_" .. match.color:gsub("#", "")

    -- Define the highlight group if it doesn't exist
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_name })
    if not ok or vim.tbl_isempty(hl) then
      vim.api.nvim_set_hl(0, hl_name, { fg = match.color })
    end

    -- Set the extmark
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line_num - 1, match.start, {
      end_col = match["end"],
      hl_group = hl_name,
    })
  end
end

-- Filter and highlight terminal output (non-destructive)
-- Stores original lines in cache before replacing buffer content.
-- Original lines can be restored via restore_buffer().
-- @param bufnr number The buffer number
-- @param filters table Filter configuration
-- @return number Number of lines hidden
function M.apply_filters(bufnr, filters)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end

  if not filters or not filters.enabled then
    return 0
  end

  -- Clear previous highlights
  M.clear_highlights(bufnr)

  -- Use cached original lines if available, otherwise read from buffer
  local lines = original_lines_cache[bufnr]
  if not lines then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    original_lines_cache[bufnr] = lines
  end

  local hidden_count = 0
  local new_lines = {}

  for _, line in ipairs(lines) do
    if should_show_line(line, filters) then
      table.insert(new_lines, line)
    else
      hidden_count = hidden_count + 1
    end
  end

  -- Update buffer content with filtered lines
  if hidden_count > 0 then
    local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
    if not was_modifiable then
      vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    if not was_modifiable then
      vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    end
  end

  -- Apply highlights to the visible lines
  if filters.highlight and #filters.highlight > 0 then
    local visible_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(visible_lines) do
      M.highlight_line(bufnr, i, line, filters.highlight)
    end
  end

  return hidden_count
end

-- Restore original unfiltered buffer content
-- @param bufnr number The buffer number
-- @return boolean True if buffer was restored
function M.restore_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local cached = original_lines_cache[bufnr]
  if not cached then
    return false
  end

  local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  if not was_modifiable then
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cached)
  if not was_modifiable then
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  end
  original_lines_cache[bufnr] = nil
  return true
end

-- Check if a buffer has cached original lines
-- @param bufnr number The buffer number
-- @return boolean True if original lines are cached
function M.has_original_lines(bufnr)
  return original_lines_cache[bufnr] ~= nil
end

-- Process a single line for real-time filtering
-- @param line string The line text
-- @param filters table Filter configuration
-- @return boolean, table Whether to show line and highlight matches
function M.process_line(line, filters)
  if not filters or not filters.enabled then
    return true, {}
  end

  local show = should_show_line(line, filters)
  local highlights = {}

  if show and filters.highlight and #filters.highlight > 0 then
    highlights = find_highlights(line, filters.highlight)
  end

  return show, highlights
end

-- Clear all filter highlights from a buffer (does not touch content)
-- @param bufnr number The buffer number
function M.clear_highlights(bufnr)
  if not ns_id then
    return
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

-- Clear buffer: restore original lines and remove highlights
-- @param bufnr number The buffer number
function M.clear_buffer(bufnr)
  M.clear_highlights(bufnr)
  M.restore_buffer(bufnr)
end

-- Clear all filter highlights from all buffers and discard caches
function M.clear_all()
  if ns_id then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      end
    end
  end

  original_lines_cache = {}
end

-- Discard the original lines cache for a buffer
-- @param bufnr number The buffer number
function M.discard_cache(bufnr)
  original_lines_cache[bufnr] = nil
end

-- Toggle filter enabled state
-- @param bufnr number The buffer number
-- @param filters table Filter configuration
-- @return boolean New enabled state
function M.toggle_enabled(bufnr, filters)
  if not filters then
    return false
  end

  filters.enabled = not filters.enabled

  if filters.enabled then
    M.apply_filters(bufnr, filters)
  else
    -- Restore original content and clear highlights
    M.clear_buffer(bufnr)
  end

  return filters.enabled
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

-- Create a preset filter configuration
-- @param name string Preset name ("errors", "warnings", "info")
-- @return table Filter configuration
function M.create_preset(name)
  local presets = {
    errors = {
      enabled = true,
      show_only = { "error", "fail", "exception", "fatal" },
      hide = {},
      highlight = {
        { pattern = "error", color = "#ff0000" },
        { pattern = "fail", color = "#ff0000" },
        { pattern = "exception", color = "#ff0000" },
        { pattern = "fatal", color = "#ff0000" },
      },
    },
    warnings = {
      enabled = true,
      show_only = { "warning", "warn" },
      hide = {},
      highlight = {
        { pattern = "warning", color = "#ffaa00" },
        { pattern = "warn", color = "#ffaa00" },
      },
    },
    info = {
      enabled = true,
      show_only = { "info", "note", "success" },
      hide = {},
      highlight = {
        { pattern = "info", color = "#00aaff" },
        { pattern = "note", color = "#00aaff" },
        { pattern = "success", color = "#00ff00" },
      },
    },
    all = {
      enabled = true,
      show_only = {},
      hide = { "debug", "verbose", "trace" },
      highlight = {
        { pattern = "error", color = "#ff0000" },
        { pattern = "warning", color = "#ffaa00" },
        { pattern = "success", color = "#00ff00" },
        { pattern = "info", color = "#00aaff" },
      },
    },
  }

  return presets[name] or presets.all
end

return M
