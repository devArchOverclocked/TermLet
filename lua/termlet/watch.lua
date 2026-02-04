-- TermLet Watch Module
-- Provides file watching capabilities to auto-rerun scripts when files change.
-- Uses vim.loop (libuv) fs_event watchers for efficient file system monitoring.

local M = {}

-- Watch state per script
-- script_name -> { watcher_handles = {}, timer = nil, enabled = bool, config = table, script = table }
local watchers = {}

-- Default watch configuration
local default_watch_config = {
  enabled = false,
  patterns = {}, -- glob patterns to watch (e.g., {"*.lua", "*.py"})
  exclude = { "node_modules", ".git", ".svn", "dist", "build", "target", "__pycache__" },
  debounce = 500, -- ms delay before re-running after a file change
}

-- Module-level callback for executing scripts (set by init.lua)
local execute_callback = nil

-- Module-level debug logger (set by init.lua)
local debug_log = function() end

--- Convert a glob pattern to a Lua pattern for matching.
--- Supports: * (any non-/ chars), ? (single non-/ char), ** (recursive dir match).
--- Processes character by character to avoid Lua pattern metacharacter conflicts.
--- Note: Does NOT support {a,b} brace expansion. Use separate patterns instead
--- (e.g., {"*.lua", "*.py"} rather than "*.{lua,py}").
---@param glob string Glob pattern like "*.lua" or "src/**/*.py"
---@return string Lua pattern
local function glob_to_pattern(glob)
  local result = {}
  local i = 1
  local len = #glob
  -- Characters that are Lua pattern metacharacters (must be escaped with %)
  local lua_magic = {
    ["("] = true,
    [")"] = true,
    ["."] = true,
    ["%"] = true,
    ["+"] = true,
    ["-"] = true,
    ["["] = true,
    ["]"] = true,
    ["^"] = true,
    ["$"] = true,
  }

  while i <= len do
    local c = glob:sub(i, i)
    if c == "*" and glob:sub(i + 1, i + 1) == "*" then
      -- ** = match anything including /
      table.insert(result, ".*")
      i = i + 2
      -- Skip trailing / after ** (e.g., **/ -> just .*)
      if i <= len and glob:sub(i, i) == "/" then
        i = i + 1
      end
    elseif c == "*" then
      -- * = match any chars except /
      table.insert(result, "[^/]*")
      i = i + 1
    elseif c == "?" then
      -- ? = match single char except /
      table.insert(result, "[^/]")
      i = i + 1
    elseif lua_magic[c] then
      -- Escape Lua pattern metacharacter
      table.insert(result, "%" .. c)
      i = i + 1
    else
      table.insert(result, c)
      i = i + 1
    end
  end

  return "^" .. table.concat(result) .. "$"
end

--- Check if a file path matches any of the given glob patterns
---@param filepath string File path relative to root
---@param patterns table List of glob patterns
---@return boolean
local function matches_patterns(filepath, patterns)
  if not patterns or #patterns == 0 then
    return false
  end
  for _, glob in ipairs(patterns) do
    local pattern = glob_to_pattern(glob)
    if filepath:match(pattern) then
      return true
    end
  end
  return false
end

--- Check if a path should be excluded from watching.
--- Compares each path component exactly against the exclude list,
--- so "build" excludes "build/" but not "rebuild/" or "build-tools/".
---@param path string Path or path component to check
---@param exclude table List of directory names to exclude
---@return boolean
local function is_excluded(path, exclude)
  if not exclude or #exclude == 0 then
    return false
  end
  -- Build a lookup set for O(1) checks
  local exclude_set = {}
  for _, excluded in ipairs(exclude) do
    exclude_set[excluded] = true
  end
  -- Split path on "/" and check each component
  for component in path:gmatch("[^/]+") do
    if exclude_set[component] then
      return true
    end
  end
  return false
end

--- Recursively collect directories to watch from a root path
---@param root string Root directory
---@param exclude table List of directories to exclude
---@param max_depth number Maximum recursion depth
---@return table List of directory paths
local function collect_watch_dirs(root, exclude, max_depth)
  max_depth = max_depth or 10
  local dirs = { root }

  local function scan(dir, depth)
    if depth > max_depth then
      return
    end
    local handle = vim.loop.fs_scandir(dir)
    if not handle then
      return
    end
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end
      if type == "directory" and not is_excluded(name, exclude) then
        local full_path = dir .. "/" .. name
        table.insert(dirs, full_path)
        scan(full_path, depth + 1)
      end
    end
  end

  scan(root, 1)
  return dirs
end

--- Stop all watchers for a script
---@param script_name string
local function stop_watchers(script_name)
  local w = watchers[script_name]
  if not w then
    return
  end

  -- Stop the debounce timer
  if w.timer then
    w.timer:stop()
    if not w.timer:is_closing() then
      w.timer:close()
    end
    w.timer = nil
  end

  -- Stop all fs_event handles
  for _, handle in ipairs(w.watcher_handles or {}) do
    if handle and not handle:is_closing() then
      handle:stop()
      handle:close()
    end
  end
  w.watcher_handles = {}
end

--- Start watching files for a script
---@param script_name string Name of the script
---@param script table Script configuration (passed to execute_callback)
---@param watch_config table Watch configuration
---@param root_dir string Root directory to watch from
---@return boolean success
function M.start(script_name, script, watch_config, root_dir)
  if not script_name or not root_dir then
    return false
  end

  -- Stop existing watchers for this script
  if watchers[script_name] then
    stop_watchers(script_name)
  end

  local cfg = vim.tbl_deep_extend("force", default_watch_config, watch_config or {})

  if not cfg.patterns or #cfg.patterns == 0 then
    vim.notify("[TermLet] Watch mode for '" .. script_name .. "' has no patterns configured", vim.log.levels.WARN)
    return false
  end

  -- Expand root_dir
  local expanded_root = vim.fn.expand(root_dir)
  if vim.fn.isdirectory(expanded_root) == 0 then
    vim.notify("[TermLet] Watch root directory does not exist: " .. expanded_root, vim.log.levels.ERROR)
    return false
  end

  local w = {
    watcher_handles = {},
    timer = nil,
    enabled = true,
    config = cfg,
    script = script,
    root_dir = expanded_root,
  }

  -- Create debounce timer
  w.timer = vim.loop.new_timer()

  -- Collect directories to watch
  local dirs = collect_watch_dirs(expanded_root, cfg.exclude)

  debug_log("Watch: monitoring " .. #dirs .. " directories for '" .. script_name .. "'")

  for _, dir in ipairs(dirs) do
    local handle = vim.loop.new_fs_event()
    if handle then
      local ok, err = handle:start(dir, {}, function(watch_err, filename)
        if watch_err then
          debug_log("Watch error: " .. watch_err)
          return
        end
        if not filename then
          return
        end

        -- Check if the watcher is still enabled
        local watcher_state = watchers[script_name]
        if not watcher_state or not watcher_state.enabled then
          return
        end

        -- Build relative path for pattern matching.
        -- libuv fs_event may return just a basename or a relative path depending
        -- on the platform. Extract the basename for non-recursive pattern matching
        -- and use the full filename for exclusion checks on path components.
        local rel_path = filename
        local basename = filename:match("[^/]+$") or filename

        -- Check exclusions on the full path (checks each component)
        if is_excluded(rel_path, cfg.exclude) then
          return
        end

        -- Check if file matches watch patterns.
        -- Try matching against both the full relative path and just the basename,
        -- so that patterns like "*.lua" work reliably even if libuv returns a path.
        if not matches_patterns(rel_path, cfg.patterns) and not matches_patterns(basename, cfg.patterns) then
          return
        end

        debug_log("Watch: file changed - " .. rel_path .. " (script: " .. script_name .. ")")

        -- Debounce: restart timer on each change
        if watcher_state.timer and not watcher_state.timer:is_closing() then
          watcher_state.timer:stop()
          watcher_state.timer:start(cfg.debounce, 0, function()
            vim.schedule(function()
              -- Re-check that watching is still enabled
              local ws = watchers[script_name]
              if ws and ws.enabled and execute_callback then
                vim.notify(
                  "[TermLet] Watch: re-running '" .. script_name .. "' (file changed: " .. rel_path .. ")",
                  vim.log.levels.INFO
                )
                execute_callback(ws.script)
              end
            end)
          end)
        end
      end)

      if ok then
        table.insert(w.watcher_handles, handle)
      else
        debug_log("Watch: failed to start watcher for " .. dir .. ": " .. tostring(err))
        if not handle:is_closing() then
          handle:close()
        end
      end
    end
  end

  if #w.watcher_handles == 0 then
    vim.notify("[TermLet] Watch: failed to start any watchers for '" .. script_name .. "'", vim.log.levels.ERROR)
    if w.timer and not w.timer:is_closing() then
      w.timer:close()
    end
    return false
  end

  -- Log if some directories failed to watch (partial success)
  local failed_count = #dirs - #w.watcher_handles
  if failed_count > 0 then
    debug_log(
      "Watch: " .. failed_count .. " of " .. #dirs .. " directories failed to watch for '" .. script_name .. "'"
    )
  end

  watchers[script_name] = w
  return true
end

--- Stop watching for a specific script
---@param script_name string
function M.stop(script_name)
  if not watchers[script_name] then
    return
  end
  stop_watchers(script_name)
  watchers[script_name] = nil
end

--- Stop all watchers
function M.stop_all()
  for name, _ in pairs(watchers) do
    stop_watchers(name)
  end
  watchers = {}
end

--- Toggle watch mode for a script.
--- Note: This function does NOT emit notifications. The caller (init.lua) owns
--- all user-facing notifications to avoid duplicates between API layers.
---@param script_name string
---@param script table Script configuration
---@param watch_config table Watch configuration
---@param root_dir string Root directory
---@return boolean new_state true if watch is now active, false if stopped
function M.toggle(script_name, script, watch_config, root_dir)
  if M.is_watching(script_name) then
    M.stop(script_name)
    return false
  else
    return M.start(script_name, script, watch_config, root_dir)
  end
end

--- Check if a script is currently being watched
---@param script_name string
---@return boolean
function M.is_watching(script_name)
  local w = watchers[script_name]
  return w ~= nil and w.enabled == true and #(w.watcher_handles or {}) > 0
end

--- Get the watch configuration for a script
---@param script_name string
---@return table|nil
function M.get_watch_config(script_name)
  local w = watchers[script_name]
  if w then
    return vim.deepcopy(w.config)
  end
  return nil
end

--- Get list of all actively watched scripts
---@return table List of script names being watched
function M.get_watched_scripts()
  local result = {}
  for name, w in pairs(watchers) do
    if w.enabled then
      table.insert(result, name)
    end
  end
  table.sort(result)
  return result
end

--- Get full state for all watchers (for testing)
---@return table
function M.get_state()
  local result = {}
  for name, w in pairs(watchers) do
    result[name] = {
      enabled = w.enabled,
      handle_count = #(w.watcher_handles or {}),
      root_dir = w.root_dir,
      config = w.config and vim.deepcopy(w.config) or nil,
    }
  end
  return result
end

--- Set the execute callback (called by init.lua during setup)
---@param callback function
function M.set_execute_callback(callback)
  execute_callback = callback
end

--- Set the debug log function (called by init.lua during setup)
---@param fn function
function M.set_debug_log(fn)
  debug_log = fn or function() end
end

-- Expose for testing
M._glob_to_pattern = glob_to_pattern
M._matches_patterns = matches_patterns
M._is_excluded = is_excluded
M._collect_watch_dirs = collect_watch_dirs
M._default_watch_config = default_watch_config

return M
