# 🧪 TermLet.nvim

**Run, manage, and interact with custom scripts in beautiful floating terminals — directly from Neovim.**

---

## ✨ Features

* 📦 **Run user-defined scripts** from structured configuration
* 🧭 **Auto-discover script paths** from flexible search logic
* 🪟 **Floating terminal windows** with customizable size, borders, and position
* 🎨 **Interactive script menu** - Mason-like popup for browsing and executing scripts
* 🔀 **Dynamic function generation** for each script (e.g. `:lua require('termlet').run_my_script()`)
* 😹 **Terminal cleanup** and safe resource handling
* 🔍 **Stack trace detection** — automatically detect file references in error output and jump to source
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
    border = "rounded", -- "none", "single", "double", "rounded", etc.
    position = "bottom" -- "bottom", "center", "top"
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
