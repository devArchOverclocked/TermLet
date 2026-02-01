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
    enabled = true,     -- Enable stack trace detection
    languages = {},     -- Filter to specific languages (empty = all)
    buffer_size = 50,   -- Lines kept in buffer for multi-line detection
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

## 🔍 Stack Trace Detection

TermLet automatically detects file references in terminal error output. When a script produces a stack trace or compiler error, you can jump directly to the source location.

### Supported Languages

Python, JavaScript/TypeScript, Java, C#, Go, Rust, Ruby, Lua, C/C++, PHP, Perl, Elixir, Erlang, Swift, Kotlin, Haskell.

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

### Custom Patterns

Register patterns for additional languages or custom error formats:

```lua
require("termlet").stacktrace.register_pattern("myformat", {
  pattern = "ERROR at ([^:]+):(%d+)",
  file_pattern = "ERROR at ([^:]+):%d+",
  line_pattern = ":(%d+)$",
  priority = 10,
})
```

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
