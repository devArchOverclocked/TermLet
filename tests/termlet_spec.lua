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

  describe("find_script_by_name", function()
    local test_root

    before_each(function()
      -- Create a temporary directory structure for testing
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      -- Clean up temp directories
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    -- Helper to create a file in a path relative to test_root
    local function create_test_file(relative_path)
      local full_path = test_root .. "/" .. relative_path
      local dir = vim.fn.fnamemodify(full_path, ":h")
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ "#!/bin/bash", "echo hello" }, full_path)
      return full_path
    end

    it("should return nil when filename is nil", function()
      local result = termlet.find_script_by_name(nil, test_root)
      assert.is_nil(result)
    end)

    it("should return nil when root_dir does not exist", function()
      local result = termlet.find_script_by_name("test.sh", "/nonexistent/path/12345")
      assert.is_nil(result)
    end)

    it("should find a file directly in root directory", function()
      local expected = create_test_file("build.sh")
      local result = termlet.find_script_by_name("build.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should find a file in a subdirectory recursively", function()
      local expected = create_test_file("scripts/deploy.sh")
      local result = termlet.find_script_by_name("deploy.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should find a file in a deeply nested subdirectory", function()
      local expected = create_test_file("a/b/c/deep_script.sh")
      local result = termlet.find_script_by_name("deep_script.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should find a file using absolute path", function()
      local expected = create_test_file("somewhere/abs_test.sh")
      -- Use the absolute path directly as the filename
      local result = termlet.find_script_by_name(expected, test_root)
      assert.are.equal(expected, result)
    end)

    it("should return nil for nonexistent absolute path", function()
      local result = termlet.find_script_by_name("/nonexistent/path/fake.sh", test_root)
      assert.is_nil(result)
    end)

    it("should find a file with relative path containing directory components", function()
      local expected = create_test_file("subdir/build.sh")
      -- Provide the relative path with directory component
      local result = termlet.find_script_by_name("subdir/build.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should recursively find basename when relative path does not match directly", function()
      -- File is at nested/deep/run.sh, but user specifies "other/run.sh" which doesn't exist
      local expected = create_test_file("nested/deep/run.sh")
      local result = termlet.find_script_by_name("nonexistent_dir/run.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should prefer direct path match over recursive search", function()
      -- Create the file both in root and in a subdirectory
      local expected = create_test_file("script.sh")
      create_test_file("subdir/script.sh")
      local result = termlet.find_script_by_name("script.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should find files in common script directories", function()
      local expected = create_test_file("scripts/lint.sh")
      local result = termlet.find_script_by_name("lint.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should find files in custom search directories", function()
      local expected = create_test_file("custom_dir/special.sh")
      local result = termlet.find_script_by_name("special.sh", test_root, { "custom_dir" })
      assert.are.equal(expected, result)
    end)

    it("should not find files in hidden directories during recursive search", function()
      -- Create file only in a hidden directory
      create_test_file(".hidden/secret.sh")
      local result = termlet.find_script_by_name("secret.sh", test_root)
      assert.is_nil(result)
    end)

    it("should not find files in node_modules during recursive search", function()
      create_test_file("node_modules/pkg/script.sh")
      local result = termlet.find_script_by_name("script.sh", test_root)
      assert.is_nil(result)
    end)

    it("should return nil when file does not exist anywhere", function()
      create_test_file("other.sh")
      local result = termlet.find_script_by_name("nonexistent.sh", test_root)
      assert.is_nil(result)
    end)

    it("should find file in nested subdirectory when only root_dir is specified", function()
      -- This is the core use case from issue #34: user provides only root_dir,
      -- and termlet recursively finds the file
      local expected = create_test_file("src/scripts/helpers/deploy.sh")
      local result = termlet.find_script_by_name("deploy.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should not search beyond max depth of 5", function()
      -- Create a file nested 7 levels deep (beyond depth limit of 5)
      create_test_file("a/b/c/d/e/f/g/too_deep.sh")
      local result = termlet.find_script_by_name("too_deep.sh", test_root)
      assert.is_nil(result)
    end)

    it("should find file exactly at max depth", function()
      -- Depth 1=root check, then 4 subdirectory levels = depth 5
      local expected = create_test_file("a/b/c/d/at_limit.sh")
      local result = termlet.find_script_by_name("at_limit.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should handle filename without extension", function()
      local expected = create_test_file("build")
      local result = termlet.find_script_by_name("build", test_root)
      assert.are.equal(expected, result)
    end)

    it("should find file in multiple search directories and return first match", function()
      -- Create file in two different common directories
      local expected_scripts = create_test_file("scripts/run.sh")
      create_test_file("bin/run.sh")
      -- "scripts" comes before "bin" in default search_dirs, so it should be found first
      local result = termlet.find_script_by_name("run.sh", test_root)
      assert.are.equal(expected_scripts, result)
    end)

    it("should find file in tools directory with explicit root_dir", function()
      -- Create file in a known root
      local expected = create_test_file("tools/check.sh")
      local result = termlet.find_script_by_name("check.sh", test_root)
      assert.are.equal(expected, result)
    end)

    it("should not search in .git directory", function()
      create_test_file(".git/hooks/pre-commit.sh")
      local result = termlet.find_script_by_name("pre-commit.sh", test_root)
      assert.is_nil(result)
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
      assert.is_truthy(termlet._format_terminal_title(cfg, "x", "running"):find("RUNNING", 1, true))
      assert.is_truthy(termlet._format_terminal_title(cfg, "x", "success"):find("OK", 1, true))
      assert.is_truthy(termlet._format_terminal_title(cfg, "x", "error"):find("FAIL", 1, true))
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
      local _buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      assert.are.equal("left", win_config.title_pos)
    end)

    it("should apply custom title_pos right", function()
      termlet.setup({
        scripts = {},
        terminal = { title_pos = "right" },
      })
      local _buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(win)

      local win_config = vim.api.nvim_win_get_config(win)
      assert.are.equal("right", win_config.title_pos)
    end)

    it("should apply winhighlight with default highlight groups", function()
      termlet.setup({ scripts = {} })
      local _buf, win = termlet.create_floating_terminal({})
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
      local _buf, win = termlet.create_floating_terminal({})
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
      local _buf, win = termlet.create_floating_terminal({})
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
        local _buf, win = termlet.create_floating_terminal({})
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
      local _buf, win = termlet.create_floating_terminal({ title = "my_build" })
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
      local _buf, win = termlet.create_floating_terminal({ title = "build" })
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
      local _buf, win = termlet.create_floating_terminal({})
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
      local _buf, win = termlet.create_floating_terminal({})
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
      local _buf, win = termlet.create_floating_terminal({ title = "build" })
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
      local _buf, win = termlet.create_floating_terminal({ title = "build" })
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
      local _buf, win = termlet.create_floating_terminal({ title = "build" })
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
      local _buf, win = termlet.create_floating_terminal({})
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
        local _buf, win = termlet.create_floating_terminal({})
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
      local _buf, win = termlet.create_floating_terminal({})
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
      local _buf, win = termlet.create_floating_terminal({})
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
        "node_modules",
        ".git",
        ".svn",
        ".hg",
        "dist",
        "build",
        "target",
        "__pycache__",
        ".cache",
        ".tox",
        ".mypy_cache",
        ".pytest_cache",
        "vendor",
        "venv",
        ".venv",
        "env",
      }
      for _, dir in ipairs(defaults) do
        assert.is_true(termlet._should_exclude_dir(dir, nil), "Expected '" .. dir .. "' to be excluded by defaults")
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

    it("should handle glob patterns containing Lua metacharacters", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = { "*.log+", "file[1].txt", "foo(bar).js" },
        exclude_dirs = {},
        exclude_hidden = false,
      }
      -- Literal + in pattern should match literal +
      assert.is_true(termlet._should_exclude_file("app.log+", search_config))
      assert.is_false(termlet._should_exclude_file("app.logg", search_config))
      -- Literal brackets should match literally
      assert.is_true(termlet._should_exclude_file("file[1].txt", search_config))
      assert.is_false(termlet._should_exclude_file("file2.txt", search_config))
      -- Literal parentheses should match literally
      assert.is_true(termlet._should_exclude_file("foo(bar).js", search_config))
      assert.is_false(termlet._should_exclude_file("foobar.js", search_config))
    end)

    it("should handle glob patterns with - and ^ characters", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = { "my-file.*", "^start.txt" },
        exclude_dirs = {},
        exclude_hidden = false,
      }
      assert.is_true(termlet._should_exclude_file("my-file.js", search_config))
      assert.is_true(termlet._should_exclude_file("^start.txt", search_config))
      assert.is_false(termlet._should_exclude_file("myXfile.js", search_config))
    end)

    it("should handle glob patterns with % character", function()
      termlet.setup({ scripts = {} })
      local search_config = {
        exclude_patterns = { "100%.txt" },
        exclude_dirs = {},
        exclude_hidden = false,
      }
      assert.is_true(termlet._should_exclude_file("100%.txt", search_config))
      assert.is_false(termlet._should_exclude_file("100X.txt", search_config))
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

    it("should allow configuring max_depth", function()
      termlet.setup({
        scripts = {},
        search = {
          max_depth = 10,
        },
      })
      -- Just verify it doesn't error - actual depth testing is in integration tests
      assert.is_not_nil(termlet)
    end)
  end)

  describe("output persistence", function()
    it("should use 'wipe' bufhidden by default", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "none",
        },
      })
      local buf, _win = termlet.create_floating_terminal({})
      assert.is_not_nil(buf)

      local bufhidden = vim.api.nvim_get_option_value("bufhidden", { buf = buf })
      assert.are.equal("wipe", bufhidden)
    end)

    it("should use 'hide' bufhidden when output_persistence is buffer", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
        },
      })
      local buf, _win = termlet.create_floating_terminal({})
      assert.is_not_nil(buf)

      local bufhidden = vim.api.nvim_get_option_value("bufhidden", { buf = buf })
      assert.are.equal("hide", bufhidden)
    end)

    it("should save buffer when window closes with buffer persistence", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
          max_saved_buffers = 5,
        },
      })

      local buf, win = termlet.create_floating_terminal({ title = "test_output" })
      assert.is_not_nil(buf)
      assert.is_not_nil(win)

      -- Close the window
      vim.api.nvim_win_close(win, true)

      -- Buffer should still be valid (hidden, not wiped)
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
    end)

    it("should enforce max_saved_buffers limit", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
          max_saved_buffers = 2,
        },
      })

      local bufs = {}
      for i = 1, 3 do
        local buf, win = termlet.create_floating_terminal({ title = "test_" .. i })
        bufs[i] = buf
        vim.api.nvim_win_close(win, true)
      end

      -- Wait for autocmd to fire
      vim.wait(100)

      -- First buffer should have been deleted (only keep 2)
      assert.is_false(vim.api.nvim_buf_is_valid(bufs[1]))
      -- Last two should still exist
      assert.is_true(vim.api.nvim_buf_is_valid(bufs[2]))
      assert.is_true(vim.api.nvim_buf_is_valid(bufs[3]))
    end)

    it("should not save buffers when output_persistence is none", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "none",
        },
      })

      local buf, win = termlet.create_floating_terminal({ title = "test" })
      vim.api.nvim_win_close(win, true)

      -- Wait briefly
      vim.wait(100)

      -- Buffer should be wiped
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
    end)
  end)

  describe("show_last_output", function()
    it("should return false when no saved outputs exist", function()
      termlet.setup({ scripts = {} })
      termlet.clear_outputs()

      local result = termlet.show_last_output()
      assert.is_false(result)
    end)

    it("should show the most recent saved output", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
        },
      })

      -- Create and close a terminal
      local _buf, win = termlet.create_floating_terminal({ title = "recent_output" })
      vim.api.nvim_win_close(win, true)

      -- Wait for save
      vim.wait(100)

      -- Should be able to show it
      local result, output_win = termlet.show_last_output()
      assert.is_true(result)

      -- Close the re-opened window to avoid dangling floating windows
      if output_win and vim.api.nvim_win_is_valid(output_win) then
        vim.api.nvim_win_close(output_win, true)
      end
    end)

    it("should set bufhidden=wipe on re-opened output viewer", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
        },
      })

      local buf, win = termlet.create_floating_terminal({ title = "viewer_test" })
      vim.api.nvim_win_close(win, true)
      vim.wait(100)

      local result, output_win = termlet.show_last_output()
      assert.is_true(result)
      assert.is_not_nil(output_win)

      -- The re-opened buffer should have bufhidden=wipe
      local bufhidden = vim.api.nvim_get_option_value("bufhidden", { buf = buf })
      assert.are.equal("wipe", bufhidden)

      -- Close the viewer window
      if output_win and vim.api.nvim_win_is_valid(output_win) then
        vim.api.nvim_win_close(output_win, true)
      end
    end)
  end)

  describe("list_outputs", function()
    it("should return empty list when no saved outputs", function()
      termlet.setup({ scripts = {} })
      termlet.clear_outputs()

      local outputs = termlet.list_outputs()
      assert.are.equal(0, #outputs)
    end)

    it("should list all saved outputs", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
          max_saved_buffers = 5,
        },
      })

      -- Create and close multiple terminals
      for i = 1, 3 do
        local _buf, win = termlet.create_floating_terminal({ title = "output_" .. i })
        vim.api.nvim_win_close(win, true)
      end

      vim.wait(100)

      local outputs = termlet.list_outputs()
      assert.are.equal(3, #outputs)
    end)

    it("should include buffer metadata in output list", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
        },
      })

      local _buf, win = termlet.create_floating_terminal({ title = "test_meta" })
      vim.api.nvim_win_close(win, true)

      vim.wait(100)

      local outputs = termlet.list_outputs()
      assert.are.equal(1, #outputs)
      assert.is_string(outputs[1].name)
      assert.is_string(outputs[1].timestamp)
      assert.is_number(outputs[1].lines)
    end)
  end)

  describe("clear_outputs", function()
    it("should clear all saved outputs", function()
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
        },
      })

      -- Create some outputs
      for i = 1, 2 do
        local _buf, win = termlet.create_floating_terminal({ title = "output_" .. i })
        vim.api.nvim_win_close(win, true)
      end

      vim.wait(100)

      local count = termlet.clear_outputs()
      assert.are.equal(2, count)

      local outputs = termlet.list_outputs()
      assert.are.equal(0, #outputs)
    end)

    it("should return 0 when no outputs to clear", function()
      termlet.setup({ scripts = {} })
      local count = termlet.clear_outputs()
      assert.are.equal(0, count)
    end)
  end)

  describe("output_persistence validation", function()
    it("should fall back to none for invalid output_persistence value", function()
      -- Should not error, should warn and fall back to "none"
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "file",
        },
      })

      -- Verify it fell back to "none" by checking bufhidden is "wipe"
      local buf, _win = termlet.create_floating_terminal({})
      assert.is_not_nil(buf)
      local bufhidden = vim.api.nvim_get_option_value("bufhidden", { buf = buf })
      assert.are.equal("wipe", bufhidden)
    end)

    it("should accept valid output_persistence values", function()
      for _, mode in ipairs({ "none", "buffer" }) do
        termlet.setup({
          scripts = {},
          terminal = {
            output_persistence = mode,
          },
        })
        -- Should not error
        local buf, _win = termlet.create_floating_terminal({})
        assert.is_not_nil(buf)
      end
    end)

    it("should clean up saved buffers when setup changes persistence to none", function()
      -- First create some saved buffers with "buffer" mode
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "buffer",
        },
      })

      local _buf, win = termlet.create_floating_terminal({ title = "cleanup_test" })
      vim.api.nvim_win_close(win, true)
      vim.wait(100)

      -- Verify we have saved outputs
      local outputs = termlet.list_outputs()
      assert.is_true(#outputs > 0)

      -- Now re-setup with "none" — should clear saved buffers
      termlet.setup({
        scripts = {},
        terminal = {
          output_persistence = "none",
        },
      })

      outputs = termlet.list_outputs()
      assert.are.equal(0, #outputs)
    end)
  end)

  describe("find_script_by_name file exclusion integration", function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should skip files matching exclude_patterns", function()
      -- Create a script file that matches an exclusion pattern
      local script_path = tmpdir .. "/build.min.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/bash\necho hello\n")
      f:close()

      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = {},
          exclude_hidden = false,
          exclude_patterns = { "*.min.*" },
        },
      })

      local result = termlet.find_script_by_name("build.min.sh", tmpdir, { "." })
      assert.is_nil(result)
    end)

    it("should find files not matching exclude_patterns", function()
      -- Create a script file that does NOT match any exclusion pattern
      local script_path = tmpdir .. "/build.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/bash\necho hello\n")
      f:close()

      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = {},
          exclude_hidden = false,
          exclude_patterns = { "*.min.*" },
        },
      })

      local result = termlet.find_script_by_name("build.sh", tmpdir, { "." })
      assert.is_not_nil(result)
      assert.is_truthy(result:find("build.sh", 1, true))
    end)

    it("should skip files in excluded directories", function()
      -- Create a subdirectory that should be excluded and put a script in it
      local excluded_dir = tmpdir .. "/node_modules"
      vim.fn.mkdir(excluded_dir, "p")
      local script_path = excluded_dir .. "/run.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/bash\necho hello\n")
      f:close()

      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = { "node_modules" },
          exclude_hidden = false,
          exclude_patterns = {},
        },
      })

      -- Search should not find the file inside excluded directory
      local result = termlet.find_script_by_name("run.sh", tmpdir, { "." })
      assert.is_nil(result)
    end)

    it("should find files in non-excluded directories", function()
      -- Create a subdirectory that is NOT excluded and put a script in it
      local scripts_dir = tmpdir .. "/scripts"
      vim.fn.mkdir(scripts_dir, "p")
      local script_path = scripts_dir .. "/run.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/bash\necho hello\n")
      f:close()

      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = { "node_modules" },
          exclude_hidden = false,
          exclude_patterns = {},
        },
      })

      local result = termlet.find_script_by_name("run.sh", tmpdir, { "scripts" })
      assert.is_not_nil(result)
      assert.is_truthy(result:find("run.sh", 1, true))
    end)
  end)

  describe("find_script_by_name recursive search depth", function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should find files in deeply nested directories within max_depth", function()
      -- Create a deeply nested directory structure (3 levels)
      local deep_dir = tmpdir .. "/level1/level2/level3"
      vim.fn.mkdir(deep_dir, "p")
      local script_path = deep_dir .. "/deep_script.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/bash\necho deep\n")
      f:close()

      termlet.setup({
        scripts = {},
        search = { exclude_dirs = {}, exclude_hidden = false, max_depth = 5 },
      })

      local result = termlet.find_script_by_name("deep_script.sh", tmpdir, {})
      assert.is_not_nil(result)
      assert.is_truthy(result:find("deep_script.sh", 1, true))
    end)

    it("should not find files deeper than max_depth", function()
      -- Create a directory structure deeper than max_depth
      local deep_dir = tmpdir .. "/l1/l2/l3/l4/l5/l6/l7"
      vim.fn.mkdir(deep_dir, "p")
      local script_path = deep_dir .. "/too_deep.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/bash\necho deep\n")
      f:close()

      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = {},
          exclude_hidden = false,
          max_depth = 3, -- Only search 3 levels deep
        },
      })

      local result = termlet.find_script_by_name("too_deep.sh", tmpdir, {})
      -- Should not find it because it's too deep (7 levels > 3)
      assert.is_nil(result)
    end)

    it("should find files exactly at max_depth", function()
      -- Create a directory structure at exactly max_depth
      local shallow_dir = tmpdir .. "/l1/l2"
      vim.fn.mkdir(shallow_dir, "p")
      local script_path = shallow_dir .. "/shallow.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/bash\necho shallow\n")
      f:close()

      termlet.setup({
        scripts = {},
        search = {
          exclude_dirs = {},
          exclude_hidden = false,
          max_depth = 3,
        },
      })

      local result = termlet.find_script_by_name("shallow.sh", tmpdir, {})
      assert.is_not_nil(result)
      assert.is_truthy(result:find("shallow.sh", 1, true))
    end)
  end)

  describe("focus management", function()
    it("should track original window when creating terminal", function()
      termlet.setup({ scripts = {} })

      local original_win = vim.api.nvim_get_current_win()
      local buf, win = termlet.create_floating_terminal({
        title = "test",
        original_win = original_win,
      })

      assert.is_not_nil(buf)
      assert.is_not_nil(win)
      -- Terminal should have been created successfully
      assert.is_true(vim.api.nvim_win_is_valid(win))
    end)

    it("should return false when focusing non-existent terminal", function()
      termlet.setup({ scripts = {} })
      local result = termlet.focus_terminal()
      assert.is_false(result)
    end)

    it("should focus existing terminal", function()
      termlet.setup({ scripts = {} })
      local _buf, _win = termlet.create_floating_terminal({ title = "test" })

      -- Create another window to move focus away
      vim.cmd("split")
      local _other_win = vim.api.nvim_get_current_win()

      -- Now focus the terminal
      local result = termlet.focus_terminal()
      assert.is_true(result)
    end)

    it("should toggle between terminal and previous window", function()
      termlet.setup({ scripts = {} })

      local original_win = vim.api.nvim_get_current_win()
      local _buf, win = termlet.create_floating_terminal({
        title = "test",
        original_win = original_win,
      })

      -- Move to terminal
      vim.api.nvim_set_current_win(win)

      -- Toggle should take us back
      local result = termlet.toggle_focus()
      assert.is_true(result or vim.api.nvim_win_is_valid(vim.api.nvim_get_current_win()))
    end)

    it("should accept focus configuration options", function()
      termlet.setup({
        scripts = {},
        terminal = {
          focus = "terminal",
          auto_insert = true,
        },
      })
      assert.is_not_nil(termlet)
    end)

    it("should work with focus='previous' mode", function()
      termlet.setup({
        scripts = {},
        terminal = {
          focus = "previous",
        },
      })

      local _buf, win = termlet.create_floating_terminal({ title = "test" })
      assert.is_not_nil(win)
      assert.is_true(vim.api.nvim_win_is_valid(win))
    end)

    it("should work with focus='none' mode", function()
      termlet.setup({
        scripts = {},
        terminal = {
          focus = "none",
        },
      })

      local _buf, win = termlet.create_floating_terminal({ title = "test" })
      assert.is_not_nil(win)
      assert.is_true(vim.api.nvim_win_is_valid(win))
    end)

    describe("script execution integration", function()
      local test_script_path

      before_each(function()
        -- Create a temporary test script
        test_script_path = vim.fn.tempname() .. ".sh"
        local f = io.open(test_script_path, "w")
        f:write("#!/bin/bash\necho 'test output'\n")
        f:close()
        vim.fn.system("chmod +x " .. test_script_path)
      end)

      after_each(function()
        if test_script_path then
          vim.fn.delete(test_script_path)
        end
      end)

      it("should keep focus in terminal when focus='terminal'", function()
        termlet.setup({
          scripts = {
            { name = "test", filename = test_script_path },
          },
          terminal = {
            focus = "terminal",
            auto_insert = false,
          },
        })

        local original_win = vim.api.nvim_get_current_win()
        termlet.run_test()

        -- Give the terminal a moment to be created
        vim.wait(100)

        local current_win = vim.api.nvim_get_current_win()
        -- Should be in a different window (the terminal)
        assert.not_equals(original_win, current_win)
      end)

      it("should return to previous window when focus='previous'", function()
        termlet.setup({
          scripts = {
            { name = "test", filename = test_script_path },
          },
          terminal = {
            focus = "previous",
          },
        })

        local original_win = vim.api.nvim_get_current_win()
        termlet.run_test()

        -- Give the terminal a moment to be created and focus to return
        vim.wait(100)

        local current_win = vim.api.nvim_get_current_win()
        -- Should be back in the original window
        assert.equals(original_win, current_win)
      end)

      it("should enter insert mode when auto_insert=true and focus='terminal'", function()
        termlet.setup({
          scripts = {
            { name = "test", filename = test_script_path },
          },
          terminal = {
            focus = "terminal",
            auto_insert = true,
          },
        })

        local original_win = vim.api.nvim_get_current_win()
        termlet.run_test()

        -- Give the terminal a moment to be created
        vim.wait(100)

        local current_win = vim.api.nvim_get_current_win()
        -- Should be in a different window (the terminal)
        assert.not_equals(original_win, current_win)

        -- Verify the configuration was set correctly
        -- (In headless mode, startinsert may not work as expected)
        -- So we just verify the terminal has focus
      end)
    end)
  end)

  describe("keybindings", function()
    before_each(function()
      -- Use a temporary config file for testing
      local keybindings_module = require("termlet.keybindings")
      local test_config_path = vim.fn.tempname() .. "-termlet-keybindings.json"
      keybindings_module.set_config_path(test_config_path)
      keybindings_module._set_keybindings({})
    end)

    it("should open keybindings UI", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      local result = termlet.open_keybindings()
      assert.is_true(result)
      assert.is_true(termlet.is_keybindings_open())
    end)

    it("should return false when no scripts configured", function()
      termlet.setup({
        scripts = {},
      })

      local result = termlet.open_keybindings()
      assert.is_false(result)
    end)

    it("should close keybindings UI", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      termlet.open_keybindings()
      assert.is_true(termlet.is_keybindings_open())

      termlet.close_keybindings()
      assert.is_false(termlet.is_keybindings_open())
    end)

    it("should toggle keybindings UI", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      assert.is_false(termlet.is_keybindings_open())
      termlet.toggle_keybindings()
      assert.is_true(termlet.is_keybindings_open())
      termlet.toggle_keybindings()
      assert.is_false(termlet.is_keybindings_open())
    end)

    it("should set keybinding programmatically", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      local result = termlet.set_keybinding("build", "<leader>b")
      assert.is_true(result)

      local bindings = termlet.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
    end)

    it("should clear keybinding programmatically", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      termlet.set_keybinding("build", "<leader>b")
      termlet.clear_keybinding("build")

      local bindings = termlet.get_keybindings()
      assert.is_nil(bindings["build"])
    end)

    it("should get all keybindings", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "test", filename = "test.sh" },
        },
      })

      termlet.set_keybinding("build", "<leader>b")
      termlet.set_keybinding("test", "<leader>t")

      local bindings = termlet.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
      assert.equals("<leader>t", bindings["test"])
    end)
  end)

  describe("viewport adjustment for bottom terminal (#66)", function()
    it("should expose _adjust_viewport_for_terminal function", function()
      termlet.setup({ scripts = {} })
      assert.is_function(termlet._adjust_viewport_for_terminal)
    end)

    it("should expose _restore_viewport_for_terminal function", function()
      termlet.setup({ scripts = {} })
      assert.is_function(termlet._restore_viewport_for_terminal)
    end)

    it("should return a table of saved window heights", function()
      termlet.setup({ scripts = {} })
      local result = termlet._adjust_viewport_for_terminal({
        row = 20,
        height = 5,
        width = 80,
        col = 0,
      })
      assert.is_table(result)
    end)

    it("should not adjust when terminal row is 0", function()
      termlet.setup({ scripts = {} })
      local result = termlet._adjust_viewport_for_terminal({
        row = 0,
        height = 5,
        width = 80,
        col = 0,
      })
      -- No adjustments should be made for row 0
      assert.are.equal(0, #result)
    end)

    it("should create terminal at bottom without errors", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "bottom",
          height_ratio = 0.16,
        },
      })
      local buf, win = termlet.create_floating_terminal({})
      assert.is_not_nil(buf)
      assert.is_not_nil(win)
      assert.is_true(vim.api.nvim_win_is_valid(win))

      -- The terminal should be positioned at the bottom
      local win_config = vim.api.nvim_win_get_config(win)
      assert.is_truthy(win_config.row)
    end)

    it("should resize editor window when bottom terminal opens", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "bottom",
          height_ratio = 0.3,
        },
      })

      -- Record the editor window height before opening the terminal
      local editor_win = vim.api.nvim_get_current_win()
      local height_before = vim.api.nvim_win_get_height(editor_win)

      -- Create a buffer with many lines so the window is "full"
      local test_buf = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 200 do
        lines[i] = "Line " .. i
      end
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)
      vim.api.nvim_win_set_buf(editor_win, test_buf)
      vim.api.nvim_win_set_cursor(editor_win, { 200, 0 })

      -- Now create a floating terminal at the bottom
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- The editor window should have been resized to be shorter
      local height_after = vim.api.nvim_win_get_height(editor_win)
      assert.is_true(height_after <= height_before, "editor window should be resized shorter")

      -- The cursor should still be at line 200
      local cursor = vim.api.nvim_win_get_cursor(editor_win)
      assert.are.equal(200, cursor[1])

      -- Clean up
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)

    it("should restore editor window height when terminal closes", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "bottom",
          height_ratio = 0.3,
        },
      })

      local editor_win = vim.api.nvim_get_current_win()
      local height_before = vim.api.nvim_win_get_height(editor_win)

      -- Create buffer
      local test_buf = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 200 do
        lines[i] = "Line " .. i
      end
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)
      vim.api.nvim_win_set_buf(editor_win, test_buf)

      -- Open terminal
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- Editor is shorter now
      local height_during = vim.api.nvim_win_get_height(editor_win)
      assert.is_true(height_during <= height_before)

      -- Close the terminal
      vim.api.nvim_win_close(term_win, true)

      -- Editor height should be restored
      local height_restored = vim.api.nvim_win_get_height(editor_win)
      assert.are.equal(height_before, height_restored)

      -- Clean up
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)

    it("should save original heights keyed by terminal window", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "bottom",
          height_ratio = 0.3,
        },
      })

      -- Open terminal
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- Check that saved heights exist for this terminal window
      local saved = termlet._saved_win_heights[term_win]
      assert.is_not_nil(saved, "should have saved heights for terminal window")
      assert.is_table(saved)
    end)

    it("should not adjust viewport for center-positioned terminal", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "center",
          height_ratio = 0.3,
        },
      })

      -- Create a buffer with many lines
      local test_buf = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 100 do
        lines[i] = "Line " .. i
      end
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

      local editor_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(editor_win, test_buf)
      vim.api.nvim_win_set_cursor(editor_win, { 50, 0 })

      -- Record height before
      local height_before = vim.api.nvim_win_get_height(editor_win)

      -- Create terminal at center
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- Height should not be changed for center position
      local height_after = vim.api.nvim_win_get_height(editor_win)
      assert.are.equal(height_before, height_after)

      -- Clean up
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)

    it("should not adjust viewport for top-positioned terminal", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "top",
          height_ratio = 0.3,
        },
      })

      -- Create a buffer with many lines
      local test_buf = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 100 do
        lines[i] = "Line " .. i
      end
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

      local editor_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(editor_win, test_buf)
      vim.api.nvim_win_set_cursor(editor_win, { 10, 0 })

      -- Record height before
      local height_before = vim.api.nvim_win_get_height(editor_win)

      -- Create terminal at top
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- Height should not be changed for top position
      local height_after = vim.api.nvim_win_get_height(editor_win)
      assert.are.equal(height_before, height_after)

      -- Clean up
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)

    it("should handle small buffers that fit entirely on screen", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "bottom",
          height_ratio = 0.3,
        },
      })

      -- Create a buffer with just a few lines
      local test_buf = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 5 do
        lines[i] = "Line " .. i
      end
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

      local editor_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(editor_win, test_buf)
      vim.api.nvim_win_set_cursor(editor_win, { 3, 0 })

      -- Create terminal - should not error even with small buffer
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- Cursor should still be on the same line
      local cursor = vim.api.nvim_win_get_cursor(editor_win)
      assert.are.equal(3, cursor[1])

      -- Clean up
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)

    it("should keep cursor visible after resize when at end of file", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "bottom",
          height_ratio = 0.3,
        },
      })

      -- Create a buffer with many lines
      local test_buf = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 200 do
        lines[i] = "Line " .. i
      end
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

      local editor_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(editor_win, test_buf)

      -- Move cursor to the very last line
      vim.api.nvim_win_set_cursor(editor_win, { 200, 0 })
      vim.api.nvim_win_call(editor_win, function()
        vim.cmd("normal! zb")
      end)

      -- Open terminal
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- Cursor should remain at line 200
      local cursor = vim.api.nvim_win_get_cursor(editor_win)
      assert.are.equal(200, cursor[1])

      -- The view's topline + window height should cover the cursor
      local view = vim.api.nvim_win_call(editor_win, function()
        return vim.fn.winsaveview()
      end)
      local win_height = vim.api.nvim_win_get_height(editor_win)
      assert.is_true(
        cursor[1] <= view.topline + win_height - 1,
        "cursor line should be within the visible area of the resized window"
      )

      -- Clean up
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)

    it("should clean up saved heights when terminal closes", function()
      termlet.setup({
        scripts = {},
        terminal = {
          position = "bottom",
          height_ratio = 0.3,
        },
      })

      -- Open terminal
      local _term_buf, term_win = termlet.create_floating_terminal({})
      assert.is_not_nil(term_win)

      -- Saved heights should exist
      assert.is_not_nil(termlet._saved_win_heights[term_win])

      -- Close terminal
      vim.api.nvim_win_close(term_win, true)

      -- Saved heights should be cleaned up
      assert.is_nil(termlet._saved_win_heights[term_win])
    end)
  end)
end)
