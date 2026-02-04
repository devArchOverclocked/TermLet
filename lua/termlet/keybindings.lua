-- TermLet Keybindings Module
-- Provides a visual interface for configuring and managing keybindings for script execution

local M = {}

-- Keybinding UI state
local state = {
  buf = nil,
  win = nil,
  scripts = {},
  selected_index = 1,
  mode = "normal", -- "normal", "capture", "input"
  captured_keys = {}, -- list of key notations captured in sequence
  input_text = "", -- text typed in input mode
  show_help = false,
  config = nil,
  on_save_callback = nil,
  keybindings = {}, -- script_name -> keybinding mapping
  on_key_ns = nil, -- vim.on_key namespace for capture mode
  capture_timer = nil, -- timer for finalizing multi-key capture
}

-- Default configuration
local default_config = {
  width_ratio = 0.6,
  height_ratio = 0.6,
  border = "rounded",
  title = " TermLet Keybindings ",
  highlight = {
    selected = "CursorLine",
    header = "Title",
    help = "Comment",
    keybinding = "String",
    warning = "WarningMsg",
    notset = "NonText",
    counter = "NonText",
  },
}

-- Config file path
local config_file_path = vim.fn.stdpath("data") .. "/termlet-keybindings.json"

-- Highlight namespace
local ns_id = vim.api.nvim_create_namespace("termlet_keybindings")

--- Calculate window dimensions and position
---@param config table Configuration
---@return table Window options for nvim_open_win
local function calculate_window_opts(config)
  local width = math.floor(vim.o.columns * config.width_ratio)
  local height = math.floor(vim.o.lines * config.height_ratio)

  -- Minimum dimensions
  width = math.max(width, 56)
  height = math.max(height, 14)

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
    footer = " c Capture  i Type  d Delete  ? Help  q Close ",
    footer_pos = "center",
  }
end

--- Get the help text lines
---@param width number Available width
---@return table List of help text lines
local function get_help_lines(width)
  local sep = "   " .. string.rep("─", math.max(width - 6, 30))
  return {
    "",
    "   Keyboard Shortcuts",
    sep,
    "",
    "   Navigation",
    "   j / Down        Move down",
    "   k / Up          Move up",
    "   gg              Go to first script",
    "   G               Go to last script",
    "",
    "   Actions",
    "   c / Enter       Capture keybinding",
    "   i               Type keybinding notation",
    "   d               Delete keybinding",
    "   Esc             Cancel / close",
    "   q               Close menu",
    "   ?               Toggle this help",
    "",
    "   Capture Mode (c / Enter)",
    sep,
    "   Press keys in sequence",
    "   Keys are recorded in real-time",
    "   Enter           Confirm captured keys",
    "   Esc             Cancel capture",
    "",
    "   Input Mode (i)",
    sep,
    "   Type notation: <leader>b, <C-k>",
    "   Enter           Confirm input",
    "   Esc             Cancel input",
    "",
  }
end

--- Format a keybinding entry for display
---@param script table Script configuration
---@param keybinding string|nil Current keybinding
---@param index number Index in the list
---@param is_selected boolean Whether this entry is selected
---@param width number Available width for the line
---@param total_count number Total number of scripts (for index column alignment)
---@return string Formatted line
---@return table[] Inline highlight info
local function format_keybinding_line(script, keybinding, index, is_selected, width, total_count)
  local pointer = is_selected and "  " or "   "
  local idx_str = string.format(" %d. ", index)
  local name = script.name or "unnamed"

  -- Calculate column widths (must match header in render_ui)
  local name_width = math.floor(width * 0.35)
  local key_width = math.floor(width * 0.25)

  -- Calculate padding for consistent index column width (same pattern as menu.lua)
  local max_idx_width = #string.format(" %d. ", total_count)
  local prefix_pad = max_idx_width - #idx_str

  -- Format all columns with string.format for consistent alignment
  local padded_name = string.format("%-" .. name_width .. "s", name:sub(1, name_width))

  local key_display
  if keybinding and keybinding ~= "" then
    key_display = keybinding
  else
    key_display = "(not set)"
  end
  local padded_key = string.format("%-" .. key_width .. "s", key_display:sub(1, key_width))

  local line = pointer .. idx_str .. string.rep(" ", prefix_pad) .. padded_name .. "  " .. padded_key

  local inline_hl = {}

  -- Track key column for inline highlighting
  local key_start = #pointer + #idx_str + prefix_pad + name_width + 2
  local key_end = key_start + #padded_key
  if keybinding and keybinding ~= "" then
    table.insert(inline_hl, { col_start = key_start, col_end = key_end, group = "keybinding" })
  else
    table.insert(inline_hl, { col_start = key_start, col_end = key_end, group = "notset" })
  end

  -- Pad to full width for consistent highlight background
  if #line < width then
    line = line .. string.rep(" ", width - #line)
  end

  return line, inline_hl
end

--- Render the keybindings UI
local function render_ui()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local win_opts = calculate_window_opts(state.config)
  local width = win_opts.width - 2 -- Account for borders

  -- Clear existing content and highlights
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

  local lines = {}
  local highlights = {}

  -- Mode-specific rendering
  if state.mode == "capture" then
    -- Real-time key capture mode UI
    table.insert(lines, "")
    table.insert(lines, "   Capture Keybinding")
    table.insert(highlights, { line = #lines - 1, group = state.config.highlight.header })

    local sep = "   " .. string.rep("─", width - 6)
    table.insert(lines, sep)
    table.insert(lines, "")

    local script_name = state.scripts[state.selected_index] and state.scripts[state.selected_index].name or "unknown"
    table.insert(lines, "   Setting keybinding for: " .. script_name)
    table.insert(lines, "")
    table.insert(lines, "   Press keys in sequence (real-time capture)")
    table.insert(lines, "   Enter to confirm, Esc to cancel")
    table.insert(lines, "")

    local captured_display = #state.captured_keys > 0 and table.concat(state.captured_keys, "") or "(waiting...)"
    local captured_line = "   Captured:  " .. captured_display
    table.insert(lines, captured_line)
    if #state.captured_keys > 0 then
      table.insert(highlights, { line = #lines - 1, group = state.config.highlight.keybinding })
    end
  elseif state.mode == "input" then
    -- Text input mode UI for typing notation like <leader>b
    table.insert(lines, "")
    table.insert(lines, "   Type Keybinding Notation")
    table.insert(highlights, { line = #lines - 1, group = state.config.highlight.header })

    local sep = "   " .. string.rep("─", width - 6)
    table.insert(lines, sep)
    table.insert(lines, "")

    local script_name = state.scripts[state.selected_index] and state.scripts[state.selected_index].name or "unknown"
    table.insert(lines, "   Setting keybinding for: " .. script_name)
    table.insert(lines, "")
    table.insert(lines, "   Type vim notation (e.g. <leader>b, <C-k>, <A-j>)")
    table.insert(lines, "   Enter to confirm, Esc to cancel")
    table.insert(lines, "")

    local input_display = state.input_text .. "█"
    local input_line = "   Input:  " .. input_display
    table.insert(lines, input_line)
    table.insert(highlights, { line = #lines - 1, group = state.config.highlight.keybinding })
  elseif state.show_help then
    -- Help display
    for _, help_line in ipairs(get_help_lines(width)) do
      table.insert(lines, help_line)
      table.insert(highlights, { line = #lines - 1, group = state.config.highlight.help })
    end
  else
    -- Normal mode - show keybinding list
    table.insert(lines, "")

    -- Header - use same column widths as data rows for alignment
    local name_width = math.floor(width * 0.35)
    local key_width = math.floor(width * 0.25)
    -- Calculate max index width to match data row prefix (same pattern as menu.lua)
    local max_idx_width = #string.format(" %d. ", #state.scripts)
    local header_prefix = "   " .. string.rep(" ", max_idx_width)
    local header = header_prefix
      .. string.format("%-" .. name_width .. "s", "Script")
      .. "  "
      .. string.format("%-" .. key_width .. "s", "Keybinding")
    table.insert(lines, header)
    table.insert(highlights, { line = #lines - 1, group = state.config.highlight.header })

    local sep = "   " .. string.rep("─", width - 4)
    table.insert(lines, sep)
    table.insert(highlights, { line = #lines - 1, group = state.config.highlight.header })

    if #state.scripts == 0 then
      table.insert(lines, "")
      table.insert(lines, "   No scripts configured")
      table.insert(lines, "")
    else
      for i, script in ipairs(state.scripts) do
        local is_selected = (i == state.selected_index)
        local keybinding = state.keybindings[script.name]
        local line, inline_hl = format_keybinding_line(script, keybinding, i, is_selected, width, #state.scripts)
        table.insert(lines, line)

        local line_idx = #lines - 1
        if is_selected then
          table.insert(highlights, { line = line_idx, group = state.config.highlight.selected })
        end

        -- Apply inline keybinding/notset highlights when not selected
        if not is_selected then
          for _, ihl in ipairs(inline_hl) do
            table.insert(highlights, {
              line = line_idx,
              col_start = ihl.col_start,
              col_end = ihl.col_end,
              group = state.config.highlight[ihl.group] or state.config.highlight.notset,
            })
          end
        end
      end

      -- Counter
      table.insert(lines, "")
      local bound_count = 0
      for _, script in ipairs(state.scripts) do
        if state.keybindings[script.name] and state.keybindings[script.name] ~= "" then
          bound_count = bound_count + 1
        end
      end
      local counter_text = string.format("   %d of %d scripts have keybindings", bound_count, #state.scripts)
      table.insert(lines, counter_text)
      table.insert(highlights, { line = #lines - 1, group = state.config.highlight.counter })
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
  if state.mode ~= "normal" or state.show_help or #state.scripts == 0 then
    return
  end

  state.selected_index = state.selected_index - 1
  if state.selected_index < 1 then
    state.selected_index = #state.scripts
  end
  render_ui()
end

--- Move selection down
local function move_down()
  if state.mode ~= "normal" or state.show_help or #state.scripts == 0 then
    return
  end

  state.selected_index = state.selected_index + 1
  if state.selected_index > #state.scripts then
    state.selected_index = 1
  end
  render_ui()
end

--- Go to first item
local function go_to_first()
  if state.mode ~= "normal" or state.show_help or #state.scripts == 0 then
    return
  end
  state.selected_index = 1
  render_ui()
end

--- Go to last item
local function go_to_last()
  if state.mode ~= "normal" or state.show_help or #state.scripts == 0 then
    return
  end
  state.selected_index = #state.scripts
  render_ui()
end

--- Toggle help display
local function toggle_help()
  if state.mode ~= "normal" then
    return
  end
  state.show_help = not state.show_help
  render_ui()
end

--- Check if a keybinding conflicts with another script
---@param keybinding string The keybinding to check
---@param exclude_script string|nil Script name to exclude from check
---@return string|nil Conflicting script name, or nil if no conflict
local function check_conflict(keybinding, exclude_script)
  if not keybinding or keybinding == "" then
    return nil
  end

  for script_name, existing_key in pairs(state.keybindings) do
    if script_name ~= exclude_script and existing_key == keybinding then
      return script_name
    end
  end

  return nil
end

--- Restore the default footer on the keybindings window
local function restore_footer()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      footer = " c Capture  i Type  d Delete  ? Help  q Close ",
      footer_pos = "center",
    })
  end
end

--- Stop the capture timer if running
local function stop_capture_timer()
  if state.capture_timer then
    state.capture_timer:stop()
    state.capture_timer:close()
    state.capture_timer = nil
  end
end

--- Detach the on_key handler
local function detach_on_key()
  if state.on_key_ns then
    vim.on_key(nil, state.on_key_ns)
    state.on_key_ns = nil
  end
end

--- Apply the captured keybinding to the selected script
---@param keybinding_str string The keybinding notation string
local function apply_captured_keybinding(keybinding_str)
  local script = state.scripts[state.selected_index]
  if script and keybinding_str and keybinding_str ~= "" then
    -- Check for conflicts
    local conflict = check_conflict(keybinding_str, script.name)
    if conflict then
      vim.notify(
        "Warning: Keybinding '" .. keybinding_str .. "' is already used by '" .. conflict .. "'",
        vim.log.levels.WARN
      )
    end

    state.keybindings[script.name] = keybinding_str
    vim.notify("Set keybinding for '" .. script.name .. "' to '" .. keybinding_str .. "'", vim.log.levels.INFO)

    -- Auto-save
    M.save()

    -- Notify callback
    if state.on_save_callback then
      state.on_save_callback(state.keybindings)
    end
  end
end

--- Exit capture or input mode and return to normal
---@param skip_render boolean|nil If true, skip the render_ui() call
local function exit_capture(skip_render)
  stop_capture_timer()
  detach_on_key()
  state.mode = "normal"
  state.captured_keys = {}
  state.input_text = ""
  restore_footer()
  if not skip_render then
    render_ui()
  end
end

--- Enter real-time key capture mode using vim.on_key
local function enter_capture_mode()
  if #state.scripts == 0 then
    return
  end
  -- Guard: prevent re-entry when already in capture/input mode.
  -- The buffer keymap for <CR> fires synchronously, while the vim.on_key
  -- handler fires via vim.schedule(). Without this guard, pressing Enter
  -- to confirm a capture would re-enter this function and reset state
  -- before the deferred on_key callback processes the confirmation.
  if state.mode == "capture" or state.mode == "input" then
    return
  end

  state.mode = "capture"
  state.captured_keys = {}

  -- Update window footer
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      footer = " Press keys...  Enter confirm  Esc cancel ",
      footer_pos = "center",
    })
  end

  render_ui()

  -- Use vim.on_key for real-time key capture
  state.on_key_ns = vim.api.nvim_create_namespace("termlet_key_capture")
  vim.on_key(function(key, typed)
    if state.mode ~= "capture" then
      detach_on_key()
      return
    end

    -- Use the typed key if available, otherwise the remapped key
    local raw = typed or key
    if not raw or raw == "" then
      return
    end

    -- Translate to key notation
    local notation = vim.fn.keytrans(raw)
    if notation == "" then
      return
    end

    vim.schedule(function()
      if state.mode ~= "capture" then
        return
      end

      -- Check for Escape -> cancel
      if notation == "<Esc>" then
        exit_capture()
        return
      end

      -- Check for Enter -> confirm
      if notation == "<CR>" then
        if #state.captured_keys > 0 then
          local keybinding_str = table.concat(state.captured_keys, "")
          -- Clean up capture state WITHOUT rendering (skip_render=true).
          -- We must apply the keybinding before rendering so the UI shows
          -- the newly set keybinding instead of flashing back to "(waiting...)".
          exit_capture(true)
          apply_captured_keybinding(keybinding_str)
          render_ui()
        end
        return
      end

      -- Append the key to the sequence
      table.insert(state.captured_keys, notation)
      render_ui()
    end)
  end, state.on_key_ns)
end

--- Enter text input mode for typing keybinding notation directly
local function enter_input_mode()
  if #state.scripts == 0 then
    return
  end
  -- Guard: prevent re-entry when already in capture/input mode (same race as above)
  if state.mode == "capture" or state.mode == "input" then
    return
  end

  state.mode = "input"
  state.input_text = ""

  -- Update window footer
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      footer = " Type notation...  Enter confirm  Esc cancel ",
      footer_pos = "center",
    })
  end

  render_ui()

  -- Use vim.on_key for real-time text input
  state.on_key_ns = vim.api.nvim_create_namespace("termlet_key_input")
  vim.on_key(function(key, typed)
    if state.mode ~= "input" then
      detach_on_key()
      return
    end

    local raw = typed or key
    if not raw or raw == "" then
      return
    end

    local notation = vim.fn.keytrans(raw)
    if notation == "" then
      return
    end

    vim.schedule(function()
      if state.mode ~= "input" then
        return
      end

      -- Check for Escape -> cancel
      if notation == "<Esc>" then
        exit_capture()
        return
      end

      -- Check for Enter -> confirm
      if notation == "<CR>" then
        if state.input_text ~= "" then
          local keybinding_str = state.input_text
          -- Clean up input state WITHOUT rendering (skip_render=true).
          -- Same as capture mode: apply keybinding before rendering.
          exit_capture(true)
          apply_captured_keybinding(keybinding_str)
          render_ui()
        end
        return
      end

      -- Backspace
      if notation == "<BS>" then
        if #state.input_text > 0 then
          state.input_text = state.input_text:sub(1, -2)
          render_ui()
        end
        return
      end

      -- Only allow printable characters and angle-bracket notation chars
      local char
      if #notation == 1 then
        char = notation
      elseif notation == "<lt>" then
        char = "<"
      elseif notation == "<Space>" then
        char = " "
      else
        -- For modifier keys like <C-x>, <A-x>, ignore them as raw input
        -- since user is typing notation text
        return
      end

      state.input_text = state.input_text .. char
      render_ui()
    end)
  end, state.on_key_ns)
end

--- Delete the keybinding for the selected script
local function delete_keybinding()
  if state.mode ~= "normal" or #state.scripts == 0 then
    return
  end

  local script = state.scripts[state.selected_index]
  if not script then
    return
  end

  if state.keybindings[script.name] then
    state.keybindings[script.name] = nil
    vim.notify("Cleared keybinding for '" .. script.name .. "'", vim.log.levels.INFO)

    -- Auto-save
    M.save()

    -- Notify callback
    if state.on_save_callback then
      state.on_save_callback(state.keybindings)
    end
  else
    vim.notify("No keybinding set for '" .. script.name .. "'", vim.log.levels.INFO)
  end

  render_ui()
end

--- Close the keybindings UI
function M.close()
  -- Clean up capture state
  stop_capture_timer()
  detach_on_key()

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.mode = "normal"
  state.captured_keys = {}
  state.input_text = ""
  state.show_help = false
end

--- Set up keymaps for the keybindings buffer
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
  vim.keymap.set("n", "c", enter_capture_mode, opts)
  vim.keymap.set("n", "<CR>", enter_capture_mode, opts)
  vim.keymap.set("n", "<Enter>", enter_capture_mode, opts)
  vim.keymap.set("n", "i", enter_input_mode, opts)
  vim.keymap.set("n", "d", delete_keybinding, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", function()
    if state.mode == "capture" or state.mode == "input" then
      exit_capture()
    else
      M.close()
    end
  end, opts)

  -- Help
  vim.keymap.set("n", "?", toggle_help, opts)
end

--- Load keybindings from config file
---@return table Loaded keybindings
function M.load()
  local keybindings = {}

  if vim.fn.filereadable(config_file_path) == 1 then
    local file = io.open(config_file_path, "r")
    if file then
      local content = file:read("*a")
      file:close()

      local ok, decoded = pcall(vim.fn.json_decode, content)
      if ok and type(decoded) == "table" then
        keybindings = decoded
      end
    end
  end

  return keybindings
end

--- Save keybindings to config file
---@return boolean Success
function M.save()
  -- Ensure directory exists
  local data_dir = vim.fn.stdpath("data")
  if vim.fn.isdirectory(data_dir) == 0 then
    vim.fn.mkdir(data_dir, "p")
  end

  local file = io.open(config_file_path, "w")
  if file then
    local ok, encoded = pcall(vim.fn.json_encode, state.keybindings)
    if ok then
      file:write(encoded)
      file:close()
      return true
    else
      file:close()
      vim.notify("Failed to encode keybindings", vim.log.levels.ERROR)
      return false
    end
  else
    vim.notify("Failed to open keybindings file for writing", vim.log.levels.ERROR)
    return false
  end
end

--- Open the keybindings configuration UI
---@param scripts table List of script configurations
---@param on_save function|nil Callback when keybindings are saved
---@param ui_config table|nil Optional UI configuration
---@return boolean Success
function M.open(scripts, on_save, ui_config)
  -- Close existing UI if open
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  end

  -- Initialize state
  state.scripts = scripts or {}
  state.selected_index = 1
  state.mode = "normal"
  state.captured_keys = {}
  state.input_text = ""
  state.show_help = false
  state.on_save_callback = on_save
  local merged_config = ui_config or {}
  -- Backwards compatibility: migrate highlight.title to highlight.header
  if merged_config.highlight and merged_config.highlight.title and not merged_config.highlight.header then
    merged_config.highlight.header = merged_config.highlight.title
    merged_config.highlight.title = nil
  end
  state.config = vim.tbl_deep_extend("force", default_config, merged_config)

  -- Load saved keybindings
  state.keybindings = M.load()

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  if not state.buf then
    vim.notify("Failed to create keybindings buffer", vim.log.levels.ERROR)
    return false
  end

  -- Set buffer options
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "termlet_keybindings"
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].modifiable = false

  -- Create window
  local win_opts = calculate_window_opts(state.config)
  state.win = vim.api.nvim_open_win(state.buf, true, win_opts)

  if not state.win then
    vim.api.nvim_buf_delete(state.buf, { force = true })
    vim.notify("Failed to create keybindings window", vim.log.levels.ERROR)
    return false
  end

  -- Set window options
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].wrap = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  -- Hide cursor block in floating window by blending Cursor with Normal
  vim.wo[state.win].winhighlight = "Cursor:Normal"

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
  render_ui()

  return true
end

--- Check if keybindings UI is currently open
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Get current keybindings
---@return table
function M.get_keybindings()
  return vim.tbl_deep_extend("force", {}, state.keybindings)
end

--- Set a keybinding programmatically
---@param script_name string Name of the script
---@param keybinding string|nil Keybinding to set (nil to clear)
---@return boolean Success
function M.set_keybinding(script_name, keybinding)
  if not script_name then
    return false
  end

  if keybinding == nil or keybinding == "" then
    state.keybindings[script_name] = nil
  else
    -- Check for conflicts
    local conflict = check_conflict(keybinding, script_name)
    if conflict then
      vim.notify(
        "Warning: Keybinding '" .. keybinding .. "' is already used by '" .. conflict .. "'",
        vim.log.levels.WARN
      )
    end
    state.keybindings[script_name] = keybinding
  end

  M.save()
  return true
end

--- Clear a keybinding programmatically
---@param script_name string Name of the script
function M.clear_keybinding(script_name)
  M.set_keybinding(script_name, nil)
end

--- Initialize keybindings from saved config
---@param scripts table List of script configurations
---@return table Loaded keybindings
function M.init(scripts)
  state.scripts = scripts or {}
  state.keybindings = M.load()
  return state.keybindings
end

--- Set config file path (mainly for testing)
---@param path string Path to config file
function M.set_config_path(path)
  config_file_path = path
end

--- Get config file path
---@return string
function M.get_config_path()
  return config_file_path
end

--- Get current UI state (for testing)
---@return table
function M.get_state()
  return {
    selected_index = state.selected_index,
    mode = state.mode,
    captured_keys = vim.tbl_deep_extend("force", {}, state.captured_keys),
    input_text = state.input_text,
    show_help = state.show_help,
    scripts_count = #state.scripts,
    keybindings = vim.tbl_deep_extend("force", {}, state.keybindings),
  }
end

--- Programmatically trigger actions (for testing)
M.actions = {
  move_up = move_up,
  move_down = move_down,
  go_to_first = go_to_first,
  go_to_last = go_to_last,
  toggle_help = toggle_help,
  enter_capture_mode = enter_capture_mode,
  enter_input_mode = enter_input_mode,
  exit_capture = exit_capture,
  delete_keybinding = delete_keybinding,
}

--- Apply a captured keybinding programmatically (for testing)
---@param keybinding_str string
function M._apply_captured_keybinding(keybinding_str)
  apply_captured_keybinding(keybinding_str)
end

--- Set captured keys directly (for testing)
---@param keys table List of key notation strings
function M._set_captured_keys(keys)
  state.captured_keys = keys or {}
end

--- Set input text directly (for testing)
---@param text string
function M._set_input_text(text)
  state.input_text = text or ""
end

--- Internal: Set keybindings directly (for testing)
---@param keybindings table
function M._set_keybindings(keybindings)
  state.keybindings = keybindings or {}
end

return M
