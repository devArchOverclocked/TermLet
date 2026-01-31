-- Stack trace parser plugin architecture
-- Provides extensible parser registration and management

local M = {}

-- Storage for registered parsers
local registered_parsers = {}

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
  return true, nil
end

-- Unregister a parser by name
function M.unregister_parser(name)
  if registered_parsers[name] then
    registered_parsers[name] = nil
    return true
  end
  return false
end

-- Get a parser by name
function M.get_parser(name)
  return registered_parsers[name]
end

-- Get all registered parsers
function M.get_all_parsers()
  local parsers = {}
  for name, parser in pairs(registered_parsers) do
    table.insert(parsers, parser)
  end
  return parsers
end

-- Clear all registered parsers (useful for testing)
function M.clear_parsers()
  registered_parsers = {}
end

-- Parse a line using all registered parsers
-- Returns: match_info (table or nil)
-- match_info = { parser_name, file_path, line_number, column_number (optional) }
function M.parse_line(line, cwd)
  if not line or type(line) ~= "string" then
    return nil
  end

  cwd = cwd or vim.fn.getcwd()

  -- Try each parser based on parser_order
  local parser_list = {}

  for _, order in ipairs(config.parser_order) do
    if order == "custom" then
      for name, parser in pairs(registered_parsers) do
        if parser.custom then
          table.insert(parser_list, parser)
        end
      end
    elseif order == "builtin" then
      for name, parser in pairs(registered_parsers) do
        if not parser.custom then
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
        local col_num = pattern_def.column_group and matches[pattern_def.column_group] or nil

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

-- Parse multiple lines (e.g., from terminal buffer)
-- Returns: array of match_info tables
function M.parse_lines(lines, cwd)
  if not lines or type(lines) ~= "table" then
    return {}
  end

  local results = {}
  for i, line in ipairs(lines) do
    local match = M.parse_line(line, cwd)
    if match then
      match.line_index = i
      table.insert(results, match)
    end
  end

  return results
end

-- Setup function to initialize configuration
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- Load built-in language parsers
  if config.languages then
    for _, lang in ipairs(config.languages) do
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
  end

  -- Load custom parsers
  if config.custom_parsers then
    for i, parser in ipairs(config.custom_parsers) do
      -- Mark as custom
      parser.custom = true
      local ok, err = M.register_parser(parser)
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
