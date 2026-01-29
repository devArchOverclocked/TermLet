-- Stack trace detection and output processing infrastructure
-- lua/termlet/stacktrace.lua

local M = {}

-- Configuration (set via setup)
local config = {
  enabled = true,
  languages = {}, -- Empty means all registered languages
  buffer_size = 50, -- Number of lines to keep in buffer for multi-line detection
}

-- Pattern registry for different languages
M.patterns = {}

-- Metadata storage: maps buffer_id -> { line_number -> file_info }
local buffer_metadata = {}

-- Output buffer for multi-line detection
local output_buffer = {}

---Register a new stack trace pattern for a language
---@param language string The language identifier (e.g., 'python', 'csharp')
---@param pattern_config table Pattern configuration
---  - pattern: string Lua pattern or regex for detecting stack trace lines
---  - file_pattern: string Pattern to extract file path
---  - line_pattern: string Pattern to extract line number
---  - column_pattern: string|nil Optional pattern to extract column number
---  - context_pattern: string|nil Optional pattern to extract function/method name
---  - multiline: boolean|nil Whether this pattern spans multiple lines
---  - start_pattern: string|nil Pattern that marks the start of a multi-line stack trace
---  - end_pattern: string|nil Pattern that marks the end of a multi-line stack trace
function M.register_pattern(language, pattern_config)
  if not language or type(language) ~= "string" then
    error("Language must be a non-empty string")
  end
  if not pattern_config or type(pattern_config) ~= "table" then
    error("Pattern config must be a table")
  end
  if not pattern_config.pattern then
    error("Pattern config must include 'pattern' field")
  end

  M.patterns[language] = pattern_config
end

---Check if a language is enabled for detection
---@param language string The language to check
---@return boolean
local function is_language_enabled(language)
  -- If no specific languages configured, all are enabled
  if not config.languages or #config.languages == 0 then
    return true
  end
  for _, lang in ipairs(config.languages) do
    if lang == language then
      return true
    end
  end
  return false
end

---Match a line against a pattern (handles both Lua patterns and regex-like patterns)
---@param line string The line to match
---@param pattern string The pattern to match against
---@return string|nil ... Captured groups or nil if no match
local function match_pattern(line, pattern)
  -- Use Lua pattern matching
  return line:match(pattern)
end

---Extract file information from a matched line
---@param line string The matched line
---@param pattern_config table The pattern configuration for the language
---@param cwd string The working directory for resolving relative paths
---@return table|nil File info: { path, line, column, context } or nil if extraction failed
function M.extract_file_info(line, pattern_config, cwd)
  if not line or not pattern_config then
    return nil
  end

  local file_path = nil
  local line_num = nil
  local column_num = nil
  local context = nil

  -- Extract file path
  if pattern_config.file_pattern then
    file_path = match_pattern(line, pattern_config.file_pattern)
  end

  -- Extract line number
  if pattern_config.line_pattern then
    local line_str = match_pattern(line, pattern_config.line_pattern)
    if line_str then
      line_num = tonumber(line_str)
    end
  end

  -- Extract column number (optional)
  if pattern_config.column_pattern then
    local col_str = match_pattern(line, pattern_config.column_pattern)
    if col_str then
      column_num = tonumber(col_str)
    end
  end

  -- Extract context/function name (optional)
  if pattern_config.context_pattern then
    context = match_pattern(line, pattern_config.context_pattern)
  end

  -- If we couldn't extract a file path, return nil
  if not file_path then
    return nil
  end

  -- Resolve relative paths to absolute paths
  local resolved_path = M.resolve_path(file_path, cwd)

  return {
    path = resolved_path,
    original_path = file_path,
    line = line_num,
    column = column_num,
    context = context,
  }
end

---Resolve a file path to an absolute path
---@param file_path string The file path (absolute or relative)
---@param cwd string The working directory for resolving relative paths
---@return string The resolved absolute path
function M.resolve_path(file_path, cwd)
  if not file_path then
    return nil
  end

  -- Check if already absolute
  if file_path:sub(1, 1) == "/" then
    return file_path
  end

  -- Handle Windows absolute paths (e.g., C:\...)
  if file_path:match("^%a:[\\/]") then
    return file_path
  end

  -- Resolve relative path using cwd
  if cwd then
    local resolved = cwd .. "/" .. file_path
    -- Normalize the path (remove ./ and resolve ../)
    resolved = vim.fn.fnamemodify(resolved, ":p")
    return resolved
  end

  -- Fallback: return as-is
  return file_path
end

---Process a single line of output and detect stack traces
---@param line string The output line to process
---@param cwd string The working directory for resolving paths
---@return table|nil Detected file reference or nil
function M.process_line(line, cwd)
  if not config.enabled or not line or line == "" then
    return nil
  end

  for language, pattern_config in pairs(M.patterns) do
    if is_language_enabled(language) then
      -- Check if line matches the stack trace pattern
      if match_pattern(line, pattern_config.pattern) then
        local file_info = M.extract_file_info(line, pattern_config, cwd)
        if file_info then
          file_info.language = language
          file_info.raw_line = line
          return file_info
        end
      end
    end
  end

  return nil
end

---Process multiple lines of output and detect stack traces
---@param lines string[] Array of output lines
---@param cwd string The working directory for resolving paths
---@return table[] Array of detected file references with positions
function M.process_output(lines, cwd)
  if not config.enabled or not lines then
    return {}
  end

  local results = {}

  for i, line in ipairs(lines) do
    -- Skip empty lines
    if line and line ~= "" then
      local file_info = M.process_line(line, cwd)
      if file_info then
        file_info.line_index = i
        table.insert(results, file_info)
      end
    end
  end

  return results
end

---Add line to the output buffer for multi-line detection
---@param line string The line to add
local function add_to_buffer(line)
  table.insert(output_buffer, line)
  -- Trim buffer if it exceeds the configured size
  while #output_buffer > config.buffer_size do
    table.remove(output_buffer, 1)
  end
end

---Clear the output buffer
function M.clear_buffer()
  output_buffer = {}
end

---Get the current output buffer
---@return string[] The output buffer
function M.get_buffer()
  return output_buffer
end

---Process output data from terminal callbacks (on_stdout/on_stderr)
---@param data string[] Array of output data from terminal
---@param cwd string The working directory
---@param buffer_id number|nil Optional buffer ID for storing metadata
---@return table[] Array of detected file references
function M.process_terminal_output(data, cwd, buffer_id)
  if not config.enabled or not data then
    return {}
  end

  local results = {}

  for _, line in ipairs(data) do
    if line and line ~= "" then
      add_to_buffer(line)

      local file_info = M.process_line(line, cwd)
      if file_info then
        file_info.buffer_line = #output_buffer
        table.insert(results, file_info)

        -- Store in buffer metadata if buffer_id provided
        if buffer_id then
          M.store_metadata(buffer_id, #output_buffer, file_info)
        end
      end
    end
  end

  return results
end

---Store file metadata for a buffer position
---@param buffer_id number The buffer ID
---@param line_number number The line number in the buffer
---@param file_info table The file information to store
function M.store_metadata(buffer_id, line_number, file_info)
  if not buffer_metadata[buffer_id] then
    buffer_metadata[buffer_id] = {}
  end
  buffer_metadata[buffer_id][line_number] = file_info
end

---Get file metadata for a buffer position
---@param buffer_id number The buffer ID
---@param line_number number The line number in the buffer
---@return table|nil The file information or nil if not found
function M.get_metadata(buffer_id, line_number)
  if not buffer_metadata[buffer_id] then
    return nil
  end
  return buffer_metadata[buffer_id][line_number]
end

---Get all metadata for a buffer
---@param buffer_id number The buffer ID
---@return table The metadata table for the buffer
function M.get_buffer_metadata(buffer_id)
  return buffer_metadata[buffer_id] or {}
end

---Clear metadata for a buffer
---@param buffer_id number The buffer ID
function M.clear_metadata(buffer_id)
  buffer_metadata[buffer_id] = nil
end

---Clear all stored metadata
function M.clear_all_metadata()
  buffer_metadata = {}
end

---Find file info near a cursor position in a buffer
---@param buffer_id number The buffer ID
---@param cursor_line number The cursor line position
---@param search_range number|nil Number of lines to search above/below (default 5)
---@return table|nil The nearest file info or nil if not found
function M.find_nearest_metadata(buffer_id, cursor_line, search_range)
  search_range = search_range or 5
  local metadata = buffer_metadata[buffer_id]

  if not metadata then
    return nil
  end

  -- Check exact line first
  if metadata[cursor_line] then
    return metadata[cursor_line]
  end

  -- Search nearby lines
  for offset = 1, search_range do
    if metadata[cursor_line - offset] then
      return metadata[cursor_line - offset]
    end
    if metadata[cursor_line + offset] then
      return metadata[cursor_line + offset]
    end
  end

  return nil
end

---Configure the stacktrace module
---@param user_config table User configuration
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- Register built-in patterns if none exist
  if vim.tbl_count(M.patterns) == 0 then
    M.register_builtin_patterns()
  end
end

---Register built-in stack trace patterns for common languages
function M.register_builtin_patterns()
  -- Python stack trace pattern
  -- Example: File "/path/to/file.py", line 42, in function_name
  M.register_pattern("python", {
    pattern = 'File "([^"]+)", line (%d+)',
    file_pattern = 'File "([^"]+)"',
    line_pattern = "line (%d+)",
    context_pattern = "in ([%w_]+)$",
    multiline = false,
  })

  -- C# stack trace pattern
  -- Example: at Namespace.Class.Method() in /path/to/file.cs:line 42
  M.register_pattern("csharp", {
    pattern = "in ([^:]+):line (%d+)",
    file_pattern = "in ([^:]+):line",
    line_pattern = ":line (%d+)",
    context_pattern = "at ([^%(]+)%(",
    multiline = false,
  })

  -- JavaScript/Node.js stack trace pattern
  -- Example: at functionName (/path/to/file.js:42:15)
  -- Example: at /path/to/file.js:42:15
  M.register_pattern("javascript", {
    pattern = "at .* %(([^:]+):(%d+):(%d+)%)",
    file_pattern = "%(([^:]+):%d+:%d+%)",
    line_pattern = ":(%d+):%d+%)",
    column_pattern = ":%d+:(%d+)%)",
    context_pattern = "at ([^%(]+) %(",
    multiline = false,
  })

  -- JavaScript/Node.js alternative pattern (no parentheses)
  M.register_pattern("javascript_alt", {
    pattern = "at ([^:]+):(%d+):(%d+)$",
    file_pattern = "at ([^:]+):%d+:%d+$",
    line_pattern = ":(%d+):%d+$",
    column_pattern = ":%d+:(%d+)$",
    multiline = false,
  })

  -- Go stack trace pattern
  -- Example: /path/to/file.go:42 +0x123
  M.register_pattern("go", {
    pattern = "^%s*([^%s]+%.go):(%d+)",
    file_pattern = "^%s*([^%s]+%.go):%d+",
    line_pattern = "%.go:(%d+)",
    multiline = false,
  })

  -- Rust stack trace pattern
  -- Example: at /path/to/file.rs:42:15
  M.register_pattern("rust", {
    pattern = "at ([^:]+%.rs):(%d+):(%d+)",
    file_pattern = "at ([^:]+%.rs):%d+:%d+",
    line_pattern = "%.rs:(%d+):%d+",
    column_pattern = "%.rs:%d+:(%d+)",
    multiline = false,
  })

  -- Java stack trace pattern
  -- Example: at com.example.Class.method(File.java:42)
  M.register_pattern("java", {
    pattern = "at [^%(]+%(([^:]+):(%d+)%)",
    file_pattern = "%(([^:]+):%d+%)",
    line_pattern = ":(%d+)%)",
    context_pattern = "at ([^%(]+)%(",
    multiline = false,
  })

  -- Lua stack trace pattern
  -- Example: /path/to/file.lua:42: error message
  M.register_pattern("lua", {
    pattern = "^%s*([^:]+%.lua):(%d+):",
    file_pattern = "^%s*([^:]+%.lua):%d+:",
    line_pattern = "%.lua:(%d+):",
    multiline = false,
  })

  -- Ruby stack trace pattern
  -- Example: /path/to/file.rb:42:in `method_name'
  M.register_pattern("ruby", {
    pattern = "([^:]+%.rb):(%d+):in",
    file_pattern = "([^:]+%.rb):%d+:in",
    line_pattern = "%.rb:(%d+):in",
    context_pattern = ":in `([^']+)'",
    multiline = false,
  })
end

---Check if stacktrace processing is enabled
---@return boolean
function M.is_enabled()
  return config.enabled
end

---Enable stacktrace processing
function M.enable()
  config.enabled = true
end

---Disable stacktrace processing
function M.disable()
  config.enabled = false
end

---Get the current configuration
---@return table The current configuration
function M.get_config()
  return vim.deepcopy(config)
end

---Get all registered patterns
---@return table The registered patterns
function M.get_patterns()
  return M.patterns
end

return M
