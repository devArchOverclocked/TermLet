-- Sharing Module for TermLet
-- Export/import script configurations for team sharing and onboarding

local M = {}

-- Default sensitive field patterns to exclude from exports
local SENSITIVE_FIELDS = {
  "root_dir",
  "search_dirs",
  "cmd",
  "on_stdout",
}

-- Supported export formats
local SUPPORTED_FORMATS = {
  json = true,
  lua = true,
}

--- Check if a field name is sensitive
---@param field string Field name to check
---@param sensitive_fields table List of field names considered sensitive
---@return boolean
local function is_sensitive_field(field, sensitive_fields)
  for _, pattern in ipairs(sensitive_fields) do
    if field == pattern then
      return true
    end
  end
  return false
end

--- Deep copy a table, filtering out sensitive fields and non-serializable values
---@param tbl table Source table
---@param exclude_sensitive boolean Whether to exclude sensitive fields
---@param sensitive_fields table List of field names considered sensitive
---@return table Filtered copy
local function filter_script(tbl, exclude_sensitive, sensitive_fields)
  local result = {}
  for k, v in pairs(tbl) do
    local should_exclude = type(v) == "function" or (exclude_sensitive and is_sensitive_field(k, sensitive_fields))
    if not should_exclude then
      if type(v) == "table" then
        result[k] = filter_script(v, exclude_sensitive, sensitive_fields)
      else
        result[k] = v
      end
    end
  end
  return result
end

--- Pretty-print a JSON string with indentation
---@param json_str string Compact JSON string
---@return string Pretty-printed JSON
local function pretty_print_json(json_str)
  local indent = 0
  local result = {}
  local in_string = false
  local escape_next = false

  for i = 1, #json_str do
    local char = json_str:sub(i, i)

    if escape_next then
      table.insert(result, char)
      escape_next = false
    elseif char == "\\" and in_string then
      table.insert(result, char)
      escape_next = true
    elseif char == '"' then
      in_string = not in_string
      table.insert(result, char)
    elseif in_string then
      table.insert(result, char)
    elseif char == "{" or char == "[" then
      indent = indent + 1
      table.insert(result, char)
      table.insert(result, "\n" .. string.rep("  ", indent))
    elseif char == "}" or char == "]" then
      indent = indent - 1
      table.insert(result, "\n" .. string.rep("  ", indent))
      table.insert(result, char)
    elseif char == "," then
      table.insert(result, char)
      table.insert(result, "\n" .. string.rep("  ", indent))
    elseif char == ":" then
      table.insert(result, ": ")
    elseif char ~= " " and char ~= "\n" and char ~= "\r" and char ~= "\t" then
      table.insert(result, char)
    end
  end

  return table.concat(result)
end

--- Serialize a Lua value to a Lua source string
---@param value any Value to serialize
---@param indent number Current indentation level
---@return string Lua source representation
local function serialize_lua(value, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local pad_inner = string.rep("  ", indent + 1)

  if type(value) == "string" then
    -- Use %q for safe string escaping
    return string.format("%q", value)
  elseif type(value) == "number" or type(value) == "boolean" then
    return tostring(value)
  elseif type(value) == "nil" then
    return "nil"
  elseif type(value) == "table" then
    -- Check if table is an array (sequential integer keys starting from 1)
    local is_array = true
    local max_index = 0
    for k, _ in pairs(value) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        is_array = false
        break
      end
      if k > max_index then
        max_index = k
      end
    end
    -- Verify no gaps
    if is_array and max_index ~= #value then
      is_array = false
    end

    local parts = {}
    if is_array and #value > 0 then
      for _, v in ipairs(value) do
        table.insert(parts, pad_inner .. serialize_lua(v, indent + 1))
      end
    else
      -- Sort keys for deterministic output
      local keys = {}
      for k, _ in pairs(value) do
        table.insert(keys, k)
      end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      for _, k in ipairs(keys) do
        local key_str
        if type(k) == "string" and k:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
          key_str = k
        else
          key_str = "[" .. serialize_lua(k, 0) .. "]"
        end
        table.insert(parts, pad_inner .. key_str .. " = " .. serialize_lua(value[k], indent + 1))
      end
    end

    if #parts == 0 then
      return "{}"
    end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. pad .. "}"
  else
    return "nil"
  end
end

--- Export scripts configuration to a serialized string
---@param scripts table List of script configurations
---@param opts table|nil Export options
---@return string|nil Exported content
---@return string|nil Error message
function M.export_config(scripts, opts)
  opts = opts or {}
  local format = opts.format or "json"
  local exclude_sensitive = opts.exclude_sensitive ~= false -- Default true
  local sensitive_fields = opts.sensitive_fields or SENSITIVE_FIELDS

  if not SUPPORTED_FORMATS[format] then
    return nil, "Unsupported format '" .. format .. "'. Supported: json, lua"
  end

  if not scripts or type(scripts) ~= "table" then
    return nil, "No scripts to export"
  end

  if #scripts == 0 then
    return nil, "No scripts to export"
  end

  -- Filter and prepare scripts for export
  local export_scripts = {}
  for _, script in ipairs(scripts) do
    local filtered = filter_script(script, exclude_sensitive, sensitive_fields)
    table.insert(export_scripts, filtered)
  end

  local export_data = {
    version = 1,
    scripts = export_scripts,
  }

  if format == "json" then
    local ok, encoded = pcall(vim.fn.json_encode, export_data)
    if not ok then
      return nil, "Failed to encode JSON: " .. tostring(encoded)
    end
    return encoded, nil
  elseif format == "lua" then
    local ok, serialized = pcall(function()
      return "return " .. serialize_lua(export_data, 0) .. "\n"
    end)
    if not ok then
      return nil, "Failed to serialize Lua: " .. tostring(serialized)
    end
    return serialized, nil
  end

  return nil, "Unexpected error"
end

--- Export scripts configuration to a file
---@param scripts table List of script configurations
---@param filepath string Output file path
---@param opts table|nil Export options (format auto-detected from extension if not specified)
---@return boolean Success
---@return string|nil Error message
function M.export_to_file(scripts, filepath, opts)
  opts = opts or {}

  -- Auto-detect format from file extension if not specified
  if not opts.format then
    local ext = filepath:match("%.([^%.]+)$")
    if ext == "json" then
      opts.format = "json"
    elseif ext == "lua" then
      opts.format = "lua"
    else
      opts.format = "json"
    end
  end

  local content, err = M.export_config(scripts, opts)
  if not content then
    return false, err
  end

  -- Pretty-print JSON for file output
  if opts.format == "json" then
    content = pretty_print_json(content)
  end

  local expanded_path = vim.fn.expand(filepath)
  local file, open_err = io.open(expanded_path, "w")
  if not file then
    return false, "Failed to open file for writing: " .. tostring(open_err)
  end

  file:write(content)
  file:write("\n")
  file:close()

  return true, nil
end

--- Detect format of a config file by extension
---@param filepath string
---@return string format
local function detect_format(filepath)
  local ext = filepath:match("%.([^%.]+)$")
  if ext == "lua" then
    return "lua"
  end
  return "json"
end

--- Parse imported config content
---@param content string Raw file content
---@param format string Format of the content ("json" or "lua")
---@return table|nil Parsed config data
---@return string|nil Error message
function M.parse_config(content, format)
  if not content or content == "" then
    return nil, "Empty content"
  end

  if format == "json" then
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if not ok then
      return nil, "Invalid JSON: " .. tostring(decoded)
    end
    return decoded, nil
  elseif format == "lua" then
    -- Reject bytecode to prevent sandbox bypass
    if content:sub(1, 1) == "\27" then
      return nil, "Lua bytecode is not allowed for security reasons"
    end

    -- Sandbox: only allow safe operations (no os, io, require, load, dofile, etc.)
    local sandbox = {
      pairs = pairs,
      ipairs = ipairs,
      type = type,
      tostring = tostring,
      tonumber = tonumber,
      table = { insert = table.insert, concat = table.concat },
      string = { format = string.format },
      math = { floor = math.floor },
    }

    -- Load Lua string in a sandboxed environment
    -- Neovim uses LuaJIT (Lua 5.1 compatible), so use loadstring + setfenv
    local chunk, load_err = loadstring(content, "=imported_config")
    if not chunk then
      return nil, "Invalid Lua: " .. tostring(load_err)
    end
    setfenv(chunk, sandbox)
    local ok, result = pcall(chunk)
    if not ok then
      return nil, "Failed to evaluate Lua config: " .. tostring(result)
    end
    if type(result) ~= "table" then
      return nil, "Lua config must return a table"
    end
    return result, nil
  end

  return nil, "Unsupported format: " .. format
end

-- Current config version supported by this module
local CURRENT_VERSION = 1

--- Validate imported config data structure
---@param data table Parsed config data
---@return boolean Valid
---@return string|nil Error message
function M.validate_config(data)
  if type(data) ~= "table" then
    return false, "Config must be a table"
  end

  -- Validate version field
  if data.version ~= nil then
    if type(data.version) ~= "number" then
      return false, "Config 'version' must be a number"
    end
    if data.version > CURRENT_VERSION then
      return false,
        "Config version "
          .. data.version
          .. " is not supported (max supported: "
          .. CURRENT_VERSION
          .. "). Please update TermLet."
    end
  end

  if not data.scripts then
    return false, "Config missing 'scripts' field"
  end

  if type(data.scripts) ~= "table" then
    return false, "'scripts' must be a list"
  end

  -- Validate each script entry
  local seen_names = {}
  for i, script in ipairs(data.scripts) do
    if type(script) ~= "table" then
      return false, "Script entry " .. i .. " must be a table"
    end
    if not script.name then
      return false, "Script entry " .. i .. " missing required 'name' field"
    end
    if type(script.name) ~= "string" or script.name == "" then
      return false, "Script entry " .. i .. " has invalid 'name' (must be non-empty string)"
    end
    if not script.filename and not (script.dir_name and script.relative_path) then
      return false,
        "Script '" .. script.name .. "' must specify either 'filename' or both 'dir_name' and 'relative_path'"
    end
    if seen_names[script.name] then
      return false, "Duplicate script name: '" .. script.name .. "'"
    end
    seen_names[script.name] = true

    -- Validate depends_on if present
    if script.depends_on then
      if type(script.depends_on) ~= "table" then
        return false, "Script '" .. script.name .. "' has invalid 'depends_on' (must be a list)"
      end
      for _, dep in ipairs(script.depends_on) do
        if type(dep) ~= "string" then
          return false, "Script '" .. script.name .. "' has non-string dependency"
        end
      end
    end

    -- Validate filters if present
    if script.filters then
      if type(script.filters) ~= "table" then
        return false, "Script '" .. script.name .. "' has invalid 'filters' (must be a table)"
      end
    end
  end

  return true, nil
end

--- Build a preview of what an import would change
---@param existing_scripts table Current scripts
---@param import_scripts table Scripts to import
---@param mode string "merge" or "replace"
---@return table Preview info with fields: added, updated, unchanged, removed
function M.preview_import(existing_scripts, import_scripts, mode)
  mode = mode or "merge"

  local preview = {
    added = {},
    updated = {},
    unchanged = {},
    removed = {},
    mode = mode,
  }

  -- Build lookup of existing scripts by name
  local existing_map = {}
  for _, script in ipairs(existing_scripts or {}) do
    existing_map[script.name] = script
  end

  -- Build lookup of imported scripts by name
  local import_map = {}
  for _, script in ipairs(import_scripts or {}) do
    import_map[script.name] = script
  end

  -- Check each imported script
  for _, script in ipairs(import_scripts or {}) do
    if existing_map[script.name] then
      -- Check if it's actually different
      local existing_json = vim.fn.json_encode(existing_map[script.name])
      local import_json = vim.fn.json_encode(script)
      if existing_json == import_json then
        table.insert(preview.unchanged, script.name)
      else
        table.insert(preview.updated, script.name)
      end
    else
      table.insert(preview.added, script.name)
    end
  end

  -- In replace mode, existing scripts not in import list are removed
  if mode == "replace" then
    for _, script in ipairs(existing_scripts or {}) do
      if not import_map[script.name] then
        table.insert(preview.removed, script.name)
      end
    end
  end

  return preview
end

--- Format a preview for display
---@param preview table Preview from preview_import()
---@return string Formatted preview text
function M.format_preview(preview)
  local lines = {}
  table.insert(lines, "Import Preview (mode: " .. preview.mode .. ")")
  table.insert(lines, string.rep("-", 40))

  if #preview.added > 0 then
    table.insert(lines, "")
    table.insert(lines, "New scripts to add:")
    for _, name in ipairs(preview.added) do
      table.insert(lines, "  + " .. name)
    end
  end

  if #preview.updated > 0 then
    table.insert(lines, "")
    table.insert(lines, "Scripts to update:")
    for _, name in ipairs(preview.updated) do
      table.insert(lines, "  ~ " .. name)
    end
  end

  if #preview.unchanged > 0 then
    table.insert(lines, "")
    table.insert(lines, "Unchanged scripts:")
    for _, name in ipairs(preview.unchanged) do
      table.insert(lines, "  = " .. name)
    end
  end

  if #preview.removed > 0 then
    table.insert(lines, "")
    table.insert(lines, "Scripts to remove:")
    for _, name in ipairs(preview.removed) do
      table.insert(lines, "  - " .. name)
    end
  end

  local total_changes = #preview.added + #preview.updated + #preview.removed
  table.insert(lines, "")
  if total_changes == 0 then
    table.insert(lines, "No changes to apply.")
  else
    table.insert(lines, total_changes .. " change(s) to apply.")
  end

  return table.concat(lines, "\n")
end

--- Merge imported scripts into existing scripts
---@param existing_scripts table Current scripts
---@param import_scripts table Scripts to import
---@param mode string "merge" or "replace"
---@return table Resulting merged scripts list
function M.merge_scripts(existing_scripts, import_scripts, mode)
  mode = mode or "merge"

  if mode == "replace" then
    -- Replace: use imported scripts directly
    local result = {}
    for _, script in ipairs(import_scripts) do
      table.insert(result, vim.deepcopy(script))
    end
    return result
  end

  -- Merge: update existing scripts and add new ones
  local result = {}
  local import_map = {}
  for _, script in ipairs(import_scripts) do
    import_map[script.name] = script
  end

  -- Process existing scripts (update if imported version exists)
  local processed = {}
  for _, script in ipairs(existing_scripts or {}) do
    if import_map[script.name] then
      -- Merge: imported values override existing
      local merged = vim.tbl_deep_extend("force", vim.deepcopy(script), import_map[script.name])
      table.insert(result, merged)
      processed[script.name] = true
    else
      table.insert(result, vim.deepcopy(script))
    end
  end

  -- Add new scripts from import that don't exist yet
  for _, script in ipairs(import_scripts) do
    if not processed[script.name] then
      table.insert(result, vim.deepcopy(script))
    end
  end

  return result
end

--- Import configuration from a file
---@param filepath string Path to config file
---@param opts table|nil Import options
---@return table|nil Parsed and validated config
---@return string|nil Error message
function M.import_from_file(filepath, opts)
  opts = opts or {}

  local expanded_path = vim.fn.expand(filepath)

  -- Check file exists
  if vim.fn.filereadable(expanded_path) ~= 1 then
    return nil, "File not found: " .. expanded_path
  end

  -- Read file content
  local file, open_err = io.open(expanded_path, "r")
  if not file then
    return nil, "Failed to open file: " .. tostring(open_err)
  end

  local content = file:read("*a")
  file:close()

  -- Detect format
  local format = opts.format or detect_format(filepath)

  -- Parse content
  local data, parse_err = M.parse_config(content, format)
  if not data then
    return nil, parse_err
  end

  -- Validate
  local valid, validate_err = M.validate_config(data)
  if not valid then
    return nil, validate_err
  end

  return data, nil
end

--- Get list of supported export formats
---@return table List of format strings
function M.get_supported_formats()
  local formats = {}
  for format, _ in pairs(SUPPORTED_FORMATS) do
    table.insert(formats, format)
  end
  table.sort(formats)
  return formats
end

--- Get the default sensitive fields list
---@return table List of field names
function M.get_sensitive_fields()
  return vim.deepcopy(SENSITIVE_FIELDS)
end

-- Expose internals for testing
M._is_sensitive_field = is_sensitive_field
M._filter_script = filter_script
M._serialize_lua = serialize_lua
M._detect_format = detect_format
M._pretty_print_json = pretty_print_json

return M
