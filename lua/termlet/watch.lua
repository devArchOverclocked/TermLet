-- TermLet Watch Module
-- Provides file watching with automatic script re-execution on changes

local M = {}

-- Active watchers keyed by script name
-- Each entry: { handle = uv_fs_event, timer = uv_timer, script = table, callback = function, generation = number }
local watchers = {}

-- Generation counter to detect stale callbacks after watcher replacement
local generation = 0

-- Default watch configuration
local default_watch_config = {
  enabled = false,
  patterns = {},
  exclude = {},
  debounce = 500, -- milliseconds
}

--- Convert a glob pattern to a Lua pattern for matching
--- Supports *, **, and ? wildcards
---@param glob string Glob pattern (e.g., "**/*.lua")
---@return string Lua pattern
function M.glob_to_pattern(glob)
  -- Step 1: Replace ** and * and ? with placeholders before escaping
  local parts = {}
  local i = 1
  local len = #glob
  while i <= len do
    if glob:sub(i, i + 1) == "**" then
      table.insert(parts, { type = "doublestar" })
      i = i + 2
      -- Skip trailing / after ** (e.g., **/ in **/node_modules/**)
      if i <= len and glob:sub(i, i) == "/" then
        i = i + 1
      end
    elseif glob:sub(i, i) == "*" then
      table.insert(parts, { type = "star" })
      i = i + 1
    elseif glob:sub(i, i) == "?" then
      table.insert(parts, { type = "question" })
      i = i + 1
    else
      -- Collect literal characters
      local start = i
      while i <= len and glob:sub(i, i) ~= "*" and glob:sub(i, i) ~= "?" do
        i = i + 1
      end
      table.insert(parts, { type = "literal", value = glob:sub(start, i - 1) })
    end
  end

  -- Step 2: Build the Lua pattern from parts
  local result = {}
  for _, part in ipairs(parts) do
    if part.type == "doublestar" then
      table.insert(result, ".*")
    elseif part.type == "star" then
      table.insert(result, "[^/]*")
    elseif part.type == "question" then
      table.insert(result, "[^/]")
    elseif part.type == "literal" then
      -- Escape Lua pattern metacharacters in literal text
      local escaped = part.value:gsub("([%(%)%.%%%+%-%[%]%^%$])", "%%%1")
      table.insert(result, escaped)
    end
  end

  return "^" .. table.concat(result) .. "$"
end

--- Check if a file path matches any of the given glob patterns
---@param filepath string File path to check
---@param patterns table List of glob patterns
---@return boolean True if filepath matches any pattern
function M.matches_patterns(filepath, patterns)
  if not patterns or #patterns == 0 then
    return true -- No patterns means match everything
  end

  for _, glob in ipairs(patterns) do
    local pattern = M.glob_to_pattern(glob)
    if filepath:match(pattern) then
      return true
    end
  end

  return false
end

--- Check if a file path matches any exclude pattern
---@param filepath string File path to check
---@param exclude table List of exclude glob patterns
---@return boolean True if filepath should be excluded
function M.matches_exclude(filepath, exclude)
  if not exclude or #exclude == 0 then
    return false
  end

  for _, glob in ipairs(exclude) do
    local pattern = M.glob_to_pattern(glob)
    if filepath:match(pattern) then
      return true
    end
  end

  return false
end

--- Check if a file change should trigger a re-run
---@param filepath string Changed file path
---@param watch_config table Watch configuration with patterns and exclude
---@return boolean True if the change should trigger re-run
function M.should_trigger(filepath, watch_config)
  if not filepath or filepath == "" then
    return false
  end

  -- Check exclude patterns first
  if M.matches_exclude(filepath, watch_config.exclude) then
    return false
  end

  -- Check include patterns
  return M.matches_patterns(filepath, watch_config.patterns)
end

--- Recursively collect directories to watch under a root path
--- Respects exclude patterns to skip directories like node_modules
---@param root string Root directory path
---@param exclude table List of exclude glob patterns
---@param max_depth number Maximum recursion depth
---@return table List of directory paths
function M.collect_watch_dirs(root, exclude, max_depth)
  max_depth = max_depth or 10
  local dirs = { root }

  local function scan(dir_path, depth)
    if depth > max_depth then
      return
    end

    local handle = vim.uv.fs_scandir(dir_path)
    if not handle then
      return
    end

    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end

      if type == "directory" then
        -- Skip hidden directories
        if name:sub(1, 1) == "." then
          goto continue
        end

        local full_path = dir_path .. "/" .. name

        -- Check if directory matches exclude patterns
        local rel_path = full_path:sub(#root + 2) -- relative path from root
        if not M.matches_exclude(rel_path, exclude) and not M.matches_exclude(name, exclude) then
          table.insert(dirs, full_path)
          scan(full_path, depth + 1)
        end

        ::continue::
      end
    end
  end

  scan(root, 1)
  return dirs
end

--- Start watching files for a script
---@param script_name string Name of the script
---@param script table Full script configuration
---@param watch_config table Watch configuration (patterns, exclude, debounce)
---@param root_dir string Root directory to watch
---@param callback function Function to call when files change (receives script)
---@return boolean True if watcher started successfully
function M.start(script_name, script, watch_config, root_dir, callback)
  -- Stop any existing watcher for this script
  M.stop(script_name)

  if not root_dir or vim.fn.isdirectory(root_dir) == 0 then
    vim.notify("[TermLet Watch] Root directory not found: " .. tostring(root_dir), vim.log.levels.ERROR)
    return false
  end

  local config = vim.tbl_deep_extend("force", default_watch_config, watch_config or {})
  local debounce_ms = config.debounce or 500

  -- Collect directories to watch
  local dirs = M.collect_watch_dirs(root_dir, config.exclude)

  if #dirs == 0 then
    vim.notify("[TermLet Watch] No directories to watch", vim.log.levels.WARN)
    return false
  end

  -- Create debounce timer
  local timer = vim.uv.new_timer()
  local handles = {}

  -- Assign a unique generation so stale callbacks from replaced watchers are ignored
  generation = generation + 1
  local my_generation = generation

  -- Track the watcher entry
  watchers[script_name] = {
    handles = handles,
    timer = timer,
    script = script,
    callback = callback,
    config = config,
    root_dir = root_dir,
    generation = my_generation,
  }

  -- Create fs_event watchers for each directory
  for _, dir in ipairs(dirs) do
    local handle = vim.uv.new_fs_event()
    if handle then
      local ok, err = handle:start(dir, {}, function(err2, filename, _events)
        if err2 then
          return
        end
        if not filename then
          return
        end

        -- Build relative path for pattern matching
        local rel_path = filename
        -- On some systems, filename is relative to the watched dir
        -- Construct a path relative to root for pattern matching
        local full_rel = dir:sub(#root_dir + 2)
        if full_rel and full_rel ~= "" then
          rel_path = full_rel .. "/" .. filename
        end

        -- Check if this file change should trigger a re-run
        if not M.should_trigger(rel_path, config) then
          return
        end

        -- Debounce: reset timer on each qualifying change
        if timer and timer:is_active() then
          timer:stop()
        end

        timer:start(debounce_ms, 0, function()
          vim.schedule(function()
            -- Check generation to ignore stale callbacks from replaced watchers
            local w = watchers[script_name]
            if w and w.generation == my_generation and w.callback then
              vim.notify("[TermLet Watch] Re-running '" .. script_name .. "' (changed: " .. rel_path .. ")")
              w.callback(w.script)
            end
          end)
        end)
      end)

      if ok then
        table.insert(handles, handle)
      else
        handle:close()
        vim.notify("[TermLet Watch] Failed to watch " .. dir .. ": " .. tostring(err), vim.log.levels.WARN)
      end
    end
  end

  if #handles == 0 then
    timer:close()
    watchers[script_name] = nil
    vim.notify("[TermLet Watch] Failed to create any file watchers", vim.log.levels.ERROR)
    return false
  end

  vim.notify("[TermLet Watch] Watching " .. #handles .. " directories for '" .. script_name .. "'", vim.log.levels.INFO)

  return true
end

--- Stop watching files for a script
---@param script_name string Name of the script
---@return boolean True if a watcher was stopped
function M.stop(script_name)
  local watcher = watchers[script_name]
  if not watcher then
    return false
  end

  -- Stop and close the debounce timer
  if watcher.timer then
    if watcher.timer:is_active() then
      watcher.timer:stop()
    end
    if not watcher.timer:is_closing() then
      watcher.timer:close()
    end
  end

  -- Stop and close all fs_event handles
  if watcher.handles then
    for _, handle in ipairs(watcher.handles) do
      if handle and not handle:is_closing() then
        handle:stop()
        handle:close()
      end
    end
  end

  watchers[script_name] = nil
  vim.notify("[TermLet Watch] Stopped watching '" .. script_name .. "'", vim.log.levels.INFO)
  return true
end

--- Stop all active watchers
---@return number Number of watchers stopped
function M.stop_all()
  -- Collect keys first to avoid modifying table during pairs() iteration
  local names = {}
  for name, _ in pairs(watchers) do
    table.insert(names, name)
  end
  for _, name in ipairs(names) do
    M.stop(name)
  end
  return #names
end

--- Toggle watch mode for a script
---@param script_name string Name of the script
---@param script table Full script configuration
---@param watch_config table Watch configuration
---@param root_dir string Root directory to watch
---@param callback function Function to call when files change
---@return boolean New watch state (true = watching, false = stopped)
function M.toggle(script_name, script, watch_config, root_dir, callback)
  if M.is_watching(script_name) then
    M.stop(script_name)
    return false
  else
    return M.start(script_name, script, watch_config, root_dir, callback)
  end
end

--- Check if a script is currently being watched
---@param script_name string Name of the script
---@return boolean True if the script has an active watcher
function M.is_watching(script_name)
  return watchers[script_name] ~= nil
end

--- Get list of all scripts currently being watched
---@return table List of script names being watched
function M.get_watched_scripts()
  local names = {}
  for name, _ in pairs(watchers) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

--- Get watch status summary for display
---@return table Map of script_name -> { watching = bool, dir_count = number }
function M.get_status()
  local status = {}
  for name, watcher in pairs(watchers) do
    status[name] = {
      watching = true,
      dir_count = watcher.handles and #watcher.handles or 0,
      root_dir = watcher.root_dir,
    }
  end
  return status
end

--- Generate a title suffix for watch mode indicator
---@param script_name string Name of the script
---@return string Title suffix (e.g., " 👁" or "")
function M.get_title_indicator(script_name)
  if M.is_watching(script_name) then
    return " [watch]"
  end
  return ""
end

--- Get internal state (for testing)
---@return table
function M.get_state()
  local state = {}
  for name, watcher in pairs(watchers) do
    state[name] = {
      config = watcher.config,
      root_dir = watcher.root_dir,
      handle_count = watcher.handles and #watcher.handles or 0,
    }
  end
  return state
end

--- Reset all state (for testing)
function M._reset()
  M.stop_all()
  watchers = {}
  generation = 0
end

return M
