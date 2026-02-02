-- Built-in C# stack trace parser
-- Supports standard .NET stack trace format

local M = {
  name = "csharp",
  description = "C# and .NET stack traces",

  patterns = {
    {
      -- Windows .NET stack trace format (drive letter path)
      -- Example: "   at ClassName.MethodName() in C:\path\to\File.cs:line 42"
      pattern = "%s+at%s+.-%s+in%s+(%a:\\[^:]+):line%s+(%d+)",
      path_group = 1,
      line_group = 2,
    },
    {
      -- Unix-style path format
      -- Example: "   at ClassName.MethodName() in /path/to/File.cs:line 42"
      pattern = "%s+at%s+.-%s+in%s+(/[^:]+):line%s+(%d+)",
      path_group = 1,
      line_group = 2,
    },
    {
      -- MSBuild error format
      -- Example: "File.cs(42,15): error CS1234: Error message"
      -- Example: "C:\path\File.cs(42,15): error CS1234"
      -- Example: "My Project/File.cs(10,5): error CS1234"
      pattern = "([%w_:/\\ %.%-]+%.cs)%((%d+),?(%d*)%)",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
  },

  -- Custom path resolver for C#
  resolve_path = function(path, cwd)
    -- Handle Windows-style backslashes
    local normalized_path = path:gsub("\\", "/")

    -- If path is absolute, return as-is
    if normalized_path:match("^/") or normalized_path:match("^%a:") then
      return normalized_path
    end

    -- Try relative to current working directory
    local full_path = cwd .. "/" .. normalized_path
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end

    -- Return normalized path if not found
    return normalized_path
  end,

  -- Context detector for improved accuracy
  is_context_match = function(lines, index)
    -- Look for C#-specific indicators in surrounding lines
    for i = math.max(1, index - 3), math.min(#lines, index + 3) do
      local line = lines[i]
      if line and (
        line:match("Exception:") or
        line:match("%s+at%s+") or
        line:match("%.cs%(") or
        line:match(":line%s+%d+")
      ) then
        return true
      end
    end
    return false
  end,
}

return M
