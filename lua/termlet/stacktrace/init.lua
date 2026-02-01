-- Stack trace parser plugin architecture
-- Provides extensible parser registration and management

local M = {}

-- Storage for registered parsers
local registered_parsers = {}
-- Ordered list to maintain insertion order (deterministic iteration)
local parser_order_list = {}

-- Default configuration
local config = {
  enabled = true,
  languages = {},
  custom_parsers = {},
  parser_order = { "custom", "builtin" },
}

-- Validate parser structure
-- Returns: success (boolean), error_message (string or nil)
local function validate_parser(parser)
  if type(parser) ~= "table" then
    return false, "Parser must be a table"
  end

  if not parser.name or type(parser.name) ~= "string" or parser.name == "" then
    return false, "Parser must have a non-empty 'name' field"
  end

  if parser.description and type(parser.description) ~= "string" then
    return false, "Parser 'description' must be a string"
  end

  if not parser.patterns or type(parser.patterns) ~= "table" or #parser.patterns == 0 then
    return false, "Parser must have a non-empty 'patterns' table"
  end

  -- Validate each pattern
  for i, pattern in ipairs(parser.patterns) do
    if type(pattern) ~= "table" then
      return false, "Pattern " .. i .. " must be a table"
    end

    if not pattern.pattern or type(pattern.pattern) ~= "string" then
      return false, "Pattern " .. i .. " must have a 'pattern' field (string)"
    end

    -- Verify pattern is valid Lua pattern
    local success = pcall(function()
      string.match("test", pattern.pattern)
    end)
    if not success then
      return false, "Pattern " .. i .. " has invalid Lua pattern syntax"
    end

    if not pattern.path_group or type(pattern.path_group) ~= "number" or pattern.path_group < 1 then
      return false, "Pattern " .. i .. " must have a valid 'path_group' field (number >= 1)"
    end

    if not pattern.line_group or type(pattern.line_group) ~= "number" or pattern.line_group < 1 then
      return false, "Pattern " .. i .. " must have a valid 'line_group' field (number >= 1)"
    end

    if pattern.column_group and (type(pattern.column_group) ~= "number" or pattern.column_group < 1) then
      return false, "Pattern " .. i .. " 'column_group' must be a number >= 1"
    end
  end

  -- Validate optional functions
  if parser.resolve_path and type(parser.resolve_path) ~= "function" then
    return false, "Parser 'resolve_path' must be a function"
  end

  if parser.is_context_match and type(parser.is_context_match) ~= "function" then
    return false, "Parser 'is_context_match' must be a function"
  end

  return true, nil
end

-- Register a parser
-- Returns: success (boolean), error_message (string or nil)
function M.register_parser(parser)
  local valid, err = validate_parser(parser)
  if not valid then
    return false, err
  end

  -- Check for duplicate names
  if registered_parsers[parser.name] then
    return false, "Parser '" .. parser.name .. "' is already registered"
  end

  registered_parsers[parser.name] = parser
  table.insert(parser_order_list, parser.name)
  return true, nil
end

-- Unregister a parser by name
function M.unregister_parser(name)
  if registered_parsers[name] then
    registered_parsers[name] = nil
    for i, n in ipairs(parser_order_list) do
      if n == name then
        table.remove(parser_order_list, i)
        break
      end
    end
    return true
  end
  return false
end

-- Get a parser by name
function M.get_parser(name)
  return registered_parsers[name]
end

-- Get all registered parsers (in registration order)
function M.get_all_parsers()
  local parsers = {}
  for _, name in ipairs(parser_order_list) do
    if registered_parsers[name] then
      table.insert(parsers, registered_parsers[name])
    end
  end
  return parsers
end

-- Clear all registered parsers (useful for testing)
function M.clear_parsers()
  registered_parsers = {}
  parser_order_list = {}
end

-- Parse a line using all registered parsers
-- Returns: match_info (table or nil)
-- match_info = { parser_name, file_path, line_number, column_number (optional) }
function M.parse_line(line, cwd)
  if not line or type(line) ~= "string" then
    return nil
  end

  cwd = cwd or vim.fn.getcwd()

  -- Try each parser based on parser_order (using insertion-ordered list)
  local parser_list = {}

  for _, order in ipairs(config.parser_order) do
    if order == "custom" then
      for _, name in ipairs(parser_order_list) do
        local parser = registered_parsers[name]
        if parser and parser.custom then
          table.insert(parser_list, parser)
        end
      end
    elseif order == "builtin" then
      for _, name in ipairs(parser_order_list) do
        local parser = registered_parsers[name]
        if parser and not parser.custom then
          table.insert(parser_list, parser)
        end
      end
    end
  end

  for _, parser in ipairs(parser_list) do
    for _, pattern_def in ipairs(parser.patterns) do
      local matches = { string.match(line, pattern_def.pattern) }

      if #matches > 0 then
        local path = matches[pattern_def.path_group]
        local line_num = matches[pattern_def.line_group]
        local raw_col = pattern_def.column_group and matches[pattern_def.column_group] or nil
        local col_num = (raw_col and raw_col ~= "") and raw_col or nil

        if path and line_num then
          -- Resolve path if custom resolver is provided
          local resolved_path = path
          if parser.resolve_path then
            resolved_path = parser.resolve_path(path, cwd)
          end

          return {
            parser_name = parser.name,
            file_path = resolved_path,
            line_number = tonumber(line_num),
            column_number = col_num and tonumber(col_num) or nil,
          }
        end
      end
    end
  end

  return nil
end

-- Parse a line returning all matching parsers (for disambiguation)
-- Returns: array of match_info tables from different parsers
function M.parse_line_all(line, cwd)
  if not line or type(line) ~= "string" then
    return {}
  end

  cwd = cwd or vim.fn.getcwd()

  local matches = {}
  local parser_list = {}

  for _, order in ipairs(config.parser_order) do
    if order == "custom" then
      for _, name in ipairs(parser_order_list) do
        local parser = registered_parsers[name]
        if parser and parser.custom then
          table.insert(parser_list, parser)
        end
      end
    elseif order == "builtin" then
      for _, name in ipairs(parser_order_list) do
        local parser = registered_parsers[name]
        if parser and not parser.custom then
          table.insert(parser_list, parser)
        end
      end
    end
  end

  for _, parser in ipairs(parser_list) do
    for _, pattern_def in ipairs(parser.patterns) do
      local match_results = { string.match(line, pattern_def.pattern) }

      if #match_results > 0 then
        local path = match_results[pattern_def.path_group]
        local line_num = match_results[pattern_def.line_group]
        local raw_col = pattern_def.column_group and match_results[pattern_def.column_group] or nil
        local col_num = (raw_col and raw_col ~= "") and raw_col or nil

        if path and line_num then
          local resolved_path = path
          if parser.resolve_path then
            resolved_path = parser.resolve_path(path, cwd)
          end

          table.insert(matches, {
            parser_name = parser.name,
            file_path = resolved_path,
            line_number = tonumber(line_num),
            column_number = col_num and tonumber(col_num) or nil,
            _parser = parser,
          })
          break -- Only first matching pattern per parser
        end
      end
    end
  end

  return matches
end

-- Parse multiple lines (e.g., from terminal buffer)
-- Uses is_context_match to disambiguate when multiple parsers match
-- Returns: array of match_info tables
function M.parse_lines(lines, cwd)
  if not lines or type(lines) ~= "table" then
    return {}
  end

  local results = {}
  for i, line in ipairs(lines) do
    local all_matches = M.parse_line_all(line, cwd)

    if #all_matches == 1 then
      local match = all_matches[1]
      match._parser = nil
      match.line_index = i
      table.insert(results, match)
    elseif #all_matches > 1 then
      -- Use is_context_match to disambiguate
      local best_match = nil
      for _, match in ipairs(all_matches) do
        if match._parser.is_context_match and match._parser.is_context_match(lines, i) then
          best_match = match
          break
        end
      end
      -- Fall back to first match (respects parser_order) if no context match
      if not best_match then
        best_match = all_matches[1]
      end
      best_match._parser = nil
      best_match.line_index = i
      table.insert(results, best_match)
    end
  end

  return results
end

-- Setup function to initialize configuration
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- Clear existing parsers to support idempotent setup() calls
  M.clear_parsers()

  -- Load built-in language parsers
  -- If config.languages is empty or not specified, load all available built-in parsers
  local languages_to_load = config.languages
  if not languages_to_load or #languages_to_load == 0 then
    -- Auto-discover all available built-in parsers
    languages_to_load = {}
    local parser_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h") .. "/parsers"
    if vim.fn.isdirectory(parser_dir) == 1 then
      local handle = vim.loop.fs_scandir(parser_dir)
      if handle then
        while true do
          local name, type = vim.loop.fs_scandir_next(handle)
          if not name then break end
          -- Load .lua files (excluding init.lua if present)
          if type == "file" and name:match("%.lua$") and name ~= "init.lua" then
            local lang_name = name:match("^(.+)%.lua$")
            table.insert(languages_to_load, lang_name)
          end
        end
      end
    end
  end

  for _, lang in ipairs(languages_to_load) do
    local parser_path = "termlet.parsers." .. lang
    local success, parser_module = pcall(require, parser_path)
    if success and parser_module then
      local ok, err = M.register_parser(parser_module)
      if not ok then
        vim.notify(
          "[TermLet] Failed to register built-in parser '" .. lang .. "': " .. (err or "unknown error"),
          vim.log.levels.WARN
        )
      end
    else
      vim.notify(
        "[TermLet] Failed to load built-in parser '" .. lang .. "'",
        vim.log.levels.WARN
      )
    end
  end

  -- Load custom parsers
  if config.custom_parsers then
    for i, parser in ipairs(config.custom_parsers) do
      -- Deep copy to avoid mutating user-provided parser objects
      local parser_copy = vim.deepcopy(parser)
      parser_copy.custom = true
      local ok, err = M.register_parser(parser_copy)
      if not ok then
        vim.notify(
          "[TermLet] Failed to register custom parser " .. i .. ": " .. (err or "unknown error"),
          vim.log.levels.WARN
        )
      end
    end
  end

  return config
end

-- Get current configuration
function M.get_config()
  return vim.deepcopy(config)
end

return M
