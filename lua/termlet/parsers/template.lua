-- Template parser for creating custom language parsers
-- Copy this file and modify it to create your own parser

local M = {
  -- Required: Unique name for this parser
  name = "my_language",

  -- Optional: Description of what this parser handles
  description = "My custom language stack traces",

  -- Required: Array of pattern definitions
  -- At least one pattern is required
  patterns = {
    {
      -- Lua pattern to match stack trace lines
      -- Use capture groups () to extract file path, line number, and optional column
      pattern = "([^:]+):(%d+):?(%d*)",

      -- Required: Capture group number for file path (1-based)
      path_group = 1,

      -- Required: Capture group number for line number (1-based)
      line_group = 2,

      -- Optional: Capture group number for column number (1-based)
      -- Set to nil or omit if your language doesn't provide column info
      column_group = 3,
    },

    -- You can add multiple patterns for different formats
    -- {
    --   pattern = "File%s+([^,]+),%s+line%s+(%d+)",
    --   path_group = 1,
    --   line_group = 2,
    -- },
  },

  -- Optional: Custom path resolver function
  -- Receives: path (string), cwd (string - current working directory)
  -- Returns: resolved_path (string)
  resolve_path = function(path, cwd)
    -- If path is absolute, return as-is
    if path:match("^/") then
      return path
    end

    -- Try relative to current working directory
    local full_path = cwd .. "/" .. path
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end

    -- Add your custom path resolution logic here
    -- For example, check common source directories:
    -- local common_dirs = { "src", "lib", "include" }
    -- for _, dir in ipairs(common_dirs) do
    --   local test_path = cwd .. "/" .. dir .. "/" .. path
    --   if vim.fn.filereadable(test_path) == 1 then
    --     return test_path
    --   end
    -- end

    -- Return original path if resolution fails
    return path
  end,

  -- Optional: Context detector function
  -- Receives: lines (array of strings), index (current line number)
  -- Returns: boolean (true if this looks like your language's stack trace)
  -- This helps improve detection accuracy by checking surrounding lines
  is_context_match = function(lines, index)
    -- Look for language-specific indicators in nearby lines
    for i = math.max(1, index - 3), math.min(#lines, index + 3) do
      local line = lines[i]
      if line and (
        line:match("Error:") or
        line:match("Exception:") or
        line:match("Traceback")
        -- Add more patterns specific to your language
      ) then
        return true
      end
    end
    return false
  end,
}

return M
