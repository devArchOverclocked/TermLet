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
  local root = nil

  -- Walk up until we find a folder named 'dir_name' (e.g. 'dnv')
  while path ~= "/" and path ~= "" do
    local basename = vim.fn.fnamemodify(path, ":t")
    if basename == dir_name then
      root = path
      break
    end
    path = vim.fn.fnamemodify(path, ":h")
  end

  if not root then
    return nil -- Could not find the target directory upwards
  end

  local script_path = root .. "/" .. relative_path
  if vim.fn.filereadable(script_path) == 1 then
    return script_path
  else
    return nil -- Script file does not exist inside found folder
  end
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
      local buf = M.open_floating_terminal()

      -- Use termopen with cmd as a list and cwd for cleaner environment
      vim.fn.termopen({ "./" .. vim.fn.fnamemodify(full_path, ":t") }, {
        on_exit = function(_, code)
          local msg = script.name .. " exited with code " .. code
          local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
          vim.schedule(function()
            vim.notify(msg, level)
          end)
        end,
        cwd = cwd,
      }, { buffer = buf })

      vim.cmd("wincmd p") -- Restore focus
    end
  end
end

function M.close_build_window()
  vim.cmd("close") -- or implement proper win handle close
end

return M

