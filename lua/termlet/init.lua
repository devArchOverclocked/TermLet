local M = {}
local config = {
  scripts = {},
}

local function open_floating_terminal()
  local height = math.floor(vim.o.lines / 6)
  local width = vim.o.columns
  local row = vim.o.lines - height - 2

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = 0,
    anchor = "NW",
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "terminal")

  return buf
end

local function find_script(dir_name, relative_path)
  local path = vim.fn.expand("%:p:h")
  while path ~= "/" do
    if vim.fn.fnamemodify(path, ":t") == dir_name then
      local script_path = path .. "/" .. relative_path
      if vim.fn.filereadable(script_path) == 1 then
        return script_path
      end
    end
    path = vim.fn.fnamemodify(path, ":h")
  end
  return nil
end

-- Dynamically create one function per script
function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})

  for _, script in ipairs(config.scripts) do
    local function_name = "run_" .. script.name:gsub("%s+", "_"):lower()

    M[function_name] = function()
      local full_path = find_script(script.dir_name, script.relative_path)
      if not full_path then
        vim.notify("Script '" .. script.name .. "' not found", vim.log.levels.ERROR)
        return
      end

      local cwd = vim.fn.fnamemodify(full_path, ":h")
      local buf = open_floating_terminal()
      vim.fn.termopen("cd " .. cwd .. " && ./build", {
        on_exit = function(_, code)
          local msg = script.name .. " exited with code " .. code
          local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
          vim.notify(msg, level)
        end
      }, { buffer = buf })

      vim.cmd("wincmd p") -- Restore focus
    end
  end
end

-- Optional: window closer if stored somewhere
function M.close_build_window()
  vim.cmd("close") -- or use nvim_win_close if you store win ID
end

return M

