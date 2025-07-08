local M = {}
local config = {
  scripts = {},
}

function M.open_floating_terminal()
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

function M.find_script(dir_name, relative_path)
  local path = vim.fn.expand("%:p:h")
  print("Starting search from: " .. path)

  while path ~= "/" do
    local folder = vim.fn.fnamemodify(path, ":t")
    print("Checking: " .. path .. " (dir: " .. folder .. ")")

    if folder == dir_name then
      local script_path = path .. "/" .. relative_path
      print("Found target folder. Looking for script at: " .. script_path)
      if vim.fn.filereadable(script_path) == 1 then
        return script_path
      else
        print("Script not found at: " .. script_path)
      end
    end

    path = vim.fn.fnamemodify(path, ":h")
  end

  print("Directory named '" .. dir_name .. "' not found.")
  return nil
end
-- Dynamically create one function per script
function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})

  for _, script in ipairs(config.scripts) do
    local function_name = "run_" .. script.name:gsub("%s+", "_"):lower()

    M[function_name] = function()
      local full_path = M.find_script(script.dir_name, script.relative_path)
      if not full_path then
        vim.notify("Script '" .. script.name .. "' not found", vim.log.levels.ERROR)
        return
      end

      local cwd = vim.fn.fnamemodify(full_path, ":h")

      -- Create terminal buffer and floating window
      local buf = vim.api.nvim_create_buf(false, true)
      local height = math.floor(vim.o.lines / 6)
      local width = vim.o.columns
      local row = vim.o.lines - height - 2

      local win = vim.api.nvim_open_win(buf, true, {
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

      -- Run the terminal in THAT buffer
      local cmd = "./" .. vim.fn.fnamemodify(full_path, ":t")
      vim.fn.termopen(cmd, {
        cwd = cwd,
        on_exit = function(_, code)
          local msg = script.name .. " exited with code " .. code
          local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
          vim.schedule(function()
            vim.notify(msg, level)
          end)
        end,
      })

      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
    end
  end
end

function M.close_build_window()
  vim.cmd("close") -- or implement proper win handle close
end

return M

