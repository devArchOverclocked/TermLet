-- Example JavaScript/Node.js stack trace parser
-- This is a template that users can enable or customize

local M = {
  name = "javascript",
  description = "Node.js and browser JavaScript stack traces",

  patterns = {
    {
      -- Node.js format: "at functionName (/path/to/file.js:42:15)"
      pattern = "at%s+.-%s+%(([^:)]+):(%d+):?(%d*)%)",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
    {
      -- Browser format: "at http://localhost:3000/app.js:42:15"
      pattern = "at%s+https?://[^/]+/([^:]+):(%d+):?(%d*)",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
    {
      -- Simple format: "at /path/to/file.js:42:15"
      pattern = "at%s+([^:]+%.js):(%d+):?(%d*)",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
    {
      -- Webpack/bundler format with source maps
      -- Example: "webpack:///./src/components/App.jsx:42:15"
      pattern = "webpack:///%.?/?([^:]+):(%d+):?(%d*)",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
  },

  -- Custom path resolver for JavaScript
  resolve_path = function(path, cwd)
    -- Remove leading ./ if present
    local clean_path = path:gsub("^%./", "")

    -- If path is absolute, return as-is
    if clean_path:match("^/") then
      return clean_path
    end

    -- Try relative to current working directory
    local full_path = cwd .. "/" .. clean_path
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end

    -- Try common source directories
    local common_dirs = { "src", "lib", "dist", "build" }
    for _, dir in ipairs(common_dirs) do
      local test_path = cwd .. "/" .. dir .. "/" .. clean_path
      if vim.fn.filereadable(test_path) == 1 then
        return test_path
      end
    end

    -- Return original path if not found
    return path
  end,

  -- Context detector for improved accuracy
  is_context_match = function(lines, index)
    -- Look for JavaScript-specific indicators
    for i = math.max(1, index - 3), math.min(#lines, index + 3) do
      local line = lines[i]
      if
        line
        and (
          line:match("Error:")
          or line:match("at%s+")
          or line:match("%.js:")
          or line:match("%.jsx:")
          or line:match("%.ts:")
          or line:match("%.tsx:")
        )
      then
        return true
      end
    end
    return false
  end,
}

return M
