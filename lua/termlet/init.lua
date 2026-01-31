local M = {}

-- Load menu module
local menu = require("termlet.menu")

-- Load stacktrace module
local stacktrace = require("termlet.stacktrace")

-- Default configuration
local config = {
  scripts = {},
  root_dir = nil, -- Global root directory for script searching
  terminal = {
    height_ratio = 0.16, -- 1/6 of screen height
    width_ratio = 1.0,   -- full width
    border = "rounded",  -- string preset or table of 8 border characters
    position = "bottom", -- "bottom", "center", "top"
    highlights = {
      border = "FloatBorder",
      title = "Title",
      background = "NormalFloat",
    },
    title_format = " {icon} {name} ",
    title_icon = "",
    title_pos = "center", -- "left", "center", "right"
    show_status = false,
    status_icons = {
      running = "●",
      success = "✓",
      error = "✗",
    },
  },
  search = {
    exclude_dirs = {
      "node_modules",
      ".git",
      ".svn",
      ".hg",
      "dist",
      "build",
      "target",
      "__pycache__",
      ".cache",
      ".tox",
      ".mypy_cache",
      ".pytest_cache",
      "vendor",
      "venv",
      ".venv",
      "env",
    },
    exclude_hidden = true,
    exclude_patterns = {},
  },
  menu = {
    width_ratio = 0.6,
    height_ratio = 0.5,
    border = "rounded",
    title = " TermLet Scripts ",
  },
  stacktrace = {
    enabled = true,           -- Enable stack trace detection
    languages = {},           -- Languages to detect (empty = all)
    custom_parsers = {},      -- Custom parser definitions
    parser_order = { "custom", "builtin" }, -- Parser priority
    buffer_size = 50,         -- Lines to keep in buffer for multi-line detection
  },
  debug = false,
}

-- Store active terminal windows for cleanup
local active_terminals = {}

-- Literal string replacement to avoid Lua pattern issues with special chars
-- Replaces ALL occurrences of placeholder in str
local function replace_placeholder(str, placeholder, replacement)
  local result = str
  local search_start = 1
  while true do
    local start, finish = result:find(placeholder, search_start, true)
    if not start then
      break
    end
    result = result:sub(1, start - 1) .. replacement .. result:sub(finish + 1)
    search_start = start + #replacement
  end
  return result
end

-- Format terminal title using config placeholders
local function format_terminal_title(term_config, name, status)
  local title = term_config.title_format or " {icon} {name} "

  local icon = term_config.title_icon or ""
  title = replace_placeholder(title, "{icon}", icon)
  title = replace_placeholder(title, "{name}", name or "Terminal")

  local status_text = ""
  if term_config.show_status and status then
    local icons = term_config.status_icons or {}
    status_text = icons[status] or ""
  end
  title = replace_placeholder(title, "{status}", status_text)

  -- Trim trailing whitespace when status placeholder was empty
  title = title:gsub("%s+$", " ")

  return title
end

-- Update terminal title with exit status (extracted for testability)
local function update_terminal_status(win, exit_code)
  local term_data = active_terminals[win]
  if not term_data then
    return false
  end
  if not term_data.term_config.show_status then
    return false
  end
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local status = exit_code == 0 and "success" or "error"
  local new_title = format_terminal_title(
    term_data.term_config, term_data.name, status)
  vim.api.nvim_win_set_config(win, { title = new_title })
  return true
end

-- Expose for testing
M._format_terminal_title = format_terminal_title
M._update_terminal_status = update_terminal_status

-- Utility function for debug logging
local function debug_log(msg)
  if config.debug then
    print("[TermLet] " .. msg)
  end
end

-- Check if a directory should be excluded from search
local function should_exclude_dir(name, search_config)
  search_config = search_config or config.search

  if search_config.exclude_hidden and name:match("^%.") then
    return true
  end

  for _, excluded in ipairs(search_config.exclude_dirs or {}) do
    if name == excluded then
      return true
    end
  end

  return false
end

-- Check if a filename matches any exclusion pattern (glob-style)
local function should_exclude_file(name, search_config)
  search_config = search_config or config.search

  for _, pattern in ipairs(search_config.exclude_patterns or {}) do
    -- Escape all Lua pattern metacharacters first, then convert glob wildcards
    local lua_pattern = pattern:gsub("([%(%)%.%%%+%-%[%]%^%$])", "%%%1")
    lua_pattern = "^" .. lua_pattern:gsub("%*", ".*"):gsub("%?", ".") .. "$"
    if name:match(lua_pattern) then
      return true
    end
  end

  return false
end

-- Expose for testing
M._should_exclude_dir = should_exclude_dir
M._should_exclude_file = should_exclude_file

-- Improved terminal window creation with better error handling
function M.create_floating_terminal(opts)
  opts = opts or {}
  
  local term_config = vim.tbl_deep_extend("force", config.terminal, opts)

  -- Validate title_pos
  local valid_title_pos = { left = true, center = true, right = true }
  if term_config.title_pos and not valid_title_pos[term_config.title_pos] then
    vim.notify(
      "[TermLet] Invalid title_pos '" .. tostring(term_config.title_pos)
        .. "', falling back to 'center'. Valid values: left, center, right",
      vim.log.levels.WARN)
    term_config.title_pos = "center"
  end

  -- Validate border table length
  if type(term_config.border) == "table" and #term_config.border ~= 8 then
    vim.notify(
      "[TermLet] Custom border table must have exactly 8 characters, got "
        .. #term_config.border .. ". Falling back to 'rounded'.",
      vim.log.levels.WARN)
    term_config.border = "rounded"
  end

  -- Calculate dimensions
  local height = math.floor(vim.o.lines * term_config.height_ratio)
  local width = math.floor(vim.o.columns * term_config.width_ratio)
  
  -- Calculate position based on preference
  local row
  if term_config.position == "center" then
    row = math.floor((vim.o.lines - height) / 2)
  elseif term_config.position == "top" then
    row = 1
  else -- bottom (default)
    row = vim.o.lines - height - 2
  end
  
  local col = math.floor((vim.o.columns - width) / 2)
  
  -- Create buffer and window
  local buf = vim.api.nvim_create_buf(false, true)
  if not buf then
    vim.notify("Failed to create terminal buffer", vim.log.levels.ERROR)
    return nil
  end
  
  -- Build formatted title
  local name = opts.title or "Terminal"
  local initial_status = term_config.show_status and "running" or nil
  local title = format_terminal_title(term_config, name, initial_status)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    anchor = "NW",
    style = "minimal",
    border = term_config.border,
    title = title,
    title_pos = term_config.title_pos or "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  if not win then
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify("Failed to create terminal window", vim.log.levels.ERROR)
    return nil
  end

  -- Apply highlight groups
  local highlights = term_config.highlights
  if highlights then
    vim.api.nvim_set_option_value("winhighlight",
      "Normal:" .. (highlights.background or "NormalFloat") ..
      ",FloatBorder:" .. (highlights.border or "FloatBorder") ..
      ",FloatTitle:" .. (highlights.title or "Title"),
      { win = win })
  end

  -- Set buffer options
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "terminal", { buf = buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = buf })
  -- Store reference for cleanup (table for status title updates)
  active_terminals[win] = {
    buf = buf,
    name = name,
    term_config = term_config,
  }

  -- Auto-cleanup on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    callback = function()
      active_terminals[win] = nil
    end,
    once = true,
  })

  return buf, win
end

-- Find script by filename, searching from a specified root directory
function M.find_script_by_name(filename, root_dir, search_dirs)
  if not filename then
    debug_log("Missing filename")
    return nil
  end
  
  -- Determine root directory
  local search_root
  if root_dir then
    -- Use provided root directory
    search_root = vim.fn.expand(root_dir)
    if vim.fn.isdirectory(search_root) == 0 then
      debug_log("Specified root directory does not exist: " .. search_root)
      return nil
    end
  else
    -- Fallback to current file's directory if no root specified
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
      debug_log("No current file and no root directory specified")
      return nil
    end
    search_root = vim.fn.fnamemodify(current_file, ":h")
  end
  
  debug_log("Starting search from root: " .. search_root)
  
  -- Default search directories if none specified
  search_dirs = search_dirs or {
    "scripts", "bin", "tools", "build", ".scripts", 
    "dev", "development", "utils", "automation"
  }
  
  -- Function to recursively search for file in a directory
  local function search_in_dir(dir_path, target_file, max_depth)
    max_depth = max_depth or 5 -- Increased depth for root-based search
    if max_depth <= 0 then return nil end

    -- Check if the target file itself is excluded by patterns
    if should_exclude_file(target_file, config.search) then
      debug_log("Skipping excluded target file: " .. target_file)
      return nil
    end

    local full_path = dir_path .. "/" .. target_file
    if vim.fn.filereadable(full_path) == 1 then
      debug_log("Found script at: " .. full_path)
      return full_path
    end
    
    -- Search in subdirectories
    local handle = vim.loop.fs_scandir(dir_path)
    if handle then
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then break end
        
        if type == "directory" then
          if should_exclude_dir(name, config.search) then
            debug_log("Skipping excluded directory: " .. dir_path .. "/" .. name)
          else
            local sub_path = dir_path .. "/" .. name
            local result = search_in_dir(sub_path, target_file, max_depth - 1)
            if result then return result end
          end
        elseif type == "file" and should_exclude_file(name, config.search) then
          debug_log("Skipping excluded file: " .. dir_path .. "/" .. name)
        end
      end
    end
    
    return nil
  end
  
  -- First, try direct search in root directory
  if not should_exclude_file(filename, config.search) then
    local direct_path = search_root .. "/" .. filename
    if vim.fn.filereadable(direct_path) == 1 then
      debug_log("Found script directly at: " .. direct_path)
      return direct_path
    end
  else
    debug_log("Skipping excluded file in direct search: " .. filename)
  end
  
  -- Then search in common script directories within root
  for _, search_dir in ipairs(search_dirs) do
    local search_path = search_root .. "/" .. search_dir
    if vim.fn.isdirectory(search_path) == 1 then
      debug_log("Searching in directory: " .. search_path)
      local result = search_in_dir(search_path, filename, 5)
      if result then return result end
    end
  end
  
  -- Finally, do a recursive search from root (as fallback)
  debug_log("Doing recursive search from root: " .. search_root)
  local result = search_in_dir(search_root, filename, 5)
  if result then return result end
  
  debug_log("Script '" .. filename .. "' not found in root directory: " .. search_root)
  return nil
end

-- Backwards compatibility - find script by directory name and relative path
function M.find_script(dir_name, relative_path)
  if not dir_name or not relative_path then
    debug_log("Missing dir_name or relative_path")
    return nil
  end
  
  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    debug_log("No current file")
    return nil
  end
  
  local path = vim.fn.fnamemodify(current_file, ":h")
  debug_log("Starting search from: " .. path)
  
  local max_depth = 20
  local depth = 0
  
  while path ~= "/" and depth < max_depth do
    local folder = vim.fn.fnamemodify(path, ":t")
    debug_log("Checking: " .. path .. " (dir: " .. folder .. ")")
    
    if folder == dir_name then
      local script_path = path .. "/" .. relative_path
      debug_log("Found target folder. Looking for script at: " .. script_path)
      
      if vim.fn.filereadable(script_path) == 1 then
        debug_log("Script found at: " .. script_path)
        return script_path
      else
        debug_log("Script not found at: " .. script_path)
      end
    end
    
    path = vim.fn.fnamemodify(path, ":h")
    depth = depth + 1
  end
  
  debug_log("Directory named '" .. dir_name .. "' not found after " .. depth .. " iterations")
  return nil
end

-- Improved script execution with better error handling
local function execute_script(script)
  local full_path

  -- Determine how to find the script
  if script.filename then
    -- New method: find by filename from root directory
    full_path = M.find_script_by_name(script.filename, script.root_dir, script.search_dirs)
  elseif script.dir_name and script.relative_path then
    -- Legacy method: find by directory name and relative path
    full_path = M.find_script(script.dir_name, script.relative_path)
  else
    vim.notify("Script '" .. script.name .. "' must specify either 'filename' (with optional 'root_dir') or both 'dir_name' and 'relative_path'", vim.log.levels.ERROR)
    return false
  end

  if not full_path then
    local search_info = script.filename and ("filename: " .. script.filename .. (script.root_dir and (", root: " .. script.root_dir) or "")) or ("dir: " .. script.dir_name .. ", path: " .. script.relative_path)
    vim.notify("Script '" .. script.name .. "' not found (" .. search_info .. ")", vim.log.levels.ERROR)
    return false
  end

  local cwd = vim.fn.fnamemodify(full_path, ":h")
  local script_name = vim.fn.fnamemodify(full_path, ":t")

  -- Create terminal with script name as title
  local buf, win = M.create_floating_terminal({
    title = script.name or script_name
  })

  if not buf or not win then
    return false
  end

  -- Clear stacktrace buffer and all metadata for new execution.
  -- We use clear_all_metadata() rather than clear_metadata(buf) because Neovim
  -- can recycle buffer IDs, so stale metadata from previous buffers may persist.
  if config.stacktrace.enabled then
    stacktrace.clear_buffer()
    stacktrace.clear_all_metadata()
  end

  -- Determine command based on file extension or explicit command
  local cmd = script.cmd or ("./" .. script_name)

  debug_log("Executing: " .. cmd .. " in " .. cwd)

  -- Run the command in the terminal.
  -- Note: termopen() creates a pseudo-terminal (PTY), which merges stdout and
  -- stderr into a single stream. on_stderr is never called with termopen().
  -- All output (including stderr) arrives through on_stdout.
  local job_id = vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function(_, code)
      local msg = script.name .. " exited with code " .. code
      local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
      vim.schedule(function()
        vim.notify(msg, level)
        update_terminal_status(win, code)
        -- After process exits, scan the terminal buffer for stack traces.
        -- This is the most reliable detection method because Neovim strips
        -- ANSI escape codes from terminal buffer content read via the API,
        -- and line numbers are accurate 1-indexed values matching cursor positions.
        if config.stacktrace.enabled and buf and vim.api.nvim_buf_is_valid(buf) then
          stacktrace.clear_metadata(buf)
          stacktrace.scan_buffer_for_stacktraces(buf, cwd)
        end
      end)
    end,
    on_stdout = function(_, data)
      -- Process stdout for real-time stack trace detection.
      -- ANSI escape codes are stripped before pattern matching.
      if config.stacktrace.enabled then
        stacktrace.process_terminal_output(data, cwd, buf)
      end
      -- Call user-defined callback if provided
      if script.on_stdout then
        script.on_stdout(data)
      end
    end,
  })

  if job_id <= 0 then
    vim.notify("Failed to start " .. script.name, vim.log.levels.ERROR)
    vim.api.nvim_win_close(win, true)
    return false
  end
  vim.api.nvim_set_current_win(vim.fn.win_getid(vim.fn.winnr('#')))
  -- Enter insert mode to interact with terminal
  --vim.cmd("startinsert")
  return true
end

-- Improved setup function with validation
function M.setup(user_config)
  -- Validate and merge configuration
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- Initialize stacktrace module with configuration
  stacktrace.setup(config.stacktrace)

  -- Validate scripts configuration
  if not config.scripts or type(config.scripts) ~= "table" then
    vim.notify("Invalid scripts configuration", vim.log.levels.ERROR)
    return
  end
  
  -- Create functions for each script
  for i, script in ipairs(config.scripts) do
    -- Validate script configuration
    if not script.name then
      vim.notify("Script " .. i .. " missing required field: name", vim.log.levels.WARN)
      goto continue
    end
    
    -- Use global root_dir if script doesn't specify one
    if not script.root_dir and config.root_dir then
      script.root_dir = config.root_dir
    end
    
    -- Check for valid configuration method
    local has_filename = script.filename
    local has_legacy = script.dir_name and script.relative_path
    
    if not has_filename and not has_legacy then
      vim.notify("Script '" .. script.name .. "' must specify either 'filename' (with optional 'root_dir') or both 'dir_name' and 'relative_path'", vim.log.levels.WARN)
      goto continue
    end
    
    -- Create sanitized function name
    local function_name = "run_" .. script.name:gsub("[%s%-%.]", "_"):lower()
    
    -- Ensure function name is valid
    if not function_name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
      vim.notify("Invalid function name generated for script: " .. script.name, vim.log.levels.WARN)
      goto continue
    end
    
    -- Create the function
    M[function_name] = function()
      return execute_script(script)
    end
    
    debug_log("Created function: " .. function_name .. " for script: " .. script.name)
    
    ::continue::
  end
end

-- Utility function to close all active terminals
function M.close_all_terminals()
  for win, _ in pairs(active_terminals) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  active_terminals = {}
end

-- Improved close function with better target detection
function M.close_terminal()
  local current_win = vim.api.nvim_get_current_win()
  
  -- Check if current window is a terminal
  if active_terminals[current_win] then
    vim.api.nvim_win_close(current_win, true)
    return true
  end
  
  -- Find and close the most recently created terminal
  local wins = vim.tbl_keys(active_terminals)
  if #wins > 0 then
    local last_win = wins[#wins]
    if vim.api.nvim_win_is_valid(last_win) then
      vim.api.nvim_win_close(last_win, true)
      return true
    end
  end
  
  vim.notify("No active terminals to close", vim.log.levels.INFO)
  return false
end

-- Utility function to list available scripts
function M.list_scripts()
  if not config.scripts or #config.scripts == 0 then
    vim.notify("No scripts configured", vim.log.levels.INFO)
    return
  end
  
  local script_list = {}
  for _, script in ipairs(config.scripts) do
    local location_info
    if script.filename then
      local root = script.root_dir or config.root_dir or "current file location"
      location_info = "filename: " .. script.filename .. " (root: " .. root .. ")"
    else
      location_info = script.dir_name .. "/" .. script.relative_path
    end
    table.insert(script_list, script.name .. " (" .. location_info .. ")")
  end
  
  vim.notify("Available scripts:\n" .. table.concat(script_list, "\n"), vim.log.levels.INFO)
end

-- Backwards compatibility
M.open_floating_terminal = function()
  vim.notify("open_floating_terminal is deprecated, use create_floating_terminal", vim.log.levels.WARN)
  return M.create_floating_terminal()
end

M.close_build_window = function()
  vim.notify("close_build_window is deprecated, use close_terminal", vim.log.levels.WARN)
  return M.close_terminal()
end

-- Open the interactive script menu
function M.open_menu()
  if not config.scripts or #config.scripts == 0 then
    vim.notify("No scripts configured", vim.log.levels.INFO)
    return false
  end

  return menu.open(config.scripts, execute_script, config.menu)
end

-- Close the menu if open
function M.close_menu()
  menu.close()
end

-- Check if menu is currently open
function M.is_menu_open()
  return menu.is_open()
end

-- Toggle the menu open/closed
function M.toggle_menu()
  if menu.is_open() then
    menu.close()
  else
    M.open_menu()
  end
end

-- Stacktrace module access
M.stacktrace = stacktrace

-- Get file info at cursor position in terminal buffer
function M.get_stacktrace_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  return stacktrace.find_nearest_metadata(buf, line)
end

-- Jump to file referenced in stack trace at cursor
function M.goto_stacktrace()
  local file_info = M.get_stacktrace_at_cursor()
  if file_info and file_info.path then
    -- Check if file exists
    if vim.fn.filereadable(file_info.path) == 1 then
      -- If the current window is a floating terminal, close it first and find
      -- a regular (non-floating) window to open the file in.
      local current_win = vim.api.nvim_get_current_win()
      local win_config = vim.api.nvim_win_get_config(current_win)
      if win_config.relative and win_config.relative ~= "" then
        -- We're in a floating window — close it
        vim.api.nvim_win_close(current_win, true)
        -- Try to find a non-floating window to switch to
        local found_regular_win = false
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local wc = vim.api.nvim_win_get_config(win)
          if (not wc.relative or wc.relative == "") and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_current_win(win)
            found_regular_win = true
            break
          end
        end
        if not found_regular_win then
          -- No regular window found, create a new split
          vim.cmd("new")
        end
      end

      vim.cmd("edit " .. vim.fn.fnameescape(file_info.path))
      if file_info.line then
        vim.api.nvim_win_set_cursor(0, { file_info.line, (file_info.column or 1) - 1 })
      end
      return true
    else
      vim.notify("File not found: " .. file_info.path, vim.log.levels.WARN)
      return false
    end
  end
  vim.notify("No stack trace reference found at cursor", vim.log.levels.INFO)
  return false
end


return M
