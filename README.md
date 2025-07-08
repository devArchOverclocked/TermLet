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
use({
  "devArchOverclocked/termlet.nvim",
  config = function()
    local termlet = require("termlet")
    vim.keymap.set("n", "<leader>b", function()
      termlet.run_script("build", "engine")
    end, { desc = "Run build script" })

    vim.keymap.set("n", "<leader>bt", function()
      termlet.run_script("test", "scripts/test")
    end, { desc = "Run test script" })

    vim.keymap.set("n", "<leader>bc", termlet.close_floating_window, { desc = "Close build window" })
  end,
})
