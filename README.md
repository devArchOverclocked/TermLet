# 🧪 TermLet.nvim

**Run, manage, and interact with custom scripts in beautiful floating terminals — directly from Neovim.**

---

## ✨ Features

* 📦 **Run user-defined scripts** from structured configuration
* 🧭 **Auto-discover script paths** from flexible search logic
* 🪟 **Floating terminal windows** with customizable size, borders, and position
* 🔀 **Dynamic function generation** for each script (e.g. `:lua require('termlet').run_my_script()`)
* 😹 **Terminal cleanup** and safe resource handling
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

Using [lazy.nvim](https://github.com/LazyVim/LazyVim):
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
  debug = false,        -- Enable verbose debug logging
}
```

Each script object must include:

### With `filename` (Preferred):

```lua
{
  name = "my_script",
  filename = "run.sh",      -- Required
  root_dir = "~/project",   -- Optional
  search_dirs = {"scripts"} -- Optional
}
```

### Or with `dir_name` + `relative_path` (Legacy):

```lua
{
  name = "legacy_task",
  dir_name = "tools",
  relative_path = "run_legacy.sh"
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

Additional utility methods:

* `require("termlet").close_all_terminals()` – close all terminals
* `require("termlet").close_terminal()` – close the current or last terminal

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
  scripts = {
    {
      name = "build",
      filename = "build.sh"
    },
    {
      name = "test_server",
      filename = "server_test.py",
      cmd = "python3 server_test.py"
    }
  }
})
```


## ✅ Example ```termlet.lua``` using [lazy.nvim](https://github.com/LazyVim/LazyVim):

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
