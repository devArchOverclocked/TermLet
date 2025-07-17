local M = {}

-- Default configuration
local config = {
  scripts = {},
  root_dir = nil, -- Global root directory for script searching
  terminal = {
    height_ratio = 0.16, -- 1/6 of screen height
    width_ratio = 1.0,   -- full width
    border = "rounded",
    position = "bottom", -- "bottom", "center", "top"
  },
  debug = false,
}

-- Store active terminal windows for cleanup
local active_terminals = {}

-- Utility function for debug logging
local function debug_log(msg)
  if config.debug then
    print("[TermLet] " .. msg)
  end
end

-- Improved terminal window creation with better error handling
function M.create_floating_terminal(opts)
  opts = opts or {}
  
  local term_config = vim.tbl_deep_extend("force", config.terminal, opts)
  
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
  
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    anchor = "NW",
    style = "minimal",
    border = term_config.border,
    title = opts.title or "Terminal",
    title_pos = "center",
  }
  
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  if not win then
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify("Failed to create terminal window", vim.log.levels.ERROR)
    return nil
  end
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "terminal")
  vim.api.nvim_buf_set_option(buf, "buflisted", false)
  -- Store reference for cleanup
  active_terminals[win] = buf
  
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
        
        if type == "directory" and not name:match("^%.") and name ~= "node_modules" and name ~= ".git" then
          local sub_path = dir_path .. "/" .. name
          local result = search_in_dir(sub_path, target_file, max_depth - 1)
          if result then return result end
        end
      end
    end
    
    return nil
  end
  
  -- First, try direct search in root directory
  local direct_path = search_root .. "/" .. filename
  if vim.fn.filereadable(direct_path) == 1 then
    debug_log("Found script directly at: " .. direct_path)
    return direct_path
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
  
  -- Determine command based on file extension or explicit command
  local cmd = script.cmd or ("./" .. script_name)
  
  debug_log("Executing: " .. cmd .. " in " .. cwd)
  
  -- Run the command in the terminal
  local job_id = vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function(_, code)
      local msg = script.name .. " exited with code " .. code
      local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
      vim.schedule(function()
        vim.notify(msg, level)
      end)
    end,
    on_stdout = function(_, data)
      -- Optional: Handle stdout if needed
      if script.on_stdout then
        script.on_stdout(data)
      end
    end,
    on_stderr = function(_, data)
      -- Optional: Handle stderr if needed
      if script.on_stderr then
        script.on_stderr(data)
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
  for win, buf in pairs(active_terminals) do
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

return M
