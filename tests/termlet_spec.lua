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
end)
