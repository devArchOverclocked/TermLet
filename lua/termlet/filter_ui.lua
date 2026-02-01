-- Interactive filter UI module
-- Provides an interactive interface for managing output filters
-- lua/termlet/filter_ui.lua

local M = {}

local filter = require("termlet.filter")

-- UI state
local ui_state = {
  win = nil,
  buf = nil,
  target_buf = nil,
  current_preset = "all",
}

-- Available presets
local presets = {
  { name = "all", description = "Show all (hide debug/verbose)" },
  { name = "errors", description = "Show only errors" },
  { name = "warnings", description = "Show only warnings" },
  { name = "info", description = "Show only info/success" },
}

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

  local lines = {
    "┌─ Filter Mode ─────────────────────┐",
    "│                                   │",
    "│  Select a filter preset:          │",
    "│                                   │",
  }

  for i, preset in ipairs(presets) do
    local prefix = (ui_state.current_preset == preset.name) and "  > " or "    "
    local line = string.format("│%s[%d] %-10s %s", prefix, i, preset.name, preset.description)
    -- Pad to match border width
    local padding = 35 - #line
    if padding > 0 then
      line = line .. string.rep(" ", padding)
    end
    line = line .. "│"
    table.insert(lines, line)
  end

  table.insert(lines, "│                                   │")
  table.insert(lines, "│  [1-4] Select  [Enter] Apply      │")
  table.insert(lines, "│  [d] Disable   [q/Esc] Close      │")
  table.insert(lines, "│                                   │")
  table.insert(lines, "└───────────────────────────────────┘")

  vim.api.nvim_buf_set_lines(ui_state.buf, 0, -1, false, lines)
end

-- Apply the current preset
local function apply_current_preset()
  if not ui_state.target_buf or not vim.api.nvim_buf_is_valid(ui_state.target_buf) then
    vim.notify("Target buffer is no longer valid", vim.log.levels.ERROR)
    M.close()
    return
  end

  local termlet = require("termlet")
  local current_buf = vim.api.nvim_get_current_buf()

  -- Temporarily switch context to target buffer
  local original_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(ui_state.target_buf)

  termlet.apply_filter_preset(ui_state.current_preset)

  -- Restore original context
  vim.api.nvim_set_current_buf(original_buf)
end

-- Setup keybindings for the filter UI
local function setup_keybindings()
  if not ui_state.buf or not vim.api.nvim_buf_is_valid(ui_state.buf) then
    return
  end

  local opts = { noremap = true, silent = true, buffer = ui_state.buf }

  -- Number keys to select preset
  for i = 1, #presets do
    vim.keymap.set("n", tostring(i), function()
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
      local original_buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_set_current_buf(ui_state.target_buf)
      termlet.toggle_filters()
      vim.api.nvim_set_current_buf(original_buf)
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
    return
  end

  -- Validate target buffer
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    vim.notify("Invalid target buffer", vim.log.levels.ERROR)
    return false
  end

  ui_state.target_buf = target_buf

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

  -- Calculate window size
  local width = 40
  local height = 15
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "none",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  if not win then
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify("Failed to create filter UI window", vim.log.levels.ERROR)
    return false
  end

  ui_state.win = win

  -- Setup UI
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  render_ui()
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

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
