# Stack Trace Parser Development Guide

This guide explains how to create custom stack trace parsers for TermLet's extensible parser plugin architecture.

## Table of Contents

- [Overview](#overview)
- [Parser Structure](#parser-structure)
- [Pattern Syntax](#pattern-syntax)
- [Creating a Custom Parser](#creating-a-custom-parser)
- [Built-in Parsers](#built-in-parsers)
- [Testing Your Parser](#testing-your-parser)
- [Best Practices](#best-practices)

## Overview

TermLet's parser plugin architecture allows you to add support for any programming language's stack trace format without modifying TermLet's core code. Parsers use Lua patterns to extract file paths, line numbers, and optional column numbers from stack trace output.

## Parser Structure

A parser is a Lua table with the following structure:

```lua
local my_parser = {
  -- Required: Unique identifier for this parser
  name = "my_language",

  -- Optional: Human-readable description
  description = "My Language stack traces",

  -- Required: Array of pattern definitions (at least one)
  patterns = {
    {
      -- Required: Lua pattern to match stack trace lines
      pattern = "...",

      -- Required: Capture group number for file path (1-based)
      path_group = 1,

      -- Required: Capture group number for line number (1-based)
      line_group = 2,

      -- Optional: Capture group number for column number
      column_group = 3,
    },
    -- You can add multiple patterns for different formats
  },

  -- Optional: Custom path resolver function
  resolve_path = function(path, cwd)
    -- Convert relative path to absolute
    return resolved_path
  end,

  -- Optional: Context detector for improved accuracy
  is_context_match = function(lines, index)
    -- Check if surrounding lines indicate this language
    return true
  end,
}
```

### Required Fields

- `name` (string): Unique identifier for the parser
- `patterns` (table): Array of at least one pattern definition

Each pattern must have:
- `pattern` (string): Valid Lua pattern with capture groups
- `path_group` (number): Which capture group contains the file path
- `line_group` (number): Which capture group contains the line number

### Optional Fields

- `description` (string): Human-readable description
- `column_group` (number): Which capture group contains the column number
- `resolve_path` (function): Custom path resolution logic
- `is_context_match` (function): Context detection for improved accuracy

## Pattern Syntax

Parsers use Lua patterns (similar to regex but simpler). Here are common patterns:

| Pattern | Matches | Example |
|---------|---------|---------|
| `%d+` | One or more digits | Line numbers: `42`, `123` |
| `[^:]+` | Any characters except `:` | File paths: `file.py` |
| `%s+` | One or more whitespace | Indentation |
| `%.` | Literal `.` | File extensions: `%.py` |
| `()` | Capture group | Extract values |

### Capture Groups

Capture groups extract values from matched text:

```lua
pattern = '  File "([^"]+)", line (%d+)'
          --        ^1^           ^2^
-- Capture group 1: file path
-- Capture group 2: line number
```

Set `path_group = 1` and `line_group = 2` to use these captures.

### Example Patterns

**Python traceback:**
```lua
pattern = '%s*File%s+"([^"]+)",%s+line%s+(%d+)'
```
Matches: `  File "/path/file.py", line 42`

**JavaScript:**
```lua
pattern = "at%s+.-%s+%(([^:)]+):(%d+):?(%d*)%)"
```
Matches: `at functionName (/path/file.js:42:15)`

**Java:**
```lua
pattern = "%s+at%s+[%w%.]+%(([^:]+%.java):(%d+)%)"
```
Matches: `	at com.example.Class.method(File.java:42)`

## Creating a Custom Parser

### Step 1: Copy the Template

Start with the template parser:

```bash
cp lua/termlet/parsers/template.lua lua/termlet/parsers/my_language.lua
```

### Step 2: Define Your Patterns

Examine your language's stack trace format and create patterns:

```lua
-- Example: Rust stack traces
local M = {
  name = "rust",
  description = "Rust panic and error traces",

  patterns = {
    {
      -- Format: "  at path/to/file.rs:42:15"
      pattern = "%s+at%s+([^:]+%.rs):(%d+):(%d+)",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
    {
      -- Format: "thread 'main' panicked at file.rs:42:15"
      pattern = "panicked%s+at%s+([^:]+%.rs):(%d+):(%d+)",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
  },
}

return M
```

### Step 3: Add Path Resolution (Optional)

If your language uses special path conventions:

```lua
resolve_path = function(path, cwd)
  -- Handle relative paths
  if not path:match("^/") then
    -- Try common source directories
    local dirs = { "src", "lib", "crates" }
    for _, dir in ipairs(dirs) do
      local full_path = cwd .. "/" .. dir .. "/" .. path
      if vim.fn.filereadable(full_path) == 1 then
        return full_path
      end
    end
  end
  return path
end
```

### Step 4: Add Context Detection (Optional)

Improve accuracy by checking surrounding lines:

```lua
is_context_match = function(lines, index)
  for i = math.max(1, index - 3), math.min(#lines, index + 3) do
    local line = lines[i]
    if line and (
      line:match("thread .+ panicked") or
      line:match("Error:") or
      line:match("%.rs:")
    ) then
      return true
    end
  end
  return false
end
```

### Step 5: Register Your Parser

#### Method 1: Configuration File

```lua
require('termlet').setup({
  stacktrace = {
    enabled = true,
    custom_parsers = {
      require('my_rust_parser'),  -- Your custom parser
    },
  }
})
```

#### Method 2: Runtime Registration

```lua
local my_parser = require('my_rust_parser')
require('termlet.stacktrace').register_parser(my_parser)
```

## Built-in Parsers

TermLet includes parsers for common languages:

### Python
Enable: `languages = { 'python' }`

Formats supported:
- Standard traceback: `File "/path/file.py", line 42`
- Single quotes: `File '/path/file.py', line 42`
- pytest: `tests/test_file.py:42: Error`

### C#
Enable: `languages = { 'csharp' }`

Formats supported:
- .NET stack trace: `at Class.Method() in File.cs:line 42`
- MSBuild: `File.cs(42,15): error CS1234`

### JavaScript
Enable: `languages = { 'javascript' }`

Formats supported:
- Node.js: `at function (/path/file.js:42:15)`
- Browser: `at http://localhost/app.js:42:15`
- Webpack: `webpack:///./src/App.jsx:42:15`

### Java
Enable: `languages = { 'java' }`

Formats supported:
- Stack trace: `at com.example.Class.method(File.java:42)`
- Compiler: `File.java:42: error: message`
- Maven: `[ERROR] /path/File.java:[42,15] error`

## Testing Your Parser

### Unit Tests

Create a test file for your parser:

```lua
-- tests/my_parser_spec.lua
describe("my_language parser", function()
  local stacktrace

  before_each(function()
    package.loaded["termlet.stacktrace"] = nil
    stacktrace = require("termlet.stacktrace")
    stacktrace.clear_parsers()

    local my_parser = require("my_language_parser")
    stacktrace.register_parser(my_parser)
  end)

  it("should parse standard format", function()
    local line = "Error at file.ext:42:15"
    local result = stacktrace.parse_line(line)

    assert.is_not_nil(result)
    assert.are.equal("my_language", result.parser_name)
    assert.are.equal("file.ext", result.file_path)
    assert.are.equal(42, result.line_number)
    assert.are.equal(15, result.column_number)
  end)
end)
```

Run tests:
```bash
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

### Manual Testing

Test with real stack traces:

```lua
local stacktrace = require('termlet.stacktrace')
local my_parser = require('my_parser')

stacktrace.register_parser(my_parser)

-- Test a sample line
local result = stacktrace.parse_line("your stack trace line here")
print(vim.inspect(result))
```

## Best Practices

### 1. Start Simple
Begin with the most common format and add variants later:

```lua
patterns = {
  {
    -- Start with the most common format
    pattern = "simple pattern",
    path_group = 1,
    line_group = 2,
  },
  -- Add more complex formats as needed
}
```

### 2. Test Pattern Matching

Use Lua's string.match to test patterns:

```lua
local test_line = "  File /path/file.py:42"
local path, line = string.match(test_line, "File%s+([^:]+):(%d+)")
print("Path:", path, "Line:", line)
```

### 3. Handle Multiple Formats

Languages often have multiple stack trace formats:

```lua
patterns = {
  { pattern = "format1", path_group = 1, line_group = 2 },
  { pattern = "format2", path_group = 1, line_group = 2 },
  { pattern = "format3", path_group = 1, line_group = 2 },
}
```

### 4. Use Specific Patterns

Make patterns as specific as possible to avoid false matches:

**Bad:** `([^:]+):(%d+)` (too generic)
**Good:** `%s+at%s+[%w%.]+%(([^:]+%.java):(%d+)%)` (specific to Java)

### 5. Path Resolution

Consider common project structures:

```lua
resolve_path = function(path, cwd)
  -- Try common directories
  local dirs = { "src", "lib", "tests", "include" }

  for _, dir in ipairs(dirs) do
    local test_path = cwd .. "/" .. dir .. "/" .. path
    if vim.fn.filereadable(test_path) == 1 then
      return test_path
    end
  end

  return path
end
```

### 6. Context Detection

Use distinctive keywords from your language:

```lua
is_context_match = function(lines, index)
  for i = math.max(1, index - 3), math.min(#lines, index + 3) do
    if lines[i] and (
      lines[i]:match("MyLanguageError") or
      lines[i]:match("MyLanguageException") or
      lines[i]:match("%.mylang:")
    ) then
      return true
    end
  end
  return false
end
```

### 7. Document Your Parser

Add comments explaining your patterns:

```lua
patterns = {
  {
    -- Standard error format: "Error: file.ext:42:15"
    pattern = "Error:%s+([^:]+):(%d+):(%d+)",
    path_group = 1,
    line_group = 2,
    column_group = 3,
  },
}
```

## Example: Complete Custom Parser

Here's a complete example for Go:

```lua
-- lua/termlet/parsers/go.lua
local M = {
  name = "go",
  description = "Go panic and error traces",

  patterns = {
    {
      -- panic format: "	/path/to/file.go:42 +0x123"
      pattern = "%s+([^:]+%.go):(%d+)%s+%+0x",
      path_group = 1,
      line_group = 2,
    },
    {
      -- compiler error: "file.go:42:15: error message"
      pattern = "([%w_/%.%-]+%.go):(%d+):(%d+):",
      path_group = 1,
      line_group = 2,
      column_group = 3,
    },
  ],

  resolve_path = function(path, cwd)
    -- Absolute path
    if path:match("^/") then
      return path
    end

    -- Try relative to cwd
    local full_path = cwd .. "/" .. path
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end

    -- Try GOPATH structure
    local gopath = vim.fn.getenv("GOPATH")
    if gopath and gopath ~= vim.NIL then
      local src_path = gopath .. "/src/" .. path
      if vim.fn.filereadable(src_path) == 1 then
        return src_path
      end
    end

    return path
  end,

  is_context_match = function(lines, index)
    for i = math.max(1, index - 3), math.min(#lines, index + 3) do
      local line = lines[i]
      if line and (
        line:match("panic:") or
        line:match("goroutine %d+") or
        line:match("%.go:")
      ) then
        return true
      end
    end
    return false
  end,
}

return M
```

Register it:

```lua
require('termlet').setup({
  stacktrace = {
    enabled = true,
    custom_parsers = {
      require('termlet.parsers.go'),
    },
  }
})
```

## Getting Help

- Check existing parsers in `lua/termlet/parsers/` for examples
- Use the template parser as a starting point
- Test with real stack traces from your language
- Refer to Lua pattern documentation: https://www.lua.org/manual/5.1/manual.html#5.4.1

## Contributing

If you create a parser for a popular language, consider contributing it to TermLet:
1. Add your parser to `lua/termlet/parsers/`
2. Add tests to `tests/stacktrace_spec.lua`
3. Update this documentation
4. Submit a pull request
