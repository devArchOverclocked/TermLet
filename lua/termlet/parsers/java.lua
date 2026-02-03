-- Example Java stack trace parser
-- This is a template that users can enable or customize

local M = {
  name = "java",
  description = "Java stack traces and exceptions",

  patterns = {
    {
      -- Standard Java stack trace format
      -- Example: "	at com.example.ClassName.methodName(FileName.java:42)"
      pattern = "%s+at%s+[%w%.]+%(([^:]+%.java):(%d+)%)",
      path_group = 1,
      line_group = 2,
    },
    {
      -- Java compiler error format
      -- Example: "FileName.java:42: error: compilation error message"
      pattern = "([%w_/%.%-]+%.java):(%d+):",
      path_group = 1,
      line_group = 2,
    },
    {
      -- Maven/Gradle build format
      -- Example: "[ERROR] /path/to/FileName.java:[42,15] error message"
      pattern = "%[ERROR%]%s+([^:]+%.java):%[(%d+),?(%d*)%]",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
  },

  -- Custom path resolver for Java
  resolve_path = function(path, cwd)
    -- If path is absolute, return as-is
    if path:match("^/") or path:match("^%a:") then
      return path
    end

    -- Try relative to current working directory
    local full_path = cwd .. "/" .. path
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end

    -- Try common Java source directories
    local common_dirs = {
      "src/main/java",
      "src/test/java",
      "src/java",
      "src",
    }

    for _, dir in ipairs(common_dirs) do
      local test_path = cwd .. "/" .. dir .. "/" .. path
      if vim.fn.filereadable(test_path) == 1 then
        return test_path
      end
    end

    -- Try to resolve based on package structure
    -- Convert package.name.ClassName to package/name/ClassName.java
    local package_path = path:gsub("%.", "/")
    for _, dir in ipairs(common_dirs) do
      local test_path = cwd .. "/" .. dir .. "/" .. package_path
      if vim.fn.filereadable(test_path) == 1 then
        return test_path
      end
    end

    -- Return original path if not found
    return path
  end,

  -- Context detector for improved accuracy
  is_context_match = function(lines, index)
    -- Look for Java-specific indicators
    for i = math.max(1, index - 3), math.min(#lines, index + 3) do
      local line = lines[i]
      if
        line
        and (
          line:match("Exception:")
          or line:match("Exception in thread")
          or line:match("%s+at%s+")
          or line:match("%.java:")
          or line:match("Caused by:")
        )
      then
        return true
      end
    end
    return false
  end,
}

return M
