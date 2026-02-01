-- TermLet History Module
-- Tracks script execution history with metadata for quick re-running

local M = {}

-- History state
local state = {
  entries = {}, -- List of history entries
  max_entries = 50, -- Maximum number of history entries to keep
  buf = nil,
  win = nil,
  config = nil,
  rerun_callback = nil,
}

-- Default history UI configuration
local default_config = {
  width_ratio = 0.7,
  height_ratio = 0.6,
  border = "rounded",
  title = " TermLet History ",
  highlight = {
    selected = "CursorLine",
    success = "DiagnosticOk",
    error = "DiagnosticError",
    title = "Title",
    help = "Comment",
  },
}

-- Highlight namespace
local ns_id = vim.api.nvim_create_namespace("termlet_history")

--- Add an entry to the history
---@param entry table History entry with script_name, exit_code, execution_time, timestamp, working_dir
function M.add_entry(entry)
  -- Validate entry
  if not entry.script_name then
    return
  end

  -- Add timestamp if not provided
  if not entry.timestamp then
    entry.timestamp = os.time()
  end

  -- Insert at the beginning (most recent first)
  table.insert(state.entries, 1, entry)

  -- Enforce max_entries limit
  while #state.entries > state.max_entries do
    table.remove(state.entries)
  end
end

--- Get all history entries
---@return table List of history entries
function M.get_entries()
  return state.entries
end

--- Get the most recent history entry
---@return table|nil Most recent entry or nil if history is empty
function M.get_last_entry()
  if #state.entries > 0 then
    return state.entries[1]
  end
  return nil
end

--- Clear all history entries
function M.clear_history()
  state.entries = {}
end

--- Set maximum number of history entries to keep
---@param max number Maximum entries
function M.set_max_entries(max)
  if type(max) == "number" and max > 0 then
    state.max_entries = max
    -- Trim existing entries if necessary
    while #state.entries > state.max_entries do
      table.remove(state.entries)
    end
  end
end

--- Calculate window dimensions and position
---@param config table UI configuration
---@return table Window options for nvim_open_win
local function calculate_window_opts(config)
  local width = math.floor(vim.o.columns * config.width_ratio)
  local height = math.floor(vim.o.lines * config.height_ratio)

  -- Minimum dimensions
  width = math.max(width, 60)
  height = math.max(height, 15)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    anchor = "NW",
    style = "minimal",
    border = config.border,
    title = config.title,
    title_pos = "center",
    footer = " [Enter] Re-run  [c] Clear  [q] Close ",
    footer_pos = "center",
  }
end

--- Format execution time in human-readable format
---@param seconds number|nil Execution time in seconds
---@return string Formatted time string
local function format_execution_time(seconds)
  if not seconds or seconds < 0 then
    return "N/A"
  end

  if seconds < 1 then
    return string.format("%.0fms", seconds * 1000)
  elseif seconds < 60 then
    return string.format("%.1fs", seconds)
  elseif seconds < 3600 then
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%dm %.0fs", mins, secs)
  else
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dm", hours, mins)
  end
end

--- Format a timestamp in human-readable format
---@param timestamp number Unix timestamp
---@return string Formatted timestamp
local function format_timestamp(timestamp)
  return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

--- Format a history entry for display
---@param entry table History entry
---@param index number Index in the list
---@param is_selected boolean Whether this entry is selected
---@param width number Available width for the line
---@return string Formatted line
local function format_history_line(entry, index, is_selected, width)
  local prefix = is_selected and "  > " or "    "

  -- Status icon
  local status_icon = entry.exit_code == 0 and "✓" or "✗"

  -- Script name (truncate if needed)
  local name = entry.script_name or "unknown"
  local name_width = math.min(#name, 25)
  local display_name = name:sub(1, name_width)
  if #name > name_width then
    display_name = display_name:sub(1, name_width - 1) .. "…"
  end

  -- Execution time
  local exec_time = format_execution_time(entry.execution_time)

  -- Timestamp
  local time_str = os.date("%H:%M:%S", entry.timestamp)

  -- Exit code
  local exit_str = string.format("exit:%d", entry.exit_code or -1)

  -- Build the line
  local line = string.format("%s%s  %-25s  %8s  %8s  %s",
    prefix, status_icon, display_name, exec_time, exit_str, time_str)

  return line
end

--- Get the help text lines
---@return table List of help text lines
local function get_help_lines()
  return {
    "",
    "  Keybindings:",
    "  ────────────────────────────────",
    "  j / ↓        Move down",
    "  k / ↑        Move up",
    "  Enter        Re-run selected script",
    "  c            Clear history",
    "  Escape       Close history",
    "  q            Close history",
    "  gg           Go to first entry",
    "  G            Go to last entry",
    "",
  }
end

--- Render the history UI
local function render_history()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local win_opts = calculate_window_opts(state.config)
  local width = win_opts.width - 2 -- Account for borders

  -- Clear existing content and highlights
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

  local lines = {}
  local highlights = {}

  -- Add header
  table.insert(lines, "")
  local header = string.format("  %s  %-25s  %8s  %8s  %s",
    " ", "Script", "Duration", "Exit", "Time")
  table.insert(lines, header)
  table.insert(lines, "  " .. string.rep("─", width - 4))

  -- Add history entries
  if #state.entries == 0 then
    table.insert(lines, "")
    table.insert(lines, "    No history available")
    table.insert(lines, "")
  else
    local selected_index = state.selected_index or 1
    for i, entry in ipairs(state.entries) do
      local is_selected = (i == selected_index)
      local line = format_history_line(entry, i, is_selected, width)
      table.insert(lines, line)

      if is_selected then
        table.insert(highlights, { line = #lines - 1, group = state.config.highlight.selected })
      end

      -- Color-code by exit status
      if entry.exit_code == 0 then
        table.insert(highlights, {
          line = #lines - 1,
          col_start = is_selected and 4 or 4,
          col_end = is_selected and 5 or 5,
          group = state.config.highlight.success
        })
      else
        table.insert(highlights, {
          line = #lines - 1,
          col_start = is_selected and 4 or 4,
          col_end = is_selected and 5 or 5,
          group = state.config.highlight.error
        })
      end
    end
  end

  -- Pad to fill window
  local target_height = win_opts.height - 2 -- Account for borders
  while #lines < target_height do
    table.insert(lines, "")
  end

  -- Set buffer content
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    if hl.col_start and hl.col_end then
      vim.api.nvim_buf_add_highlight(state.buf, ns_id, hl.group, hl.line, hl.col_start, hl.col_end)
    else
      vim.api.nvim_buf_add_highlight(state.buf, ns_id, hl.group, hl.line, 0, -1)
    end
  end
end

--- Move selection up
local function move_up()
  if #state.entries == 0 then
    return
  end

  state.selected_index = (state.selected_index or 1) - 1
  if state.selected_index < 1 then
    state.selected_index = #state.entries
  end
  render_history()
end

--- Move selection down
local function move_down()
  if #state.entries == 0 then
    return
  end

  state.selected_index = (state.selected_index or 1) + 1
  if state.selected_index > #state.entries then
    state.selected_index = 1
  end
  render_history()
end

--- Go to first item
local function go_to_first()
  if #state.entries == 0 then
    return
  end
  state.selected_index = 1
  render_history()
end

--- Go to last item
local function go_to_last()
  if #state.entries == 0 then
    return
  end
  state.selected_index = #state.entries
  render_history()
end

--- Re-run the selected entry
local function rerun_selected()
  if #state.entries == 0 then
    return
  end

  local selected_entry = state.entries[state.selected_index or 1]
  if not selected_entry then
    return
  end

  -- Close history UI
  M.close()

  -- Execute via callback
  if state.rerun_callback then
    vim.schedule(function()
      state.rerun_callback(selected_entry)
    end)
  end
end

--- Clear history
local function clear_history_ui()
  M.clear_history()
  render_history()
  vim.notify("History cleared", vim.log.levels.INFO)
end

--- Close the history UI
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.selected_index = nil
end

--- Set up keymaps for the history buffer
local function setup_keymaps()
  local buf = state.buf
  local opts = { noremap = true, silent = true, buffer = buf }

  -- Navigation
  vim.keymap.set("n", "j", move_down, opts)
  vim.keymap.set("n", "k", move_up, opts)
  vim.keymap.set("n", "<Down>", move_down, opts)
  vim.keymap.set("n", "<Up>", move_up, opts)
  vim.keymap.set("n", "gg", go_to_first, opts)
  vim.keymap.set("n", "G", go_to_last, opts)

  -- Actions
  vim.keymap.set("n", "<CR>", rerun_selected, opts)
  vim.keymap.set("n", "<Enter>", rerun_selected, opts)
  vim.keymap.set("n", "c", clear_history_ui, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
end

--- Open the history browser UI
---@param rerun_callback function Callback to re-run a script from history
---@param ui_config table|nil Optional UI configuration
---@return boolean Success
function M.open(rerun_callback, ui_config)
  -- Close existing window if open
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  end

  -- Check if we have history
  if #state.entries == 0 then
    vim.notify("No history available", vim.log.levels.INFO)
    return false
  end

  -- Initialize state
  state.selected_index = 1
  state.rerun_callback = rerun_callback
  state.config = vim.tbl_deep_extend("force", default_config, ui_config or {})

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  if not state.buf then
    vim.notify("Failed to create history buffer", vim.log.levels.ERROR)
    return false
  end

  -- Set buffer options
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "termlet_history"
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].modifiable = false

  -- Create window
  local win_opts = calculate_window_opts(state.config)
  state.win = vim.api.nvim_open_win(state.buf, true, win_opts)

  if not state.win then
    vim.api.nvim_buf_delete(state.buf, { force = true })
    vim.notify("Failed to create history window", vim.log.levels.ERROR)
    return false
  end

  -- Set window options
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].wrap = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"

  -- Auto-close on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = state.buf,
    callback = function()
      M.close()
    end,
    once = true,
  })

  -- Set up keymaps
  setup_keymaps()

  -- Render initial content
  render_history()

  return true
end

--- Check if history UI is currently open
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Get current state (for testing)
---@return table
function M.get_state()
  return {
    selected_index = state.selected_index,
    entry_count = #state.entries,
    max_entries = state.max_entries,
  }
end

--- Set state directly (for testing)
function M._set_entries(entries)
  state.entries = entries or {}
end

return M
