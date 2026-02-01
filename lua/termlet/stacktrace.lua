-- Stack trace detection and output processing infrastructure
-- lua/termlet/stacktrace.lua

local M = {}

-- Configuration (set via setup)
local config = {
  enabled = true,
  languages = {}, -- Empty means all registered languages
  buffer_size = 50, -- Number of lines to keep in buffer for multi-line detection
}

-- Pattern registry: ordered list of { language = string, config = table, priority = number }
-- Higher priority patterns are checked first. Use ipairs() for deterministic order.
local pattern_list = {}

-- Lookup table for quick access by language name
local pattern_lookup = {}

-- Metadata storage: maps buffer_id -> { line_number -> file_info }
local buffer_metadata = {}

-- Output buffer for multi-line detection
local output_buffer = {}

-- Load highlight module once at module level with pcall guard
local highlight_ok, highlight_module = pcall(require, "termlet.highlight")

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

  local priority = pattern_config.priority or 0

  -- Remove existing entry for this language if re-registering
  if pattern_lookup[language] then
    for i, entry in ipairs(pattern_list) do
      if entry.language == language then
        table.remove(pattern_list, i)
        break
      end
    end
  end

  local entry = {
    language = language,
    config = pattern_config,
    priority = priority,
  }

  -- Insert in priority order (higher priority first)
  local inserted = false
  for i, existing in ipairs(pattern_list) do
    if priority > existing.priority then
      table.insert(pattern_list, i, entry)
      inserted = true
      break
    end
  end
  if not inserted then
    table.insert(pattern_list, entry)
  end

  pattern_lookup[language] = pattern_config
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

---Strip ANSI escape sequences and carriage returns from a string.
---Terminal PTY output includes escape codes (e.g. \x1b[0m) that corrupt
---Lua pattern matching. This function removes them before processing.
---@param str string The string to clean
---@return string The cleaned string
function M.strip_ansi(str)
  -- Remove ANSI CSI sequences: ESC [ (optional private-mode prefix ?/>/=) params final_byte
  -- Private-mode prefixes like ? appear in common sequences:
  --   \27[?25h (show cursor), \27[?25l (hide cursor),
  --   \27[?1049h (alternate screen), \27[?7h (auto-wrap)
  local cleaned = str:gsub("\27%[[?>=]*[%d;]*[A-Za-z@]", "")
  -- Remove OSC sequences: ESC ] ... ST (BEL or ESC \)
  cleaned = cleaned:gsub("\27%][^\a\27]*[\a]", "")
  cleaned = cleaned:gsub("\27%][^\a\27]*\27\\", "")
  -- Remove other ESC sequences (two-character)
  cleaned = cleaned:gsub("\27[%(%)][A-Za-z0-9]", "")
  -- Remove carriage returns (PTY often sends \r\n)
  cleaned = cleaned:gsub("\r", "")
  return cleaned
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

  -- Expand tilde (~) to user's home directory
  if file_path:sub(1, 1) == "~" then
    local home = vim.loop.os_homedir() or os.getenv("HOME") or ""
    file_path = home .. file_path:sub(2)
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

  -- Iterate in deterministic priority order using ipairs on the ordered list
  for _, entry in ipairs(pattern_list) do
    if is_language_enabled(entry.language) then
      -- Check if line matches the stack trace pattern
      if match_pattern(line, entry.config.pattern) then
        local file_info = M.extract_file_info(line, entry.config, cwd)
        if file_info then
          file_info.language = entry.language
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

  -- Get the current terminal buffer line count to key metadata correctly.
  -- The metadata must be keyed on the actual Neovim buffer line number so that
  -- find_nearest_metadata (called with cursor position) can locate entries.
  local terminal_line_count = 0
  if buffer_id and vim.api.nvim_buf_is_valid(buffer_id) then
    terminal_line_count = vim.api.nvim_buf_line_count(buffer_id)
  end

  local results = {}
  local line_offset = 0

  for _, line in ipairs(data) do
    -- Increment line_offset for every element in data, including empty strings,
    -- because Neovim's on_stdout/on_stderr callbacks include empty strings as
    -- line separators and each element corresponds to a line in the terminal buffer.
    line_offset = line_offset + 1

    if line and line ~= "" then
      -- Strip ANSI escape sequences from PTY output before processing.
      -- termopen() creates a pseudo-terminal, so on_stdout receives raw
      -- terminal data including escape codes that corrupt pattern matching.
      local cleaned_line = M.strip_ansi(line)
      add_to_buffer(cleaned_line)

      local file_info = M.process_line(cleaned_line, cwd)
      if file_info then
        local buffer_line = terminal_line_count + line_offset
        file_info.buffer_line = buffer_line
        table.insert(results, file_info)

        -- Store in buffer metadata keyed on actual terminal buffer line number
        if buffer_id then
          M.store_metadata(buffer_id, buffer_line, file_info)

          -- Apply highlighting if available
          -- We need to use vim.schedule because we're in a callback and need to
          -- wait for the line to be fully rendered in the terminal buffer
          if highlight_ok and highlight_module.is_enabled() then
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(buffer_id) then
                -- Get the actual line text from the buffer
                local lines = vim.api.nvim_buf_get_lines(buffer_id, buffer_line - 1, buffer_line, false)
                if #lines > 0 then
                  highlight_module.highlight_stacktrace_line(buffer_id, buffer_line, lines[1], file_info)
                end
              end
            end)
          end
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
---@param search_range number|nil Number of lines to search above/below (default 10)
---@return table|nil The nearest file info or nil if not found
function M.find_nearest_metadata(buffer_id, cursor_line, search_range)
  search_range = search_range or 10
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

---Scan a terminal buffer's rendered content for stack trace references.
---This should be called after the process exits, because Neovim strips ANSI
---escape codes from terminal buffer lines read via nvim_buf_get_lines().
---This provides the most reliable detection since it operates on clean text
---with accurate 1-indexed line numbers that match cursor positions exactly.
---@param buffer_id number The terminal buffer ID
---@param cwd string The working directory for resolving paths
---@return table[] Array of detected file references
function M.scan_buffer_for_stacktraces(buffer_id, cwd)
  if not config.enabled then
    return {}
  end
  if not buffer_id or not vim.api.nvim_buf_is_valid(buffer_id) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local results = {}

  for i, line in ipairs(lines) do
    if line and line ~= "" then
      local file_info = M.process_line(line, cwd)
      if file_info then
        file_info.buffer_line = i
        table.insert(results, file_info)
        M.store_metadata(buffer_id, i, file_info)

        -- Apply highlighting if available
        if highlight_ok and highlight_module.is_enabled() then
          highlight_module.highlight_stacktrace_line(buffer_id, i, line, file_info)
        end
      end
    end
  end

  return results
end

-- Load the parser plugin module
-- Note: require("termlet.stacktrace") resolves to this file (stacktrace.lua),
-- so the parser module at stacktrace/init.lua is loaded via dofile to avoid conflicts.
local parser_module
do
  local info = debug.getinfo(1, "S")
  local this_dir = vim.fn.fnamemodify(info.source:sub(2), ":h")
  local parser_init = this_dir .. "/stacktrace/init.lua"
  if vim.fn.filereadable(parser_init) == 1 then
    parser_module = dofile(parser_init)
  end
end

-- Re-export parser module functions
if parser_module then
  M.register_parser = parser_module.register_parser
  M.unregister_parser = parser_module.unregister_parser
  M.get_parser = parser_module.get_parser
  M.get_all_parsers = parser_module.get_all_parsers
  M.clear_parsers = parser_module.clear_parsers
  M.parse_line = parser_module.parse_line
  M.parse_line_all = parser_module.parse_line_all
  M.parse_lines = parser_module.parse_lines
  M.get_parser_config = parser_module.get_config
end

---Configure the stacktrace module
---@param user_config table User configuration
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- Register built-in patterns if none exist
  if #pattern_list == 0 then
    M.register_builtin_patterns()
  end

  -- Setup parser plugin module if available
  if parser_module then
    parser_module.setup(user_config or {})
  end
end

---Register built-in stack trace patterns for common languages
function M.register_builtin_patterns()
  -- Patterns are registered with a priority field. Higher priority patterns are
  -- checked first, which avoids false positives from broad patterns matching
  -- lines intended for more specific ones. Language-keyword patterns (containing
  -- distinguishing tokens like "File", "at", "in") get higher priority than
  -- generic file:line patterns.

  -- Python stack trace pattern (priority 10: has unique "File" keyword)
  -- Example: File "/path/to/file.py", line 42, in function_name
  M.register_pattern("python", {
    pattern = 'File "([^"]+)", line (%d+)',
    file_pattern = 'File "([^"]+)"',
    line_pattern = "line (%d+)",
    context_pattern = "in ([%w_]+)$",
    multiline = false,
    priority = 10,
  })

  -- C# stack trace pattern (priority 10: has unique "in ... :line" keyword)
  -- Example: at Namespace.Class.Method() in /path/to/file.cs:line 42
  M.register_pattern("csharp", {
    pattern = "in ([^:]+):line (%d+)",
    file_pattern = "in ([^:]+):line",
    line_pattern = ":line (%d+)",
    context_pattern = "at ([^%(]+)%(",
    multiline = false,
    priority = 10,
  })

  -- JavaScript/Node.js stack trace pattern (priority 8: has "at" + parens)
  -- Example: at functionName (/path/to/file.js:42:15)
  M.register_pattern("javascript", {
    pattern = "at .* %(([^:]+):(%d+):(%d+)%)",
    file_pattern = "%(([^:]+):%d+:%d+%)",
    line_pattern = ":(%d+):%d+%)",
    column_pattern = ":%d+:(%d+)%)",
    context_pattern = "at ([^%(]+) %(",
    multiline = false,
    priority = 8,
  })

  -- JavaScript/Node.js alternative pattern (priority 5: generic "at file:line:col")
  M.register_pattern("javascript_alt", {
    pattern = "at ([^:]+):(%d+):(%d+)$",
    file_pattern = "at ([^:]+):%d+:%d+$",
    line_pattern = ":(%d+):%d+$",
    column_pattern = ":%d+:(%d+)$",
    multiline = false,
    priority = 5,
  })

  -- Java stack trace pattern (priority 8: has "at" + parens with .java extension)
  -- Example: at com.example.Class.method(File.java:42)
  M.register_pattern("java", {
    pattern = "at [^%(]+%(([^:]+):(%d+)%)",
    file_pattern = "%(([^:]+):%d+%)",
    line_pattern = ":(%d+)%)",
    context_pattern = "at ([^%(]+)%(",
    multiline = false,
    priority = 8,
  })

  -- Rust stack trace pattern (priority 7: has "at" + .rs extension)
  -- Example: at /path/to/file.rs:42:15
  M.register_pattern("rust", {
    pattern = "at ([^:]+%.rs):(%d+):(%d+)",
    file_pattern = "at ([^:]+%.rs):%d+:%d+",
    line_pattern = "%.rs:(%d+):%d+",
    column_pattern = "%.rs:%d+:(%d+)",
    multiline = false,
    priority = 7,
  })

  -- Ruby stack trace pattern (priority 7: has .rb extension + "in" keyword)
  -- Example: /path/to/file.rb:42:in `method_name'
  M.register_pattern("ruby", {
    pattern = "([^:]+%.rb):(%d+):in",
    file_pattern = "([^:]+%.rb):%d+:in",
    line_pattern = "%.rb:(%d+):in",
    context_pattern = ":in `([^']+)'",
    multiline = false,
    priority = 7,
  })

  -- Elixir/Erlang stack trace pattern (priority 7: has parens + .ex/.erl extension)
  -- Example: (my_app 0.1.0) lib/my_app/worker.ex:42: MyApp.Worker.run/1
  -- Example: lib/my_app.ex:42: (module)
  M.register_pattern("elixir", {
    pattern = "([^:%s]+%.exs?):(%d+):",
    file_pattern = "([^:%s]+%.exs?):%d+:",
    line_pattern = "%.exs?:(%d+):",
    multiline = false,
    priority = 7,
  })

  -- Erlang stack trace pattern
  -- Example: {module,function,1,[{file,"src/module.erl"},{line,42}]}
  M.register_pattern("erlang", {
    pattern = '{file,"([^"]+%.erl)"}.*{line,(%d+)}',
    file_pattern = '{file,"([^"]+%.erl)"}',
    line_pattern = "{line,(%d+)}",
    multiline = false,
    priority = 7,
  })

  -- Swift stack trace pattern (priority 6: has .swift extension)
  -- Example: /path/to/file.swift:42: error: something went wrong
  -- Example: /path/to/file.swift:42:15: error: description
  M.register_pattern("swift", {
    pattern = "([^:%s]+%.swift):(%d+):",
    file_pattern = "([^:%s]+%.swift):%d+:",
    line_pattern = "%.swift:(%d+):",
    column_pattern = "%.swift:%d+:(%d+):",
    multiline = false,
    priority = 6,
  })

  -- Kotlin stack trace pattern (priority 9: uses Java-style "at" keyword + .kt extension,
  -- higher priority than generic Java pattern to avoid Kotlin traces matching as Java)
  -- Example: at com.example.MyClass.method(MyFile.kt:42)
  M.register_pattern("kotlin", {
    pattern = "at [^%(]+%(([^:]+%.kt):(%d+)%)",
    file_pattern = "%(([^:]+%.kt):%d+%)",
    line_pattern = ":(%d+)%)",
    context_pattern = "at ([^%(]+)%(",
    multiline = false,
    priority = 9,
  })

  -- Haskell stack trace pattern (priority 6: has .hs extension)
  -- Example: /path/to/file.hs:42:15: error:
  -- Example: CallStack (from HasCallStack):  module, called at src/Module.hs:42:15
  M.register_pattern("haskell", {
    pattern = "([^:%s]+%.hs):(%d+):",
    file_pattern = "([^:%s]+%.hs):%d+:",
    line_pattern = "%.hs:(%d+):",
    column_pattern = "%.hs:%d+:(%d+):",
    multiline = false,
    priority = 6,
  })

  -- PHP stack trace pattern (priority 6: has .php extension + specific format)
  -- Example: /path/to/file.php:42
  -- Example: #0 /path/to/file.php(42): ClassName->method()
  M.register_pattern("php", {
    pattern = "([^:%(]+%.php)[:(](%d+)",
    file_pattern = "([^:%(]+%.php)[:(]%d+",
    line_pattern = "%.php[:(](%d+)",
    multiline = false,
    priority = 6,
  })

  -- Perl stack trace pattern (priority 7: has .pl/.pm extension + "at" + "line" keywords)
  -- Example: at /path/to/script.pl line 42.
  -- Example: at /path/to/Module.pm line 42
  M.register_pattern("perl", {
    pattern = "at ([^%s]+%.p[lm]) line (%d+)",
    file_pattern = "at ([^%s]+%.p[lm]) line",
    line_pattern = "line (%d+)",
    multiline = false,
    priority = 7,
  })

  -- C source files
  -- Example: /path/to/file.c:42:15: error: expected ';'
  M.register_pattern("c_source", {
    pattern = "([^:%s]+%.c):(%d+):",
    file_pattern = "([^:%s]+%.c):%d+:",
    line_pattern = "%.c:(%d+):",
    column_pattern = "%.c:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- C++ source files (.cpp)
  -- Example: /path/to/file.cpp:42: undefined reference
  M.register_pattern("cpp_source", {
    pattern = "([^:%s]+%.cpp):(%d+):",
    file_pattern = "([^:%s]+%.cpp):%d+:",
    line_pattern = "%.cpp:(%d+):",
    column_pattern = "%.cpp:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- C++ source files (.cc)
  -- Example: /path/to/file.cc:42: error
  M.register_pattern("cc_source", {
    pattern = "([^:%s]+%.cc):(%d+):",
    file_pattern = "([^:%s]+%.cc):%d+:",
    line_pattern = "%.cc:(%d+):",
    column_pattern = "%.cc:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- C++ source files (.cxx)
  -- Example: /path/to/file.cxx:42: error
  M.register_pattern("cxx_source", {
    pattern = "([^:%s]+%.cxx):(%d+):",
    file_pattern = "([^:%s]+%.cxx):%d+:",
    line_pattern = "%.cxx:(%d+):",
    column_pattern = "%.cxx:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- C header files (.h)
  -- Example: file.h:42:10: warning: unused variable
  M.register_pattern("h_header", {
    pattern = "([^:%s]+%.h):(%d+):",
    file_pattern = "([^:%s]+%.h):%d+:",
    line_pattern = "%.h:(%d+):",
    column_pattern = "%.h:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- C++ header files (.hpp)
  -- Example: /path/to/file.hpp:42: error
  M.register_pattern("hpp_header", {
    pattern = "([^:%s]+%.hpp):(%d+):",
    file_pattern = "([^:%s]+%.hpp):%d+:",
    line_pattern = "%.hpp:(%d+):",
    column_pattern = "%.hpp:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- C++ header files (.hh)
  -- Example: /path/to/file.hh:42: error
  M.register_pattern("hh_header", {
    pattern = "([^:%s]+%.hh):(%d+):",
    file_pattern = "([^:%s]+%.hh):%d+:",
    line_pattern = "%.hh:(%d+):",
    column_pattern = "%.hh:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- C++ header files (.hxx)
  -- Example: /path/to/file.hxx:42: error
  M.register_pattern("hxx_header", {
    pattern = "([^:%s]+%.hxx):(%d+):",
    file_pattern = "([^:%s]+%.hxx):%d+:",
    line_pattern = "%.hxx:(%d+):",
    column_pattern = "%.hxx:%d+:(%d+):",
    multiline = false,
    priority = 5,
  })

  -- Go stack trace pattern (priority 5: generic .go:line)
  -- Example: /path/to/file.go:42 +0x123
  M.register_pattern("go", {
    pattern = "^%s*([^%s]+%.go):(%d+)",
    file_pattern = "^%s*([^%s]+%.go):%d+",
    line_pattern = "%.go:(%d+)",
    multiline = false,
    priority = 5,
  })

  -- Lua stack trace pattern (priority 5: generic .lua:line)
  -- Example: /path/to/file.lua:42: error message
  M.register_pattern("lua", {
    pattern = "^%s*([^:]+%.lua):(%d+):",
    file_pattern = "^%s*([^:]+%.lua):%d+:",
    line_pattern = "%.lua:(%d+):",
    multiline = false,
    priority = 5,
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

---Get all registered patterns (returns a deep copy for safety)
---@return table A copy of the pattern lookup table keyed by language name
function M.get_patterns()
  return vim.deepcopy(pattern_lookup)
end

---Get the ordered pattern list (returns a deep copy for safety)
---@return table[] Ordered list of { language, config, priority }
function M.get_pattern_list()
  return vim.deepcopy(pattern_list)
end

return M
