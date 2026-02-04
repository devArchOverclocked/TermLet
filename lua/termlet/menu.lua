-- TermLet Menu Module
-- Provides an interactive Mason-like popup menu for browsing and executing scripts

local M = {}

-- Menu state
local state = {
  buf = nil,
  win = nil,
  scripts = {},
  filtered_scripts = {},
  selected_index = 1,
  search_query = "",
  search_mode = false,
  show_help = false,
  config = nil,
  execute_callback = nil,
}

-- Default menu configuration
local default_config = {
  width_ratio = 0.6,
  height_ratio = 0.6,
  border = "rounded",
  title = " TermLet Scripts ",
  highlight = {
    selected = "CursorLine",
    header = "Title",
    help = "Comment",
    search = "Search",
    description = "Comment",
    counter = "NonText",
  },
}

-- Highlight namespace
local ns_id = vim.api.nvim_create_namespace("termlet_menu")

--- Calculate window dimensions and position
---@param config table Menu configuration
---@return table Window options for nvim_open_win
local function calculate_window_opts(config)
  local width = math.floor(vim.o.columns * config.width_ratio)
  local height = math.floor(vim.o.lines * config.height_ratio)

  -- Minimum dimensions
  width = math.max(width, 50)
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
    footer = " Enter Run  / Search  ? Help  q Close ",
    footer_pos = "center",
  }
end

--- Format a script entry for display
---@param script table Script configuration
---@param index number Index in the list
---@param is_selected boolean Whether this script is selected
---@param width number Available width for the line
---@return string Formatted line
---@return table[] Inline highlights for this line {col_start, col_end, group}
local function format_script_line(script, index, is_selected, width, total_count)
  local pointer = is_selected and "  " or "   "
  local idx_str = string.format(" %d. ", index)
  local name = script.name or "unnamed"
  local description = script.description or ""

  -- Use fixed column widths for consistent alignment across all rows
  local name_width = math.floor(width * 0.35)
  -- Calculate fixed prefix width: pointer(3) + max idx_str width
  local max_idx_width = #string.format(" %d. ", total_count)
  local prefix_pad = max_idx_width - #idx_str
  local padded_name = string.format("%-" .. name_width .. "s", name:sub(1, name_width))

  local line = pointer .. idx_str .. string.rep(" ", prefix_pad) .. padded_name

  local inline_hl = {}

  if description ~= "" then
    local sep = "  "
    local desc_width = width - #line - #sep - 2
    if desc_width > 0 then
      local truncated_desc = description:sub(1, desc_width)
      local desc_start = #line + #sep
      line = line .. sep .. truncated_desc
      table.insert(inline_hl, { col_start = desc_start, col_end = #line, group = "description" })
    end
  end

  -- Pad to full width for consistent highlight background
  if #line < width then
    line = line .. string.rep(" ", width - #line)
  end

  return line, inline_hl
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
    "   Enter           Run selected script",
    "   /               Search / filter scripts",
    "   Esc             Cancel search / close",
    "   q               Close menu",
    "   ?               Toggle this help",
    "",
  }
end

--- Filter scripts based on search query
---@param scripts table List of scripts
---@param query string Search query
---@return table Filtered scripts
local function filter_scripts(scripts, query)
  if query == "" then
    return scripts
  end

  local filtered = {}
  local lower_query = query:lower()

  for _, script in ipairs(scripts) do
    local name = (script.name or ""):lower()
    local description = (script.description or ""):lower()

    if name:find(lower_query, 1, true) or description:find(lower_query, 1, true) then
      table.insert(filtered, script)
    end
  end

  return filtered
end

--- Render the menu content
local function render_menu()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local win_opts = calculate_window_opts(state.config)
  local width = win_opts.width - 2 -- Account for borders

  -- Clear existing content and highlights
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

  local lines = {}
  local highlights = {}

  -- Add search bar if in search mode
  if state.search_mode then
    table.insert(lines, "")
    local search_line = "   / " .. state.search_query .. "█"
    table.insert(lines, search_line)
    table.insert(lines, "")
    table.insert(highlights, { line = 1, group = state.config.highlight.search })
  else
    table.insert(lines, "")
  end

  -- Add script list or help
  if state.show_help then
    for _, help_line in ipairs(get_help_lines(width)) do
      table.insert(lines, help_line)
      table.insert(highlights, { line = #lines - 1, group = state.config.highlight.help })
    end
  else
    if #state.filtered_scripts == 0 then
      table.insert(lines, "")
      if state.search_query ~= "" then
        table.insert(lines, "   No scripts match your search")
      else
        table.insert(lines, "   No scripts configured")
      end
      table.insert(lines, "")
    else
      -- Column header - align with data row prefix (pointer + idx_str + padding)
      local name_width = math.floor(width * 0.35)
      local max_idx_width = #string.format(" %d. ", #state.filtered_scripts)
      -- Header prefix: "   " (3, matches unselected pointer) + spaces for idx column
      local header_prefix = "   " .. string.rep(" ", max_idx_width)
      local header = header_prefix .. string.format("%-" .. name_width .. "s", "Script") .. "  " .. "Description"
      table.insert(lines, header)
      table.insert(highlights, { line = #lines - 1, group = state.config.highlight.header })

      local sep_line = "   " .. string.rep("─", width - 4)
      table.insert(lines, sep_line)
      table.insert(highlights, { line = #lines - 1, group = state.config.highlight.header })

      -- Script entries
      local total_count = #state.filtered_scripts
      for i, script in ipairs(state.filtered_scripts) do
        local is_selected = (i == state.selected_index)
        local line, inline_hl = format_script_line(script, i, is_selected, width, total_count)
        table.insert(lines, line)

        local line_idx = #lines - 1
        if is_selected then
          table.insert(highlights, { line = line_idx, group = state.config.highlight.selected })
        end

        -- Apply inline description highlights (only when not selected, to avoid overriding)
        if not is_selected then
          for _, ihl in ipairs(inline_hl) do
            table.insert(highlights, {
              line = line_idx,
              col_start = ihl.col_start,
              col_end = ihl.col_end,
              group = state.config.highlight[ihl.group] or state.config.highlight.description,
            })
          end
        end
      end
    end

    -- Counter line at the bottom
    if #state.filtered_scripts > 0 then
      table.insert(lines, "")
      local counter_text
      if state.search_query ~= "" then
        counter_text = string.format("   %d of %d scripts (filtered)", #state.filtered_scripts, #state.scripts)
      else
        counter_text = string.format("   %d scripts", #state.scripts)
      end
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
  if state.show_help or #state.filtered_scripts == 0 then
    return
  end

  state.selected_index = state.selected_index - 1
  if state.selected_index < 1 then
    state.selected_index = #state.filtered_scripts
  end
  render_menu()
end

--- Move selection down
local function move_down()
  if state.show_help or #state.filtered_scripts == 0 then
    return
  end

  state.selected_index = state.selected_index + 1
  if state.selected_index > #state.filtered_scripts then
    state.selected_index = 1
  end
  render_menu()
end

--- Go to first item
local function go_to_first()
  if state.show_help or #state.filtered_scripts == 0 then
    return
  end
  state.selected_index = 1
  render_menu()
end

--- Go to last item
local function go_to_last()
  if state.show_help or #state.filtered_scripts == 0 then
    return
  end
  state.selected_index = #state.filtered_scripts
  render_menu()
end

--- Execute the selected script
local function execute_selected()
  if state.show_help then
    state.show_help = false
    render_menu()
    return
  end

  if #state.filtered_scripts == 0 then
    return
  end

  local selected_script = state.filtered_scripts[state.selected_index]
  if not selected_script then
    return
  end

  -- Close menu first
  M.close()

  -- Execute the script via callback
  if state.execute_callback then
    vim.schedule(function()
      state.execute_callback(selected_script)
    end)
  end
end

--- Enter search mode
local function enter_search_mode()
  state.search_mode = true
  state.search_query = ""
  render_menu()
end

--- Exit search mode
local function exit_search_mode()
  state.search_mode = false
  render_menu()
end

--- Handle search input
---@param char string Character typed
local function handle_search_input(char)
  if char == "<BS>" or char == "\b" then
    -- Backspace
    if #state.search_query > 0 then
      state.search_query = state.search_query:sub(1, -2)
    end
  elseif char == "<CR>" or char == "\r" or char == "\n" then
    -- Enter - confirm search and exit search mode
    state.search_mode = false
  elseif char == "<Esc>" then
    -- Escape - cancel search
    state.search_query = ""
    state.search_mode = false
    state.filtered_scripts = state.scripts
    state.selected_index = 1
  elseif #char == 1 and char:match("[%w%s%p]") then
    -- Regular character
    state.search_query = state.search_query .. char
  end

  -- Update filtered list
  state.filtered_scripts = filter_scripts(state.scripts, state.search_query)
  state.selected_index = math.min(state.selected_index, math.max(1, #state.filtered_scripts))

  render_menu()
end

--- Toggle help display
local function toggle_help()
  state.show_help = not state.show_help
  render_menu()
end

--- Close the menu
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.search_mode = false
  state.search_query = ""
  state.show_help = false
end

--- Set up keymaps for the menu buffer
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
  vim.keymap.set("n", "<CR>", execute_selected, opts)
  vim.keymap.set("n", "<Enter>", execute_selected, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", function()
    if state.search_mode then
      handle_search_input("<Esc>")
    else
      M.close()
    end
  end, opts)

  -- Search
  vim.keymap.set("n", "/", function()
    enter_search_mode()
    -- Set up character input handler for search
    vim.api.nvim_buf_set_keymap(buf, "n", "<BS>", "", {
      noremap = true,
      silent = true,
      callback = function()
        if state.search_mode then
          handle_search_input("<BS>")
        end
      end,
    })
  end, opts)

  -- Help
  vim.keymap.set("n", "?", toggle_help, opts)

  -- Character input for search mode
  -- We use a simple approach: intercept all printable characters when in search mode
  for i = 32, 126 do
    local char = string.char(i)
    -- Skip special characters that have other mappings
    if char ~= "j" and char ~= "k" and char ~= "q" and char ~= "/" and char ~= "?" and char ~= "G" then
      vim.keymap.set("n", char, function()
        if state.search_mode then
          handle_search_input(char)
        end
        -- For char == "g": wait for second 'g' for gg command
        -- This is handled by the default gg mapping
      end, opts)
    else
      -- For mapped keys, check search mode first
      local original_fn
      if char == "j" then
        original_fn = move_down
      elseif char == "k" then
        original_fn = move_up
      elseif char == "q" then
        original_fn = M.close
      elseif char == "/" then
        original_fn = enter_search_mode
      elseif char == "?" then
        original_fn = toggle_help
      elseif char == "G" then
        original_fn = go_to_last
      end

      vim.keymap.set("n", char, function()
        if state.search_mode then
          handle_search_input(char)
        else
          original_fn()
        end
      end, opts)
    end
  end
end

--- Open the interactive script menu
---@param scripts table List of script configurations
---@param execute_callback function Callback to execute a script
---@param menu_config table|nil Optional menu configuration
function M.open(scripts, execute_callback, menu_config)
  -- Close existing menu if open
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  end

  -- Initialize state
  state.scripts = scripts or {}
  state.filtered_scripts = state.scripts
  state.selected_index = 1
  state.search_query = ""
  state.search_mode = false
  state.show_help = false
  state.execute_callback = execute_callback
  local merged_config = menu_config or {}
  -- Backwards compatibility: migrate highlight.title to highlight.header
  if merged_config.highlight and merged_config.highlight.title and not merged_config.highlight.header then
    merged_config.highlight.header = merged_config.highlight.title
    merged_config.highlight.title = nil
  end
  state.config = vim.tbl_deep_extend("force", default_config, merged_config)

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  if not state.buf then
    vim.notify("Failed to create menu buffer", vim.log.levels.ERROR)
    return false
  end

  -- Set buffer options
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "termlet_menu"
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].modifiable = false

  -- Create window
  local win_opts = calculate_window_opts(state.config)
  state.win = vim.api.nvim_open_win(state.buf, true, win_opts)

  if not state.win then
    vim.api.nvim_buf_delete(state.buf, { force = true })
    vim.notify("Failed to create menu window", vim.log.levels.ERROR)
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
  render_menu()

  return true
end

--- Check if menu is currently open
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Get current menu state (for testing)
---@return table
function M.get_state()
  return {
    selected_index = state.selected_index,
    search_query = state.search_query,
    search_mode = state.search_mode,
    show_help = state.show_help,
    filtered_count = #state.filtered_scripts,
    total_count = #state.scripts,
  }
end

--- Programmatically trigger actions (for testing)
M.actions = {
  move_up = move_up,
  move_down = move_down,
  go_to_first = go_to_first,
  go_to_last = go_to_last,
  execute_selected = execute_selected,
  enter_search_mode = enter_search_mode,
  exit_search_mode = exit_search_mode,
  handle_search_input = handle_search_input,
  toggle_help = toggle_help,
}

return M
