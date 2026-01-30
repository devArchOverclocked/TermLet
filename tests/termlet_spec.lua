-- Tests for TermLet main module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet", function()
  local termlet

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet"] = nil
    package.loaded["termlet.menu"] = nil
    termlet = require("termlet")
  end)

  after_each(function()
    -- Clean up
    if termlet.close_menu then
      termlet.close_menu()
    end
    termlet.close_all_terminals()
  end)

  describe("setup", function()
    it("should initialize with default config", function()
      termlet.setup({
        scripts = {},
      })
      -- Should not error
      assert.is_not_nil(termlet)
    end)

    it("should create run functions for scripts", function()
      termlet.setup({
        scripts = {
          { name = "test_script", filename = "test.sh" },
        },
      })

      assert.is_function(termlet.run_test_script)
    end)

    it("should sanitize function names", function()
      termlet.setup({
        scripts = {
          { name = "my-test.script", filename = "test.sh" },
          { name = "another test", filename = "test2.sh" },
        },
      })

      assert.is_function(termlet.run_my_test_script)
      assert.is_function(termlet.run_another_test)
    end)
  end)

  describe("open_menu", function()
    it("should return false when no scripts configured", function()
      termlet.setup({
        scripts = {},
      })

      local result = termlet.open_menu()
      assert.is_false(result)
    end)

    it("should open menu when scripts are configured", function()
      termlet.setup({
        scripts = {
          { name = "build", description = "Build project", filename = "build.sh" },
          { name = "test", description = "Run tests", filename = "test.sh" },
        },
      })

      local result = termlet.open_menu()
      assert.is_true(result)
      assert.is_true(termlet.is_menu_open())
    end)
  end)

  describe("close_menu", function()
    it("should close an open menu", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      termlet.open_menu()
      assert.is_true(termlet.is_menu_open())

      termlet.close_menu()
      assert.is_false(termlet.is_menu_open())
    end)

    it("should not error when no menu is open", function()
      termlet.setup({ scripts = {} })
      -- Should not error
      termlet.close_menu()
    end)
  end)

  describe("toggle_menu", function()
    it("should open menu when closed", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      assert.is_false(termlet.is_menu_open())
      termlet.toggle_menu()
      assert.is_true(termlet.is_menu_open())
    end)

    it("should close menu when open", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      termlet.open_menu()
      assert.is_true(termlet.is_menu_open())

      termlet.toggle_menu()
      assert.is_false(termlet.is_menu_open())
    end)
  end)

  describe("is_menu_open", function()
    it("should return false initially", function()
      termlet.setup({ scripts = {} })
      assert.is_false(termlet.is_menu_open())
    end)
  end)

  describe("list_scripts", function()
    it("should not error with empty scripts", function()
      termlet.setup({ scripts = {} })
      -- Should not error
      termlet.list_scripts()
    end)

    it("should not error with configured scripts", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })
      -- Should not error
      termlet.list_scripts()
    end)
  end)

  describe("menu configuration", function()
    it("should accept custom menu config", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
        menu = {
          width_ratio = 0.8,
          height_ratio = 0.6,
          border = "double",
          title = " Custom Menu ",
        },
      })

      local result = termlet.open_menu()
      assert.is_true(result)
    end)
  end)

  describe("format_terminal_title", function()
    it("should format title with default template", function()
      local cfg = {
        title_format = " {icon} {name} ",
        title_icon = "",
        show_status = false,
        status_icons = { running = "●", success = "✓", error = "✗" },
      }
      local result = termlet._format_terminal_title(cfg, "build.sh", nil)
      assert.is_truthy(result:find("build.sh", 1, true))
      assert.is_truthy(result:find("", 1, true))
    end)

    it("should replace {name} placeholder", function()
      local cfg = {
        title_format = "[{name}]",
        title_icon = "",
        show_status = false,
        status_icons = {},
      }
      local result = termlet._format_terminal_title(cfg, "my_script", nil)
      assert.is_truthy(result:find("my_script", 1, true))
    end)

    it("should replace {icon} placeholder", function()
      local cfg = {
        title_format = "{icon} test",
        title_icon = "",
        show_status = false,
        status_icons = {},
      }
      local result = termlet._format_terminal_title(cfg, "test", nil)
      assert.is_truthy(result:find("", 1, true))
    end)

    it("should show running status icon when show_status is true", function()
      local cfg = {
        title_format = " {name} {status} ",
        title_icon = "",
        show_status = true,
        status_icons = { running = "●", success = "✓", error = "✗" },
      }
      local result = termlet._format_terminal_title(cfg, "build", "running")
      assert.is_truthy(result:find("●", 1, true))
    end)

    it("should show success status icon", function()
      local cfg = {
        title_format = " {name} {status} ",
        title_icon = "",
        show_status = true,
        status_icons = { running = "●", success = "✓", error = "✗" },
      }
      local result = termlet._format_terminal_title(cfg, "build", "success")
      assert.is_truthy(result:find("✓", 1, true))
    end)

    it("should show error status icon", function()
      local cfg = {
        title_format = " {name} {status} ",
        title_icon = "",
        show_status = true,
        status_icons = { running = "●", success = "✓", error = "✗" },
      }
      local result = termlet._format_terminal_title(cfg, "build", "error")
      assert.is_truthy(result:find("✗", 1, true))
    end)

    it("should not show status icon when show_status is false", function()
      local cfg = {
        title_format = " {name} {status} ",
        title_icon = "",
        show_status = false,
        status_icons = { running = "●", success = "✓", error = "✗" },
      }
      local result = termlet._format_terminal_title(cfg, "build", "running")
      assert.is_falsy(result:find("●", 1, true))
    end)

    it("should handle nil name by defaulting to Terminal", function()
      local cfg = {
        title_format = " {name} ",
        title_icon = "",
        show_status = false,
        status_icons = {},
      }
      local result = termlet._format_terminal_title(cfg, nil, nil)
      assert.is_truthy(result:find("Terminal", 1, true))
    end)

    it("should handle custom title format string", function()
      local cfg = {
        title_format = ">> {icon} | {name} | {status} <<",
        title_icon = "X",
        show_status = true,
        status_icons = { running = "R" },
      }
      local result = termlet._format_terminal_title(cfg, "test", "running")
      assert.is_truthy(result:find("X", 1, true))
      assert.is_truthy(result:find("test", 1, true))
      assert.is_truthy(result:find("R", 1, true))
    end)

    it("should handle missing status_icons gracefully", function()
      local cfg = {
        title_format = " {name} {status} ",
        title_icon = "",
        show_status = true,
        status_icons = {},
      }
      -- Should not error even with no icon defined for "running"
      local result = termlet._format_terminal_title(cfg, "build", "running")
      assert.is_truthy(result:find("build", 1, true))
    end)

    it("should handle empty title_format", function()
      local cfg = {
        title_format = "",
        title_icon = "",
        show_status = false,
        status_icons = {},
      }
      local result = termlet._format_terminal_title(cfg, "build", nil)
      assert.is_string(result)
    end)

    it("should handle format without any placeholders", function()
      local cfg = {
        title_format = " Static Title ",
        title_icon = "",
        show_status = false,
        status_icons = {},
      }
      local result = termlet._format_terminal_title(cfg, "build", nil)
      assert.is_truthy(result:find("Static Title", 1, true))
    end)

    it("should use custom status icons", function()
      local cfg = {
        title_format = "{status}",
        title_icon = "",
        show_status = true,
        status_icons = { running = "RUNNING", success = "OK", error = "FAIL" },
      }
      assert.is_truthy(
        termlet._format_terminal_title(cfg, "x", "running"):find("RUNNING", 1, true)
      )
      assert.is_truthy(
        termlet._format_terminal_title(cfg, "x", "success"):find("OK", 1, true)
      )
      assert.is_truthy(
        termlet._format_terminal_title(cfg, "x", "error"):find("FAIL", 1, true)
      )
    end)

    it("should handle nil status when show_status is true", function()
      local cfg = {
        title_format = " {name} {status} ",
        title_icon = "",
        show_status = true,
        status_icons = { running = "●" },
      }
      -- nil status should produce empty status text
      local result = termlet._format_terminal_title(cfg, "build", nil)
      assert.is_falsy(result:find("●", 1, true))
    end)
  end)

  describe("create_floating_terminal styling", function()
    it("should create terminal with default styling", function()
      termlet.setup({ scripts = {} })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(buf)
      assert.is_not_nil(win)
      assert.is_true(vim.api.nvim_win_is_valid(win))

      local win_config = vim.api.nvim_win_get_config(win)
      assert.are.equal("center", win_config.title_pos)
    end)

    it("should apply custom title_pos left", function()
      termlet.setup({
        scripts = {},
        terminal = { title_pos = "left" },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      assert.are.equal("left", win_config.title_pos)
    end)

    it("should apply custom title_pos right", function()
      termlet.setup({
        scripts = {},
        terminal = { title_pos = "right" },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      assert.are.equal("right", win_config.title_pos)
    end)

    it("should apply winhighlight with default highlight groups", function()
      termlet.setup({ scripts = {} })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = win })
      assert.is_truthy(winhighlight:find("Normal:NormalFloat", 1, true))
      assert.is_truthy(winhighlight:find("FloatBorder:FloatBorder", 1, true))
      assert.is_truthy(winhighlight:find("FloatTitle:Title", 1, true))
    end)

    it("should apply custom highlight groups", function()
      termlet.setup({
        scripts = {},
        terminal = {
          highlights = {
            border = "TelescopeBorder",
            title = "TelescopeTitle",
            background = "TelescopeNormal",
          },
        },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = win })
      assert.is_truthy(winhighlight:find("Normal:TelescopeNormal", 1, true))
      assert.is_truthy(winhighlight:find("FloatBorder:TelescopeBorder", 1, true))
      assert.is_truthy(winhighlight:find("FloatTitle:TelescopeTitle", 1, true))
    end)

    it("should accept custom border characters as a table", function()
      termlet.setup({
        scripts = {},
        terminal = {
          border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
        },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      assert.is_table(win_config.border)
    end)

    it("should accept border preset strings", function()
      for _, preset in ipairs({ "rounded", "single", "double" }) do
        termlet.setup({
          scripts = {},
          terminal = { border = preset },
        })
        local buf, win = termlet.create_floating_terminal({})
        assert.is_not_nil(win)
      end
    end)

    it("should format title using configured template", function()
      termlet.setup({
        scripts = {},
        terminal = {
          title_format = "[ {name} ]",
          title_icon = "",
        },
      })
      local buf, win = termlet.create_floating_terminal({ title = "my_build" })
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      -- The title from nvim_win_get_config is a list of {text, hl} pairs
      local title_text = ""
      if type(win_config.title) == "string" then
        title_text = win_config.title
      elseif type(win_config.title) == "table" then
        for _, part in ipairs(win_config.title) do
          if type(part) == "table" then
            title_text = title_text .. (part[1] or "")
          elseif type(part) == "string" then
            title_text = title_text .. part
          end
        end
      end
      assert.is_truthy(title_text:find("my_build", 1, true))
    end)

    it("should show running status in title when show_status is true", function()
      termlet.setup({
        scripts = {},
        terminal = {
          title_format = " {name} {status} ",
          show_status = true,
          status_icons = { running = "●", success = "✓", error = "✗" },
        },
      })
      local buf, win = termlet.create_floating_terminal({ title = "build" })
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      local title_text = ""
      if type(win_config.title) == "string" then
        title_text = win_config.title
      elseif type(win_config.title) == "table" then
        for _, part in ipairs(win_config.title) do
          if type(part) == "table" then
            title_text = title_text .. (part[1] or "")
          elseif type(part) == "string" then
            title_text = title_text .. part
          end
        end
      end
      assert.is_truthy(title_text:find("●", 1, true))
    end)

    it("should use none border style", function()
      termlet.setup({
        scripts = {},
        terminal = { border = "none" },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)
    end)

    it("should accept partial highlight overrides", function()
      termlet.setup({
        scripts = {},
        terminal = {
          highlights = {
            border = "WarningMsg",
          },
        },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = win })
      assert.is_truthy(winhighlight:find("FloatBorder:WarningMsg", 1, true))
      -- Should still have defaults for non-overridden groups
      assert.is_truthy(winhighlight:find("Normal:NormalFloat", 1, true))
      assert.is_truthy(winhighlight:find("FloatTitle:Title", 1, true))
    end)
  end)

  describe("terminal styling config", function()
    it("should accept full styling configuration in setup", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
        terminal = {
          position = "bottom",
          height_ratio = 0.2,
          border = "rounded",
          highlights = {
            border = "TelescopeBorder",
            title = "TelescopeTitle",
          },
          title_format = " {icon} {name} {status} ",
          title_icon = "",
          title_pos = "center",
          show_status = true,
          status_icons = {
            running = "●",
            success = "✓",
            error = "✗",
          },
        },
      })
      -- Should not error
      assert.is_not_nil(termlet)
      assert.is_function(termlet.run_build)
    end)

    it("should accept custom border table in setup", function()
      termlet.setup({
        scripts = {},
        terminal = {
          border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
        },
      })
      -- Should not error
      assert.is_not_nil(termlet)
    end)
  end)

  describe("replace_placeholder multiple occurrences", function()
    it("should replace all occurrences of the same placeholder", function()
      local cfg = {
        title_format = "{name} - {name}",
        title_icon = "",
        show_status = false,
        status_icons = {},
      }
      local result = termlet._format_terminal_title(cfg, "build", nil)
      -- Both {name} placeholders should be replaced
      assert.are.equal("build - build", result)
    end)

    it("should replace multiple {icon} occurrences", function()
      local cfg = {
        title_format = "{icon} {name} {icon}",
        title_icon = "X",
        show_status = false,
        status_icons = {},
      }
      local result = termlet._format_terminal_title(cfg, "test", nil)
      assert.is_truthy(result:find("X test X", 1, true))
    end)

    it("should replace multiple {status} occurrences", function()
      local cfg = {
        title_format = "{status} {name} {status}",
        title_icon = "",
        show_status = true,
        status_icons = { running = "R" },
      }
      local result = termlet._format_terminal_title(cfg, "build", "running")
      -- Both {status} should become "R"
      local _, count = result:gsub("R", "")
      assert.are.equal(2, count)
    end)
  end)

  describe("update_terminal_status", function()
    it("should update title with success status on exit code 0", function()
      termlet.setup({
        scripts = {},
        terminal = {
          show_status = true,
          title_format = " {name} {status} ",
          status_icons = { running = "●", success = "✓", error = "✗" },
        },
      })
      local buf, win = termlet.create_floating_terminal({ title = "build" })
      assert.is_not_nil(win)

      local updated = termlet._update_terminal_status(win, 0)
      assert.is_true(updated)

      local win_config = vim.api.nvim_win_get_config(win)
      local title_text = ""
      if type(win_config.title) == "string" then
        title_text = win_config.title
      elseif type(win_config.title) == "table" then
        for _, part in ipairs(win_config.title) do
          if type(part) == "table" then
            title_text = title_text .. (part[1] or "")
          elseif type(part) == "string" then
            title_text = title_text .. part
          end
        end
      end
      assert.is_truthy(title_text:find("✓", 1, true))
    end)

    it("should update title with error status on non-zero exit code", function()
      termlet.setup({
        scripts = {},
        terminal = {
          show_status = true,
          title_format = " {name} {status} ",
          status_icons = { running = "●", success = "✓", error = "✗" },
        },
      })
      local buf, win = termlet.create_floating_terminal({ title = "build" })
      assert.is_not_nil(win)

      local updated = termlet._update_terminal_status(win, 1)
      assert.is_true(updated)

      local win_config = vim.api.nvim_win_get_config(win)
      local title_text = ""
      if type(win_config.title) == "string" then
        title_text = win_config.title
      elseif type(win_config.title) == "table" then
        for _, part in ipairs(win_config.title) do
          if type(part) == "table" then
            title_text = title_text .. (part[1] or "")
          elseif type(part) == "string" then
            title_text = title_text .. part
          end
        end
      end
      assert.is_truthy(title_text:find("✗", 1, true))
    end)

    it("should return false when show_status is disabled", function()
      termlet.setup({
        scripts = {},
        terminal = {
          show_status = false,
        },
      })
      local buf, win = termlet.create_floating_terminal({ title = "build" })
      assert.is_not_nil(win)

      local updated = termlet._update_terminal_status(win, 0)
      assert.is_false(updated)
    end)

    it("should return false for invalid window", function()
      termlet.setup({
        scripts = {},
        terminal = { show_status = true },
      })
      -- Use a window ID that doesn't exist
      local updated = termlet._update_terminal_status(99999, 0)
      assert.is_false(updated)
    end)
  end)

  describe("title_pos validation", function()
    it("should fall back to center for invalid title_pos", function()
      termlet.setup({
        scripts = {},
        terminal = { title_pos = "middle" },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      assert.are.equal("center", win_config.title_pos)
    end)

    it("should accept valid title_pos values", function()
      for _, pos in ipairs({ "left", "center", "right" }) do
        termlet.setup({
          scripts = {},
          terminal = { title_pos = pos },
        })
        local buf, win = termlet.create_floating_terminal({})
        assert.is_not_nil(win)

        local win_config = vim.api.nvim_win_get_config(win)
        assert.are.equal(pos, win_config.title_pos)
      end
    end)
  end)

  describe("border table validation", function()
    it("should fall back to rounded for border table with wrong length", function()
      termlet.setup({
        scripts = {},
        terminal = {
          border = { "╭", "─", "╮", "│", "╯" }, -- only 5 elements
        },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)
      -- Should not error — falls back to "rounded"
    end)

    it("should accept border table with exactly 8 elements", function()
      termlet.setup({
        scripts = {},
        terminal = {
          border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
        },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      assert.is_table(win_config.border)
    end)
  end)

  describe("should_exclude_dir", function()
    it("should exclude hidden directories when exclude_hidden is true", function()
      termlet.setup({ scripts = {} })
      local search_config = { exclude_hidden = true, exclude_dirs = {} }
      assert.is_true(termlet._should_exclude_dir(".git", search_config))
      assert.is_true(termlet._should_exclude_dir(".cache", search_config))
      assert.is_true(termlet._should_exclude_dir(".hidden", search_config))
    end)

    it("should not exclude hidden directories when exclude_hidden is false", function()
      termlet.setup({ scripts = {} })
      local search_config = { exclude_hidden = false, exclude_dirs = {} }
      assert.is_false(termlet._should_exclude_dir(".git", search_config))
      assert.is_false(termlet._should_exclude_dir(".cache", search_config))
    end)

    it("should exclude directories in exclude_dirs list", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_hidden = false,
        exclude_dirs = { "node_modules", "dist", "build" },
      }
      assert.is_true(termlet._should_exclude_dir("node_modules", search_config))
      assert.is_true(termlet._should_exclude_dir("dist", search_config))
      assert.is_true(termlet._should_exclude_dir("build", search_config))
    end)

    it("should not exclude directories not in the list", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_hidden = false,
        exclude_dirs = { "node_modules" },
      }
      assert.is_false(termlet._should_exclude_dir("src", search_config))
      assert.is_false(termlet._should_exclude_dir("scripts", search_config))
      assert.is_false(termlet._should_exclude_dir("lib", search_config))
    end)

    it("should handle empty exclude_dirs list", function()
      termlet.setup({ scripts = {} })
      local search_config = { exclude_hidden = false, exclude_dirs = {} }
      assert.is_false(termlet._should_exclude_dir("node_modules", search_config))
      assert.is_false(termlet._should_exclude_dir("anything", search_config))
    end)

    it("should combine hidden and explicit exclusions", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_hidden = true,
        exclude_dirs = { "node_modules", "vendor" },
      }
      -- Hidden dir excluded by exclude_hidden
      assert.is_true(termlet._should_exclude_dir(".secret", search_config))
      -- Explicit dir excluded by list
      assert.is_true(termlet._should_exclude_dir("node_modules", search_config))
      assert.is_true(termlet._should_exclude_dir("vendor", search_config))
      -- Not excluded
      assert.is_false(termlet._should_exclude_dir("src", search_config))
    end)

    it("should use default config when search_config is nil", function()
      termlet.setup({ scripts = {} })
      -- Uses defaults: exclude_hidden=true and the default exclude_dirs list
      assert.is_true(termlet._should_exclude_dir(".git", nil))
      assert.is_true(termlet._should_exclude_dir("node_modules", nil))
      assert.is_false(termlet._should_exclude_dir("src", nil))
    end)

    it("should exclude all default directories", function()
      termlet.setup({ scripts = {} })
      local defaults = {
        "node_modules", ".git", ".svn", ".hg", "dist", "build",
        "target", "__pycache__", ".cache", ".tox", ".mypy_cache",
        ".pytest_cache", "vendor", "venv", ".venv", "env",
      }
      for _, dir in ipairs(defaults) do
        assert.is_true(termlet._should_exclude_dir(dir, nil),
          "Expected '" .. dir .. "' to be excluded by defaults")
      end
    end)
  end)

  describe("should_exclude_file", function()
    it("should exclude files matching glob patterns", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = { "*.min.*" },
        exclude_dirs = {},
        exclude_hidden = false,
      }
      assert.is_true(termlet._should_exclude_file("app.min.js", search_config))
      assert.is_true(termlet._should_exclude_file("styles.min.css", search_config))
    end)

    it("should not exclude files that do not match patterns", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = { "*.min.*" },
        exclude_dirs = {},
        exclude_hidden = false,
      }
      assert.is_false(termlet._should_exclude_file("app.js", search_config))
      assert.is_false(termlet._should_exclude_file("build.sh", search_config))
    end)

    it("should handle multiple patterns", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = { "*.min.*", "*.bundle.*", "*.bak" },
        exclude_dirs = {},
        exclude_hidden = false,
      }
      assert.is_true(termlet._should_exclude_file("app.min.js", search_config))
      assert.is_true(termlet._should_exclude_file("vendor.bundle.js", search_config))
      assert.is_true(termlet._should_exclude_file("data.bak", search_config))
      assert.is_false(termlet._should_exclude_file("main.lua", search_config))
    end)

    it("should handle empty patterns list", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = {},
        exclude_dirs = {},
        exclude_hidden = false,
      }
      assert.is_false(termlet._should_exclude_file("anything.js", search_config))
    end)

    it("should support ? wildcard for single character", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = { "test?.lua" },
        exclude_dirs = {},
        exclude_hidden = false,
      }
      assert.is_true(termlet._should_exclude_file("test1.lua", search_config))
      assert.is_true(termlet._should_exclude_file("testA.lua", search_config))
      assert.is_false(termlet._should_exclude_file("test12.lua", search_config))
      assert.is_false(termlet._should_exclude_file("test.lua", search_config))
    end)

    it("should use default config when search_config is nil", function()
      -- Default has empty exclude_patterns, so nothing should be excluded
      termlet.setup({ scripts = {} })
      assert.is_false(termlet._should_exclude_file("anything.js", nil))
    end)
  end)

  describe("search configuration", function()
    it("should accept custom search config in setup", function()
      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = { "custom_dir", "another_dir" },
          exclude_hidden = false,
          exclude_patterns = { "*.tmp" },
        },
      })
      -- Should not error
      assert.is_not_nil(termlet)
    end)

    it("should merge search config with defaults", function()
      termlet.setup({
        scripts = {},
        search = {
          exclude_hidden = false,
        },
      })
      -- After deep merge, exclude_hidden should be false
      -- but exclude_dirs should still have defaults
      assert.is_not_nil(termlet)
      -- Verify by testing the function with nil (uses internal config)
      -- exclude_hidden was set to false, so hidden dirs are NOT excluded
      assert.is_false(termlet._should_exclude_dir(".hidden_dir", nil))
      -- But explicit dirs from default list should still be excluded
      assert.is_true(termlet._should_exclude_dir("node_modules", nil))
    end)

    it("should allow replacing exclude_dirs entirely", function()
      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = { "only_this" },
        },
      })
      assert.is_true(termlet._should_exclude_dir("only_this", nil))
      -- Default dirs like node_modules should no longer be excluded
      -- because tbl_deep_extend replaces the list
      assert.is_false(termlet._should_exclude_dir("node_modules", nil))
    end)

    it("should allow adding exclude_patterns", function()
      termlet.setup({
        scripts = {},
        search = {
          exclude_patterns = { "*.min.*", "*.bundle.*" },
        },
      })
      assert.is_true(termlet._should_exclude_file("app.min.js", nil))
      assert.is_true(termlet._should_exclude_file("vendor.bundle.js", nil))
      assert.is_false(termlet._should_exclude_file("app.js", nil))
    end)
  end)
end)
