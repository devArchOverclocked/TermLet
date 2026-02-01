# 🧪 TermLet.nvim

**Run, manage, and interact with custom scripts in beautiful floating terminals — directly from Neovim.**

---

## ✨ Features

* 📦 **Run user-defined scripts** from structured configuration
* 🧭 **Auto-discover script paths** from flexible search logic
* 🪟 **Floating terminal windows** with customizable size, borders, and position
* 🎨 **Interactive script menu** - Mason-like popup for browsing and executing scripts
* ⌨️ **Visual keybinding configuration** - Configure keybindings interactively without editing config files
* 🔀 **Dynamic function generation** for each script (e.g. `:lua require('termlet').run_my_script()`)
* 😹 **Terminal cleanup** and safe resource handling
* 🔍 **Stack trace detection** — automatically detect file references in error output and jump to source
* 💾 **Output persistence** — preserve terminal output after window closes for later review
* 🎯 **Smart output filtering** — filter terminal output by patterns and highlight important messages
* 🧪 **Debug-friendly** with verbose logging option

---

## 🚀 Installation

Using [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "devArchOverclocked/termlet",
  config = function()
    require("termlet").setup({
      root_dir = "~/my/project",
      debug = true,
      scripts = {
        {
          name = "build_project",
          filename = "build.sh",
          root_dir = "~/projects/myapp"
        },
        {
          name = "start_server",
          dir_name = "server",
          relative_path = "start.py"
        },
      }
    })
  end
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{
  "devArchOverclocked/termlet",
  config = function()
    require("termlet").setup({
      root_dir = "~/my/project",
      debug    = true,
      scripts  = {
        {
          name      = "build_project",
          filename  = "build.sh",
          root_dir  = "~/projects/myapp",
        },
        {
          name          = "start_server",
          dir_name      = "server",
          relative_path = "start.py",
        },
      },
    })
  end,
},
```

---

## ⚙️ Configuration

Here's the full configuration structure:

```lua
{
  scripts = {},         -- List of scripts with `name` and either `filename` or `dir_name`/`relative_path`
  root_dir = nil,       -- Default root directory for script search
  terminal = {
    height_ratio = 0.16,
    width_ratio = 1.0,
    border = "rounded",           -- "none", "single", "double", "rounded", etc.
    position = "bottom",          -- "bottom", "center", "top"
    output_persistence = "none",  -- "none" | "buffer"
    max_saved_buffers = 5,        -- Maximum number of hidden buffers to keep
    filters = {
      enabled = false,            -- Enable output filtering
      show_only = {},             -- Only show lines matching these patterns
      hide = {},                  -- Hide lines matching these patterns
      highlight = {},             -- Custom highlighting: { pattern = "ERROR", color = "#ff0000" }
    },
  },
  menu = {
    width_ratio = 0.6,  -- Menu window width (fraction of screen)
    height_ratio = 0.5, -- Menu window height (fraction of screen)
    border = "rounded", -- Menu border style
    title = " TermLet Scripts " -- Menu window title
  },
  search = {
    exclude_dirs = {},   -- Directories to exclude from search (defaults include node_modules, .git, etc.)
    exclude_hidden = true, -- Exclude hidden directories (starting with .)
    exclude_patterns = {}, -- Glob patterns to exclude files (e.g., "*.min.*")
    max_depth = 5,       -- Maximum recursion depth for file search
  },
  stacktrace = {
    enabled = true,                     -- Enable stack trace detection
    languages = { 'python', 'csharp' }, -- Built-in parsers to load (empty = all)
    custom_parsers = {},                -- Custom parser definitions
    parser_order = { 'custom', 'builtin' }, -- Parser priority
    buffer_size = 50,                   -- Lines kept in buffer for multi-line detection
  },
  debug = false,        -- Enable verbose debug logging
}
```

Each script object must include:

### With `filename` (Preferred):

```lua
{
  name = "my_script",
  filename = "run.sh",      -- Required
  root_dir = "~/project",   -- Optional (inherits from global root_dir)
  search_dirs = {"scripts"} -- Optional
}
```

The `filename` field supports three resolution modes:

1. **Plain filename** (e.g., `"build.sh"`) — Searched recursively from `root_dir`. You only need to provide the root directory and the filename; TermLet will find it anywhere in the directory tree.
2. **Relative path** (e.g., `"subdir/build.sh"`) — First resolved relative to `root_dir`. If not found, the basename is searched recursively.
3. **Absolute path** (e.g., `"/usr/local/bin/check.sh"` or `"~/scripts/deploy.sh"`) — Used directly, allowing you to run scripts outside of `root_dir`.

### Or with `dir_name` + `relative_path` (Legacy):

```lua
{
  name = "legacy_task",
  dir_name = "tools",
  relative_path = "run_legacy.sh"
}
```

### Recursive File Search

When using `filename` with a `root_dir`, TermLet searches for your script in this order:

1. **Direct match** — `{root_dir}/{filename}`
2. **Common directories** — Checks `scripts/`, `bin/`, `tools/`, `build/`, `.scripts/`, `dev/`, `development/`, `utils/`, `automation/` within `root_dir`
3. **Recursive fallback** — Scans the full directory tree under `root_dir` (up to 5 levels deep)

Hidden directories (starting with `.`) and `node_modules` are excluded from recursive search.

You can customize the search directories per script:

```lua
{
  name = "deploy",
  filename = "deploy.sh",
  root_dir = "~/project",
  search_dirs = { "devops", "ci", "scripts" }
}
```

---

## 🧪 Usage

After setup, functions are auto-generated for each script:

```lua
require("termlet")

vim.keymap.set("n", "<leader>b", function()
  termlet.run_build()
end, { desc = "Run Build Script" })

vim.keymap.set("n", "<leader>t", function()
  termlet.run_test()
end, { desc = "Run Test Script" })

vim.keymap.set("n", "<leader>P", function()
  termlet.run_precommit()
end, { desc = "Precommit" })

vim.keymap.set("n", "<leader>bc", function()
  termlet.close_terminal()
end, { desc = "Close Build Window" })

```

Or call `require("termlet").list_scripts()` to list all configured scripts.

### Interactive Script Menu

Open a Mason-like popup menu to browse and execute scripts:

```lua
vim.keymap.set("n", "<leader>ts", function()
  require("termlet").open_menu()
end, { desc = "Open TermLet Script Menu" })

-- Or use toggle to open/close with the same key
vim.keymap.set("n", "<leader>ts", function()
  require("termlet").toggle_menu()
end, { desc = "Toggle TermLet Script Menu" })
```

The menu displays all configured scripts with optional descriptions:

```
╭─ TermLet Scripts ─────────────────────╮
│                                       │
│  > build         Build project        │
│    test          Run tests            │
│    deploy        Deploy to staging    │
│    lint          Run linter           │
│                                       │
│ [Enter] Run  [/] Search  [?] Help [q] │
╰───────────────────────────────────────╯
```

**Menu Keybindings:**

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `gg` | Go to first script |
| `G` | Go to last script |
| `Enter` | Execute selected script |
| `/` | Enter search/filter mode |
| `Esc` | Cancel search or close menu |
| `q` | Close menu |
| `?` | Toggle help |

**Adding descriptions to scripts:**

```lua
scripts = {
  {
    name = "build",
    filename = "build.sh",
    description = "Build the project"  -- Shows in menu
  },
}
```

Additional utility methods:

* `require("termlet").open_menu()` – open the interactive script menu
* `require("termlet").close_menu()` – close the script menu
* `require("termlet").toggle_menu()` – toggle the script menu open/closed
* `require("termlet").is_menu_open()` – check if menu is currently open
* `require("termlet").close_all_terminals()` – close all terminals
* `require("termlet").close_terminal()` – close the current or last terminal
* `require("termlet").show_last_output()` – show output from the most recent script run
* `require("termlet").list_outputs()` – list all saved terminal outputs
* `require("termlet").clear_outputs()` – clear all saved terminal outputs

---

## 💾 Output Persistence

TermLet can preserve terminal output after a script completes, allowing you to review build warnings, test results, or error messages even after closing the terminal window.

### Configuration

```lua
require("termlet").setup({
  terminal = {
    output_persistence = "buffer",  -- "none" | "buffer"
    max_saved_buffers = 5,          -- Maximum outputs to keep
  },
  -- ... other config
})
```

### Persistence Modes

- **`"none"`** (default): Terminal buffers are wiped when the window closes. Output is lost.
- **`"buffer"`**: Terminal buffers are hidden when the window closes. Output is preserved and can be viewed later.

### Usage

After running scripts, access saved outputs:

```lua
-- View the most recent output
vim.keymap.set("n", "<leader>tl", function()
  require("termlet").show_last_output()
end, { desc = "Show last terminal output" })

-- List all saved outputs
vim.keymap.set("n", "<leader>to", function()
  require("termlet").list_outputs()
end, { desc = "List saved outputs" })

-- Clear all saved outputs
vim.keymap.set("n", "<leader>tx", function()
  require("termlet").clear_outputs()
end, { desc = "Clear saved outputs" })
```

### Use Cases

1. **Build output review**: After closing the terminal, review specific warnings or errors
2. **Test results**: Check which tests failed after the terminal closed
3. **Debugging**: Compare output from multiple script runs
4. **Documentation**: Copy output for bug reports or documentation

### Memory Management

When `output_persistence = "buffer"`, TermLet automatically manages memory:
- Old outputs are removed when `max_saved_buffers` limit is reached (FIFO)
- Invalid buffers are cleaned up automatically
- Use `clear_outputs()` to manually free memory

---

## ⌨️ Visual Keybinding Configuration

TermLet provides an interactive interface for configuring keybindings for your scripts without editing config files.

### Opening the Keybindings Manager

```lua
vim.keymap.set("n", "<leader>tk", function()
  require("termlet").open_keybindings()
end, { desc = "Open TermLet Keybindings" })

-- Or use toggle to open/close with the same key
vim.keymap.set("n", "<leader>tk", function()
  require("termlet").toggle_keybindings()
end, { desc = "Toggle TermLet Keybindings" })
```

The keybindings manager displays all configured scripts with their assigned keybindings:

```
╭─ TermLet Keybindings ─────────────────────╮
│                                            │
│    Script          Keybinding    Action   │
│    ──────────────────────────────────────  │
│  > build           <leader>b     [Change]  │
│    test            <leader>t     [Change]  │
│    deploy          (not set)     [Set]     │
│    lint            <leader>l     [Change]  │
│                                            │
│ [c] Capture  [i] Type  [d] Delete  [q]    │
╰────────────────────────────────────────────╯
```

### Keybindings Manager Controls

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `gg` | Go to first script |
| `G` | Go to last script |
| `c` / `Enter` | Capture keybinding (real-time key capture) |
| `i` | Type keybinding notation (e.g., `<leader>b`) |
| `d` | Delete keybinding |
| `Esc` | Cancel / Close |
| `q` | Close manager |
| `?` | Toggle help |

### Setting Keybindings

**Method 1: Real-time Capture (c / Enter)**

Press `c` or `Enter` to enter capture mode, then press the key combination you want to use. Keys are captured in real-time and displayed immediately. Press `Enter` to confirm or `Esc` to cancel.

**Method 2: Type Notation (i)**

Press `i` to enter input mode, then type the keybinding notation directly (e.g., `<leader>b`, `<C-k>`, `<A-j>`). Press `Enter` to confirm or `Esc` to cancel.

### Features

- **Persistence**: Keybindings are automatically saved to `~/.local/share/nvim/termlet-keybindings.json` and loaded on startup
- **Conflict Detection**: Warns when a keybinding is already assigned to another script
- **Auto-apply**: Keybindings are applied immediately and persisted across Neovim sessions
- **Real-time Capture**: Captures multi-key sequences and special keys like `<leader>`, `<C-x>`, etc.

### Programmatic API

You can also manage keybindings programmatically:

```lua
-- Set a keybinding
require("termlet").set_keybinding("build", "<leader>b")

-- Clear a keybinding
require("termlet").clear_keybinding("build")

-- Get all keybindings
local bindings = require("termlet").get_keybindings()
print(bindings["build"]) -- "<leader>b"

-- Open/close/toggle the UI
require("termlet").open_keybindings()
require("termlet").close_keybindings()
require("termlet").toggle_keybindings()
```

---

## 🎯 Smart Output Filtering and Highlighting

TermLet can filter terminal output by patterns and apply custom syntax highlighting to warnings, errors, and important messages. This helps you quickly spot issues in verbose output from long-running scripts.

### Use Cases

- **Long build processes** - Filter to show only errors and warnings
- **Test suites** - Highlight failures and hide verbose debug output
- **Log analysis** - Focus on specific log levels (ERROR, WARNING, INFO)
- **CI/CD pipelines** - Quickly identify deployment issues

### Configuration

Configure filters globally or per-script:

```lua
require("termlet").setup({
  scripts = {
    {
      name = "build",
      filename = "build.sh",
      filters = {
        enabled = true,
        show_only = { "error", "warning" }, -- Only show matching lines
        hide = { "debug", "verbose" },      -- Hide matching lines
        highlight = {
          { pattern = "ERROR", color = "#ff0000" },
          { pattern = "WARNING", color = "#ffaa00" },
          { pattern = "SUCCESS", color = "#00ff00" },
        }
      }
    }
  }
})
```

### Interactive Filter Mode

Press `<C-f>` in a terminal window to enter interactive filter mode:

```lua
vim.keymap.set("t", "<C-f>", function()
  require("termlet").open_filter_ui()
end, { desc = "Open filter UI" })
```

The filter UI provides quick presets:
- **All** - Show all output (hide debug/verbose)
- **Errors** - Show only errors
- **Warnings** - Show only warnings
- **Info** - Show only info/success messages

### API Functions

```lua
-- Apply a filter preset
require("termlet").apply_filter_preset("errors")

-- Toggle filters on/off
require("termlet").toggle_filters()

-- Clear filters
require("termlet").clear_filters()

-- Reapply current filters
require("termlet").reapply_filters()

-- Open interactive filter UI
require("termlet").open_filter_ui()
```

### Example Keybindings

```lua
-- Open filter UI in terminal mode
vim.keymap.set("t", "<C-f>", function()
  require("termlet").open_filter_ui()
end, { desc = "Open filter UI" })

-- Toggle filters in terminal mode
vim.keymap.set("t", "<C-g>", function()
  require("termlet").toggle_filters()
end, { desc = "Toggle filters" })

-- Quick presets in normal mode (when in terminal buffer)
vim.keymap.set("n", "<leader>fe", function()
  require("termlet").apply_filter_preset("errors")
end, { desc = "Filter: Errors only" })

vim.keymap.set("n", "<leader>fw", function()
  require("termlet").apply_filter_preset("warnings")
end, { desc = "Filter: Warnings only" })

vim.keymap.set("n", "<leader>fa", function()
  require("termlet").apply_filter_preset("all")
end, { desc = "Filter: All (hide debug)" })
```

### Filter Patterns

Filters support case-insensitive substring matching:

```lua
filters = {
  enabled = true,
  -- Show only lines containing these patterns (case-insensitive)
  show_only = { "error", "fail", "exception" },

  -- Hide lines containing these patterns (case-insensitive)
  hide = { "debug", "trace", "verbose" },

  -- Highlight patterns with custom colors
  highlight = {
    { pattern = "error", color = "#ff0000" },      -- Red
    { pattern = "warning", color = "#ffaa00" },    -- Orange
    { pattern = "success", color = "#00ff00" },    -- Green
    { pattern = "info", color = "#00aaff" },       -- Blue
  }
}
```

**Note:** When both `show_only` and `hide` are specified, a line must match `show_only` AND not match `hide` to be shown.

**Non-destructive:** Filtering is fully reversible. Original output is cached and restored when you toggle filters off or clear them. Stack trace metadata remains valid across filter changes.

### Per-Script Filters

Each script can have its own filter configuration:

```lua
scripts = {
  {
    name = "build",
    filename = "build.sh",
    filters = {
      enabled = true,
      show_only = { "error", "warning" },
      highlight = {
        { pattern = "error", color = "#ff0000" },
        { pattern = "warning", color = "#ffaa00" },
      }
    }
  },
  {
    name = "test",
    filename = "test.sh",
    filters = {
      enabled = true,
      hide = { "debug", "[PASS]" },
      highlight = {
        { pattern = "[FAIL]", color = "#ff0000" },
        { pattern = "[SKIP]", color = "#ffaa00" },
      }
    }
  }
}
```

---

## 🔍 Stack Trace Detection

TermLet automatically detects file references in terminal error output. When a script produces a stack trace or compiler error, you can jump directly to the source location.

### Supported Languages

TermLet includes built-in parsers for:
- **Python** - Standard tracebacks, pytest format
- **C#** - .NET stack traces, MSBuild errors
- **JavaScript/TypeScript** - Node.js, browser, webpack formats
- **Java** - Standard stack traces, compiler errors
- **Go** - Panic and error traces
- **Rust** - Compiler errors and backtraces
- **Ruby** - Exception traces
- **Lua** - Error messages
- **C/C++** - Compiler errors
- **PHP, Perl, Elixir, Erlang, Swift, Kotlin, Haskell**

### Quick Start

Enable stack trace parsing for specific languages:

```lua
require("termlet").setup({
  stacktrace = {
    enabled = true,
    languages = { 'python', 'csharp' }, -- empty = all languages
  }
})
```

### Usage

Add a keybinding to jump to the nearest stack trace reference:

```lua
vim.keymap.set("n", "<leader>tg", function()
  require("termlet").goto_stacktrace()
end, { desc = "Go to stack trace file" })
```

You can also query stack trace info programmatically:

```lua
local info = require("termlet").get_stacktrace_at_cursor()
if info then
  print("File: " .. info.path)
  print("Line: " .. info.line)
end
```

### Extensible Parser Plugin System

TermLet includes an extensible parser plugin architecture for parsing stack traces from multiple languages.

#### Using the Parser API

Parse stack trace lines:

```lua
local stacktrace = require('termlet.stacktrace')

-- Parse a single line
local result = stacktrace.parse_line('  File "/path/file.py", line 42')
-- Returns: { parser_name = "python", file_path = "/path/file.py", line_number = 42 }

-- Parse multiple lines
local results = stacktrace.parse_lines(terminal_buffer_lines)
```

#### Creating Custom Parsers

Create parsers for any language:

```lua
local my_parser = {
  name = 'go',
  description = 'Go panic and error traces',

  patterns = {
    {
      pattern = '([^:]+%.go):(%d+)',
      path_group = 1,
      line_group = 2,
    }
  },

  resolve_path = function(path, cwd)
    -- Custom path resolution logic
    return path
  end,
}

require('termlet').setup({
  stacktrace = {
    enabled = true,
    custom_parsers = { my_parser },
  }
})
```

#### Custom Pattern Registration

Register patterns for additional languages or custom error formats:

```lua
require("termlet").stacktrace.register_pattern("myformat", {
  pattern = "ERROR at ([^:]+):(%d+)",
  file_pattern = "ERROR at ([^:]+):%d+",
  line_pattern = ":(%d+)$",
  priority = 10,
})
```

#### Parser Development

See the [Parser Development Guide](docs/PARSER_DEVELOPMENT.md) for:
- Complete parser structure documentation
- Pattern syntax reference
- Built-in parser examples
- Testing guidelines
- Best practices

---

## 🧪 Testing

TermLet includes a comprehensive test suite using [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

### Running Tests

#### Using Make (Recommended)

```bash
# Run all tests
make test

# Run a specific test file
make test-file FILE=tests/termlet_spec.lua

# Clean test artifacts
make clean
```

#### Using Neovim Directly

```bash
# Run all tests
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"

# Run a specific test file
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/termlet_spec.lua"
```

### Test Coverage

The test suite covers:
- ✅ Path discovery functions (`find_script_by_name`, `find_script`)
- ✅ Floating terminal creation and configuration
- ✅ Terminal management (close, close_all)
- ✅ Configuration validation and setup
- ✅ Function name sanitization
- ✅ Stack trace detection and parsing (Python, C#, JavaScript, Java, etc.)
- ✅ Interactive script menu
- ✅ Keybinding management
- ✅ Visual highlighting of file paths
- ✅ Navigation features
- ✅ Output persistence
- ✅ Focus management

### Test Structure

```
tests/
├── minimal_init.lua          # Minimal Neovim config for tests
├── termlet_spec.lua          # Main module tests
├── stacktrace_spec.lua       # Stack trace detection tests
├── menu_spec.lua             # Interactive menu tests
├── keybindings_spec.lua      # Keybinding management tests
├── highlight_spec.lua        # Visual highlighting tests
└── filter_spec.lua           # Output filtering tests
```

### Requirements

- [Neovim](https://neovim.io/) (stable or nightly)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (installed automatically in CI)

### Continuous Integration

Tests run automatically on GitHub Actions for:
- Every push to `main`, `master`, or `develop` branches
- All pull requests
- Both Neovim stable and nightly versions

---

## ✅ Example using [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
require("termlet").setup({
  root_dir = "~/code/project",
  debug = false,
  terminal = {
    height_ratio = 0.2,
    border = "single",
    position = "top"
  },
  menu = {
    width_ratio = 0.5,
    height_ratio = 0.4,
    border = "rounded"
  },
  scripts = {
    {
      name = "build",
      filename = "build.sh",
      description = "Build the project"
    },
    {
      name = "test_server",
      filename = "server_test.py",
      cmd = "python3 server_test.py",
      description = "Run server tests"
    }
  }
})

-- Open the script menu with <leader>ts
vim.keymap.set("n", "<leader>ts", function()
  require("termlet").open_menu()
end, { desc = "Open TermLet Script Menu" })
```


## ✅ Example ```termlet.lua``` using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  {
    'devArchOverclocked/termlet',
    event = 'VeryLazy',
    opts = {
      root_dir = '~/path/to/my/projects/', -- Default root directory for script search
      terminal = {
        height_ratio = 0.50,
        width_ratio = 1,
        border = 'rounded',                -- "none", "single", "double", "rounded", etc.
        position = 'bottom',               -- "bottom", "center", "top"
      },
      scripts = {                          -- List of scripts with `name` and either `filename` or `dir_name`/`relative_path`

        { name = 'build_project', filename = 'build.sh' },
        { name = 'start_server', filename = 'server_test.py', cmd = 'python3 server_test.py' },
      },
      debug = false,                       -- Enable verbose debug logging
    },
    keys = {
      {
        '<leader>tb',
        function()
          require('termlet').run_build_project()
        end,
        desc = 'TermLet: Build project',
      },
      {
        '<leader>ts',
        function()
          require('termlet').run_start_server()
        end,
        desc = 'TermLet: Start server',
      },
      {
        '<leader>tl',
        function()
          require('termlet').list_scripts()
        end,
        desc = 'TermLet: List scripts',
      },
      {
        '<leader>tc',
        function()
          require('termlet').close_terminal()
        end,
        desc = 'TermLet: Close terminal',
      },
    },
  },
}
```
