# termlet.nvim

> Run any project-local script (build, test, deploy, etc.) inside a small floating terminal — without leaving your current Neovim buffer.

---

## Features

-  Run any script inside a **floating terminal** at the bottom of your screen
-  Automatically discovers script paths from anywhere in your project
-  Maintains **focus in your main buffer** (no context-switching!)
-  Lightweight, minimal, and no dependencies
-  Custom script support 

---

## Installation

Using [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use ({'devArchOverclocked/termlet.nvim', config = false })
```

```after/plugins/termlet
local termlet = require("termlet")

termlet.setup({
  scripts = {
    { name = "Build", dir_name = "DIR", relative_path = "Path/to/build" },
    { name = "Test Script", dir_name = "DIR2", relative_path = "run_test.sh" },
  }
})

vim.keymap.set("n", "<leader>b", function()
  termlet.run_build()
end, { desc = "Run Build Script" })

vim.keymap.set("n", "<leader>t", function()
  termlet.run_test_script()
end, { desc = "Run Test Script" })

vim.keymap.set("n", "<leader>bc", function()
  termlet.close_build_window()
end, { desc = "Close Build Window" })
```

## TODO
Find a better way to provide the relative path
