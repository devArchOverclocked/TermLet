-- Luacheck configuration for TermLet.nvim

std = "luajit"
cache = true

-- Neovim globals (read-write since plugins set vim.o, vim.bo, vim.wo, vim.opt)
globals = {
  "vim",
}

-- Max line length (match stylua column_width)
max_line_length = 120
max_code_line_length = 120
max_string_line_length = false
max_comment_line_length = false

-- Ignore unused self parameter (common in OOP-style Lua)
self = false

-- Files configuration
files["tests/**/*_spec.lua"] = {
  -- Plenary busted globals
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "setup",
    "teardown",
    "pending",
    "assert",
  },
}

files["tests/minimal_init.lua"] = {
  globals = {
    "vim",
  },
}

-- Ignore specific warnings
ignore = {
  "211/_.*",  -- Unused variable starting with underscore
  "212/_.*",  -- Unused argument starting with underscore
  "213/_.*",  -- Unused loop variable starting with underscore
  "221/_.*",  -- Underscore-prefixed variable is never set
  "231/_.*",  -- Underscore-prefixed variable is never accessed
  "311/_.*",  -- Value assigned to underscore-prefixed variable is unused
  "611",      -- Line contains only whitespace (stylua handles formatting)
  "631",      -- Line is too long (stylua handles line length)
}
