-- Minimal init file for running tests
-- This sets up the Lua path so that require("termlet") works

-- Add the plugin to the runtimepath
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_root)

-- Add plenary to runtimepath if available
local plenary_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:prepend(plenary_path)
end

-- Also check lazy.nvim path
local lazy_plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(lazy_plenary_path) == 1 then
  vim.opt.runtimepath:prepend(lazy_plenary_path)
end

-- Disable swap files
vim.opt.swapfile = false

-- Set up minimal settings
vim.o.hidden = true
vim.o.termguicolors = true
