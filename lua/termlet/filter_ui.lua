-- Interactive filter UI module
-- Provides an interactive interface for managing output filters
-- lua/termlet/filter_ui.lua

local M = {}

-- UI state
local ui_state = {
  win = nil,
  buf = nil,
  target_buf = nil,
  current_preset = "all",
  selected_index = 1,
}

-- Available presets
local presets = {
  { name = "all", description = "Show all output (hide debug/verbose)" },
  { name = "errors", description = "Show only errors" },
  { name = "warnings", description = "Show only warnings" },
  { name = "info", description = "Show only info and success messages" },
}

-- Highlight namespace
local ns_id = vim.api.nvim_create_namespace("termlet_filter_ui")

-- Check if UI is currently open
function M.is_open()
  return ui_state.win ~= nil and vim.api.nvim_win_is_valid(ui_state.win)
end

-- Close the filter UI
function M.close()
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    vim.api.nvim_win_close(ui_state.win, true)
  end
  ui_state.win = nil
  ui_state.buf = nil
  ui_state.target_buf = nil
end

-- Render the filter UI content
local function render_ui()
  if not ui_state.buf or not vim.api.nvim_buf_is_valid(ui_state.buf) then
    return
  end

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(ui_state.buf, ns_id, 0, -1)

  local lines = {}
  local highlights = {}

  table.insert(lines, "")
  table.insert(lines, "    Select a filter preset:")
  table.insert(highlights, { line = #lines - 1, group = "Title" })
  table.insert(lines, "    " .. string.rep("─", 40))
  table.insert(lines, "")

  for i, preset in ipairs(presets) do
    local is_selected = (i == ui_state.selected_index)
    local is_active = (ui_state.current_preset == preset.name)
    local pointer = is_selected and " > " or "   "
    local active_marker = is_active and " * " or "   "
    local line = pointer .. string.format(" %d.%s%-10s  %s", i, active_marker, preset.name, preset.description)
    table.insert(lines, line)

    local line_idx = #lines - 1
    if is_selected then
      table.insert(highlights, { line = line_idx, group = "CursorLine" })
    elseif is_active then
      table.insert(highlights, { line = line_idx, group = "String" })
    end
  end

  table.insert(lines, "")
  table.insert(lines, "    " .. string.rep("─", 40))
  table.insert(lines, "")
  table.insert(lines, "    * = currently active preset")
  table.insert(highlights, { line = #lines - 1, group = "Comment" })
  table.insert(lines, "")

  -- Pad remaining space
  local win_config = vim.api.nvim_win_get_config(ui_state.win)
  local target_height = (win_config.height or 15) - 2
  while #lines < target_height do
    table.insert(lines, "")
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = ui_state.buf })
  vim.api.nvim_buf_set_lines(ui_state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ui_state.buf })

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(ui_state.buf, ns_id, hl.group, hl.line, 0, -1)
  end
end

-- Apply the current preset to the target buffer directly (no buffer switching)
local function apply_current_preset()
  if not ui_state.target_buf or not vim.api.nvim_buf_is_valid(ui_state.target_buf) then
    vim.notify("Target buffer is no longer valid", vim.log.levels.ERROR)
    M.close()
    return
  end

  local selected_preset = presets[ui_state.selected_index]
  if selected_preset then
    ui_state.current_preset = selected_preset.name
  end

  local termlet = require("termlet")
  termlet.apply_filter_preset_to_buf(ui_state.target_buf, ui_state.current_preset)
end

-- Move selection up
local function move_up()
  ui_state.selected_index = ui_state.selected_index - 1
  if ui_state.selected_index < 1 then
    ui_state.selected_index = #presets
  end
  render_ui()
end

-- Move selection down
local function move_down()
  ui_state.selected_index = ui_state.selected_index + 1
  if ui_state.selected_index > #presets then
    ui_state.selected_index = 1
  end
  render_ui()
end

-- Setup keybindings for the filter UI
local function setup_keybindings()
  if not ui_state.buf or not vim.api.nvim_buf_is_valid(ui_state.buf) then
    return
  end

  local opts = { noremap = true, silent = true, buffer = ui_state.buf }

  -- Navigation
  vim.keymap.set("n", "j", move_down, opts)
  vim.keymap.set("n", "k", move_up, opts)
  vim.keymap.set("n", "<Down>", move_down, opts)
  vim.keymap.set("n", "<Up>", move_up, opts)

  -- Number keys to select preset
  for i = 1, #presets do
    vim.keymap.set("n", tostring(i), function()
      ui_state.selected_index = i
      ui_state.current_preset = presets[i].name
      render_ui()
    end, opts)
  end

  -- Enter to apply
  vim.keymap.set("n", "<CR>", function()
    apply_current_preset()
    M.close()
  end, opts)

  -- d to disable filters
  vim.keymap.set("n", "d", function()
    if ui_state.target_buf and vim.api.nvim_buf_is_valid(ui_state.target_buf) then
      local termlet = require("termlet")
      termlet.disable_filters_for_buf(ui_state.target_buf)
    end
    M.close()
  end, opts)

  -- q and Esc to close
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)
end

-- Open the filter UI
function M.open(target_buf)
  if M.is_open() then
    M.close()
    return false
  end

  -- Validate target buffer
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    vim.notify("Invalid target buffer", vim.log.levels.ERROR)
    return false
  end

  ui_state.target_buf = target_buf
  ui_state.selected_index = 1

  -- Find current active preset index
  for i, preset in ipairs(presets) do
    if preset.name == ui_state.current_preset then
      ui_state.selected_index = i
      break
    end
  end

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  if not buf then
    vim.notify("Failed to create filter UI buffer", vim.log.levels.ERROR)
    return false
  end

  ui_state.buf = buf

  -- Set buffer options
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "termlet-filter", { buf = buf })

  -- Calculate window size - use native border instead of ASCII art
  local width = 55
  local height = 14
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window with native border
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Filter Mode ",
    title_pos = "center",
    footer = " Enter: Apply  j/k: Navigate  d: Disable  q: Close ",
    footer_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  if not win then
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify("Failed to create filter UI window", vim.log.levels.ERROR)
    return false
  end

  ui_state.win = win

  -- Set window options
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  -- Setup UI
  render_ui()

  setup_keybindings()

  -- Auto-close when window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    callback = function()
      M.close()
    end,
    once = true,
  })

  return true
end

-- Toggle the filter UI
function M.toggle(target_buf)
  if M.is_open() then
    M.close()
  else
    M.open(target_buf)
  end
end

return M
