-- Built-in Python stack trace parser
-- Supports standard Python traceback format

local M = {
  name = "python",
  description = "Python stack traces and tracebacks",

  patterns = {
    {
      -- Standard Python traceback format
      -- Example: '  File "/path/to/file.py", line 42, in function_name'
      pattern = '%s*File%s+"([^"]+)",%s+line%s+(%d+)',
      path_group = 1,
      line_group = 2,
    },
    {
      -- Alternative format with single quotes
      -- Example: "  File '/path/to/file.py', line 42, in function_name"
      pattern = "%s*File%s+'([^']+)',%s+line%s+(%d+)",
      path_group = 1,
      line_group = 2,
    },
    {
      -- pytest format
      -- Example: "tests/test_module.py:42: AssertionError"
      pattern = "([%w_/%.%-]+%.py):(%d+):",
      path_group = 1,
      line_group = 2,
    },
  },

  -- Custom path resolver for Python
  resolve_path = function(path, cwd)
    -- If path is absolute, return as-is
    if vim.fn.fnamemodify(path, ":p") == path then
      return path
    end

    -- Try relative to current working directory
    local full_path = cwd .. "/" .. path
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end

    -- Return original path if not found
    return path
  end,

  -- Context detector for improved accuracy
  is_context_match = function(lines, index)
    -- Look for Python-specific indicators in surrounding lines
    for i = math.max(1, index - 3), math.min(#lines, index + 3) do
      local line = lines[i]
      if line and (
        line:match("Traceback") or
        line:match("File.*%.py") or
        line:match("Error:") or
        line:match("Exception:")
      ) then
        return true
      end
    end
    return false
  end,
}

return M
