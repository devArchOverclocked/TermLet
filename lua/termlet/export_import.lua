-- TermLet Export/Import Module
-- Enables sharing script configurations through export/import functionality
-- Supports JSON format with sensitive data stripping and merge/replace import modes

local M = {}

-- Module state
local state = {
  buf = nil,
  win = nil,
  preview_data = nil, -- Parsed import data awaiting confirmation
  preview_callback = nil, -- Callback for import confirmation
  preview_mode = "merge", -- "merge" or "replace"
}

-- Highlight namespace
local ns_id = vim.api.nvim_create_namespace("termlet_export_import")

-- Default preview UI configuration
local default_preview_config = {
  width_ratio = 0.7,
  height_ratio = 0.6,
  border = "rounded",
  title = " TermLet Import Preview ",
  highlight = {
    selected = "CursorLine",
    title = "Title",
    help = "Comment",
    added = "DiagnosticOk",
    conflict = "DiagnosticWarn",
  },
}

-- Fields considered sensitive and stripped during export
local sensitive_fields = {
  "env",
  "root_dir",
  "search_dirs",
}

-- Fields that are valid for a script configuration
local valid_script_fields = {
  name = "string",
  filename = "string",
  cmd = "string",
  description = "string",
  dir_name = "string",
  relative_path = "string",
  root_dir = "string",
  search_dirs = "table",
  depends_on = "table",
  run_after_deps = "string",
  filters = "table",
  env = "table",
}

--- Strip sensitive fields from a script configuration
---@param script table Script configuration
---@param fields table|nil List of field names to strip (defaults to sensitive_fields)
---@return table Cleaned script configuration
local function strip_sensitive(script, fields)
  fields = fields or sensitive_fields
  local cleaned = {}
  local strip_set = {}
  for _, field in ipairs(fields) do
    strip_set[field] = true
  end

  for key, value in pairs(script) do
    if not strip_set[key] then
      if type(value) == "table" then
        cleaned[key] = vim.deepcopy(value)
      else
        cleaned[key] = value
      end
    end
  end

  return cleaned
end

--- Check if a path contains traversal components (e.g., "..")
---@param path string Path to check
---@return boolean has_traversal
local function has_path_traversal(path)
  for component in path:gmatch("[^/\\]+") do
    if component == ".." then
      return true
    end
  end
  return false
end

--- Validate a single script configuration
---@param script table Script to validate
---@return boolean valid
---@return string|nil error_message
local function validate_script(script)
  if type(script) ~= "table" then
    return false, "Script must be a table"
  end

  if not script.name or type(script.name) ~= "string" or script.name == "" then
    return false, "Script must have a non-empty 'name' string field"
  end

  -- Must have either filename or dir_name+relative_path
  local has_filename = script.filename and type(script.filename) == "string"
  local has_legacy = script.dir_name
    and type(script.dir_name) == "string"
    and script.relative_path
    and type(script.relative_path) == "string"

  if not has_filename and not has_legacy then
    return false, "Script '" .. script.name .. "' must have 'filename' or both 'dir_name' and 'relative_path'"
  end

  -- Validate that filename does not contain path traversal
  if has_filename and has_path_traversal(script.filename) then
    return false, "Script '" .. script.name .. "': filename must not contain '..' path traversal"
  end

  -- Validate that relative_path does not contain path traversal
  if has_legacy and has_path_traversal(script.relative_path) then
    return false, "Script '" .. script.name .. "': relative_path must not contain '..' path traversal"
  end

  -- Validate field types
  for key, value in pairs(script) do
    local expected_type = valid_script_fields[key]
    if expected_type and type(value) ~= expected_type then
      return false,
        "Script '" .. script.name .. "': field '" .. key .. "' should be " .. expected_type .. ", got " .. type(value)
    end
  end

  -- Validate depends_on entries are strings
  if script.depends_on then
    for i, dep in ipairs(script.depends_on) do
      if type(dep) ~= "string" then
        return false, "Script '" .. script.name .. "': depends_on[" .. i .. "] must be a string"
      end
    end
  end

  -- Validate run_after_deps value
  if script.run_after_deps then
    local valid_modes = { all = true, any = true, none = true }
    if not valid_modes[script.run_after_deps] then
      return false, "Script '" .. script.name .. "': run_after_deps must be 'all', 'any', or 'none'"
    end
  end

  return true, nil
end

--- Validate an import data structure
---@param data table Parsed import data
---@return boolean valid
---@return string|nil error_message
function M.validate_import_data(data)
  if type(data) ~= "table" then
    return false, "Import data must be a table"
  end

  if not data.scripts or type(data.scripts) ~= "table" then
    return false, "Import data must contain a 'scripts' table"
  end

  if #data.scripts == 0 then
    return false, "Import data contains no scripts"
  end

  -- Validate each script
  local seen_names = {}
  for i, script in ipairs(data.scripts) do
    local valid, err = validate_script(script)
    if not valid then
      return false, "Script " .. i .. ": " .. err
    end

    -- Check for duplicate names
    if seen_names[script.name] then
      return false, "Duplicate script name: '" .. script.name .. "'"
    end
    seen_names[script.name] = true
  end

  return true, nil
end

--- Export scripts to JSON format
---@param scripts table List of script configurations
---@param opts table|nil Export options: { strip_sensitive = true, include_fields = nil, strip_fields = nil }
---@return string|nil json_string
---@return string|nil error_message
function M.export_json(scripts, opts)
  opts = opts or {}
  local strip = opts.strip_sensitive ~= false -- Default: true

  if not scripts or type(scripts) ~= "table" or #scripts == 0 then
    return nil, "No scripts to export"
  end

  -- Build export data
  local export_scripts = {}
  for _, script in ipairs(scripts) do
    local exported
    if strip then
      exported = strip_sensitive(script, opts.strip_fields)
    else
      exported = vim.deepcopy(script)
    end

    -- Only include specified fields if include_fields is set
    if opts.include_fields then
      local filtered = {}
      local include_set = {}
      for _, field in ipairs(opts.include_fields) do
        include_set[field] = true
      end
      -- Always include name and filename/dir_name+relative_path
      include_set["name"] = true
      include_set["filename"] = true
      include_set["dir_name"] = true
      include_set["relative_path"] = true

      for key, value in pairs(exported) do
        if include_set[key] then
          filtered[key] = value
        end
      end
      exported = filtered
    end

    -- Remove internal/runtime fields that shouldn't be exported
    exported.on_stdout = nil
    exported.on_exit = nil

    table.insert(export_scripts, exported)
  end

  local export_data = {
    version = 1,
    scripts = export_scripts,
  }

  -- Metadata
  if opts.include_metadata ~= false then
    export_data.metadata = {
      exported_at = os.date("%Y-%m-%dT%H:%M:%S"),
      script_count = #export_scripts,
    }
  end

  local ok, json_str = pcall(vim.fn.json_encode, export_data)
  if not ok then
    return nil, "Failed to encode JSON: " .. tostring(json_str)
  end

  return json_str, nil
end

--- Export scripts to a file
---@param scripts table List of script configurations
---@param filepath string Output file path
---@param opts table|nil Export options (same as export_json)
---@return boolean success
---@return string|nil error_message
function M.export_to_file(scripts, filepath, opts)
  local json_str, err = M.export_json(scripts, opts)
  if not json_str then
    return false, err
  end

  -- Expand path
  filepath = vim.fn.expand(filepath)

  -- Ensure parent directory exists
  local parent_dir = vim.fn.fnamemodify(filepath, ":h")
  if vim.fn.isdirectory(parent_dir) == 0 then
    return false, "Directory does not exist: " .. parent_dir
  end

  -- Write atomically: write to temp file then rename
  local tmpfile = filepath .. ".tmp." .. tostring(os.time())
  local file, write_err = io.open(tmpfile, "w")
  if not file then
    return false, "Failed to open temp file for writing: " .. tostring(write_err)
  end

  file:write(json_str)
  file:write("\n")
  file:close()

  local rename_ok, rename_err = os.rename(tmpfile, filepath)
  if not rename_ok then
    os.remove(tmpfile)
    return false, "Failed to rename temp file: " .. tostring(rename_err)
  end

  return true, nil
end

--- Parse JSON import data from a string
---@param json_str string JSON string
---@return table|nil data
---@return string|nil error_message
function M.parse_json(json_str)
  if not json_str or json_str == "" then
    return nil, "Empty input"
  end

  local ok, data = pcall(vim.fn.json_decode, json_str)
  if not ok then
    return nil, "Invalid JSON: " .. tostring(data)
  end

  return data, nil
end

--- Import scripts from a file
---@param filepath string Input file path
---@return table|nil data Parsed and validated import data
---@return string|nil error_message
function M.import_from_file(filepath)
  -- Expand path
  filepath = vim.fn.expand(filepath)

  if vim.fn.filereadable(filepath) ~= 1 then
    return nil, "File not found: " .. filepath
  end

  local file, read_err = io.open(filepath, "r")
  if not file then
    return nil, "Failed to open file: " .. tostring(read_err)
  end

  local content = file:read("*a")
  file:close()

  if not content or content == "" then
    return nil, "File is empty: " .. filepath
  end

  -- Parse as JSON (the only supported format)
  local data, err = M.parse_json(content)

  if not data then
    return nil, err
  end

  -- Validate
  local valid, validate_err = M.validate_import_data(data)
  if not valid then
    return nil, validate_err
  end

  return data, nil
end

--- Merge imported scripts with existing scripts
--- New scripts are added, existing scripts with the same name are updated
---@param existing table Existing scripts list
---@param imported table Imported scripts list
---@return table merged Merged scripts list
---@return table changes Summary of changes { added = {}, updated = {}, unchanged = {} }
function M.merge_scripts(existing, imported)
  -- Build lookup of existing scripts by name
  local existing_map = {}
  for i, script in ipairs(existing) do
    existing_map[script.name] = { index = i, script = script }
  end

  local merged = vim.deepcopy(existing)
  local changes = {
    added = {},
    updated = {},
    unchanged = {},
  }

  for _, imp_script in ipairs(imported) do
    local existing_entry = existing_map[imp_script.name]
    if existing_entry then
      -- Update existing script (merge fields)
      merged[existing_entry.index] = vim.tbl_deep_extend("force", existing_entry.script, imp_script)
      table.insert(changes.updated, imp_script.name)
    else
      -- Add new script
      table.insert(merged, vim.deepcopy(imp_script))
      table.insert(changes.added, imp_script.name)
    end
  end

  -- Track unchanged scripts
  for _, script in ipairs(existing) do
    local found = false
    for _, name in ipairs(changes.updated) do
      if name == script.name then
        found = true
        break
      end
    end
    if not found then
      table.insert(changes.unchanged, script.name)
    end
  end

  return merged, changes
end

--- Calculate preview window dimensions
---@param config table UI configuration
---@return table Window options for nvim_open_win
local function calculate_window_opts(config)
  local width = math.floor(vim.o.columns * config.width_ratio)
  local height = math.floor(vim.o.lines * config.height_ratio)

  -- Minimum dimensions
  width = math.max(width, 60)
  height = math.max(height, 15)

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
    footer = " [Enter] Confirm  [m] Toggle Mode  [q] Cancel ",
    footer_pos = "center",
  }
end

--- Render the import preview UI
local function render_preview()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local config = state.preview_config or default_preview_config
  local win_opts = calculate_window_opts(config)
  local width = win_opts.width - 2 -- Account for borders

  -- Clear existing content and highlights
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

  local lines = {}
  local highlights = {}

  -- Header
  table.insert(lines, "")
  local mode_str = state.preview_mode == "merge" and "MERGE" or "REPLACE"
  local header = "  Import Mode: " .. mode_str
  table.insert(lines, header)
  table.insert(highlights, { line = #lines - 1, group = config.highlight.title })
  table.insert(lines, "  " .. string.rep("─", width - 4))

  if state.preview_data and state.preview_data.scripts then
    -- Show metadata if available
    if state.preview_data.metadata then
      local meta = state.preview_data.metadata
      if meta.exported_at then
        table.insert(lines, "  Exported: " .. meta.exported_at)
        table.insert(highlights, { line = #lines - 1, group = config.highlight.help })
      end
      if meta.script_count then
        table.insert(lines, "  Scripts: " .. meta.script_count)
        table.insert(highlights, { line = #lines - 1, group = config.highlight.help })
      end
      table.insert(lines, "")
    end

    -- Show changes summary
    if state.preview_changes then
      local changes = state.preview_changes
      if #changes.added > 0 then
        table.insert(lines, "  + New: " .. table.concat(changes.added, ", "))
        table.insert(highlights, { line = #lines - 1, group = config.highlight.added })
      end
      if #changes.updated > 0 then
        table.insert(lines, "  ~ Updated: " .. table.concat(changes.updated, ", "))
        table.insert(highlights, { line = #lines - 1, group = config.highlight.conflict })
      end
      if #changes.unchanged > 0 then
        table.insert(lines, "  = Unchanged: " .. table.concat(changes.unchanged, ", "))
        table.insert(highlights, { line = #lines - 1, group = config.highlight.help })
      end
      table.insert(lines, "")
    end

    table.insert(lines, "  " .. string.rep("─", width - 4))
    table.insert(lines, "")

    -- Show scripts to import
    table.insert(lines, "  Scripts:")
    table.insert(highlights, { line = #lines - 1, group = config.highlight.title })
    table.insert(lines, "")

    for _, script in ipairs(state.preview_data.scripts) do
      local line = "    " .. script.name
      if script.description then
        line = line .. " - " .. script.description
      end
      table.insert(lines, line)

      -- Show script details
      if script.filename then
        table.insert(lines, "      filename: " .. script.filename)
        table.insert(highlights, { line = #lines - 1, group = config.highlight.help })
      end
      if script.cmd then
        table.insert(lines, "      cmd: " .. script.cmd)
        table.insert(highlights, { line = #lines - 1, group = config.highlight.help })
      end
      if script.depends_on and #script.depends_on > 0 then
        table.insert(lines, "      depends_on: " .. table.concat(script.depends_on, ", "))
        table.insert(highlights, { line = #lines - 1, group = config.highlight.help })
      end
      table.insert(lines, "")
    end
  else
    table.insert(lines, "")
    table.insert(lines, "    No scripts found in import data")
    table.insert(lines, "")
  end

  -- Pad to fill window
  local target_height = win_opts.height - 2
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

--- Toggle import mode between merge and replace
local function toggle_mode()
  if state.preview_mode == "merge" then
    state.preview_mode = "replace"
  else
    state.preview_mode = "merge"
  end

  -- Recalculate changes based on new mode
  if state.preview_mode == "replace" then
    state.preview_changes = {
      added = {},
      updated = {},
      unchanged = {},
    }
    for _, script in ipairs(state.preview_data.scripts) do
      table.insert(state.preview_changes.added, script.name)
    end
  elseif state.existing_scripts then
    local _, changes = M.merge_scripts(state.existing_scripts, state.preview_data.scripts)
    state.preview_changes = changes
  end

  render_preview()
end

--- Confirm import
local function confirm_import()
  if not state.preview_data or not state.preview_callback then
    return
  end

  local data = state.preview_data
  local mode = state.preview_mode
  local callback = state.preview_callback

  M.close_preview()

  vim.schedule(function()
    callback(data, mode)
  end)
end

--- Set up keymaps for the preview buffer
local function setup_keymaps()
  local buf = state.buf
  local opts = { noremap = true, silent = true, buffer = buf }

  vim.keymap.set("n", "<CR>", confirm_import, opts)
  vim.keymap.set("n", "<Enter>", confirm_import, opts)
  vim.keymap.set("n", "m", toggle_mode, opts)
  vim.keymap.set("n", "q", M.close_preview, opts)
  vim.keymap.set("n", "<Esc>", M.close_preview, opts)
end

--- Open import preview UI
---@param import_data table Parsed import data
---@param existing_scripts table Current scripts for merge comparison
---@param callback function Called with (data, mode) on confirmation
---@param ui_config table|nil Optional UI configuration
---@return boolean success
function M.open_preview(import_data, existing_scripts, callback, ui_config)
  -- Close existing window if open
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close_preview()
  end

  if not import_data or not import_data.scripts or #import_data.scripts == 0 then
    vim.notify("No scripts to import", vim.log.levels.WARN)
    return false
  end

  -- Initialize state
  state.preview_data = import_data
  state.preview_callback = callback
  state.preview_mode = "merge"
  state.existing_scripts = existing_scripts
  state.preview_config = vim.tbl_deep_extend("force", default_preview_config, ui_config or {})

  -- Calculate initial changes for merge mode
  local _, changes = M.merge_scripts(existing_scripts or {}, import_data.scripts)
  state.preview_changes = changes

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  if not state.buf then
    vim.notify("Failed to create preview buffer", vim.log.levels.ERROR)
    return false
  end

  -- Set buffer options
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "termlet_import_preview"
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].modifiable = false

  -- Create window
  local win_opts = calculate_window_opts(state.preview_config)
  state.win = vim.api.nvim_open_win(state.buf, true, win_opts)

  if not state.win then
    vim.api.nvim_buf_delete(state.buf, { force = true })
    vim.notify("Failed to create preview window", vim.log.levels.ERROR)
    return false
  end

  -- Set window options
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].wrap = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"

  -- Set up keymaps
  setup_keymaps()

  -- Render initial content
  render_preview()

  return true
end

--- Close the preview UI
function M.close_preview()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.preview_data = nil
  state.preview_callback = nil
  state.preview_changes = nil
  state.existing_scripts = nil
end

--- Check if preview UI is currently open
---@return boolean
function M.is_preview_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Get current state (for testing)
---@return table
function M.get_state()
  return {
    preview_mode = state.preview_mode,
    is_open = M.is_preview_open(),
    has_data = state.preview_data ~= nil,
  }
end

-- Expose internal functions for testing
M._strip_sensitive = strip_sensitive
M._validate_script = validate_script
M._has_path_traversal = has_path_traversal

return M
