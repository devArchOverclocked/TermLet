-- Tests for TermLet menu module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local menu = require("termlet.menu")

describe("termlet.menu", function()
  local test_scripts = {
    { name = "build", description = "Build the project", filename = "build.sh" },
    { name = "test", description = "Run tests", filename = "test.sh" },
    { name = "deploy", description = "Deploy to staging", filename = "deploy.sh" },
    { name = "lint", description = "Run linter", filename = "lint.sh" },
  }

  local executed_script = nil
  local function mock_execute(script)
    executed_script = script
  end

  before_each(function()
    executed_script = nil
    -- Close any existing menu
    menu.close()
  end)

  after_each(function()
    menu.close()
  end)

  describe("open", function()
    it("should open the menu with scripts", function()
      local result = menu.open(test_scripts, mock_execute)
      assert.is_true(result)
      assert.is_true(menu.is_open())
    end)

    it("should initialize state correctly", function()
      menu.open(test_scripts, mock_execute)
      local state = menu.get_state()

      assert.equals(1, state.selected_index)
      assert.equals("", state.search_query)
      assert.is_false(state.search_mode)
      assert.is_false(state.show_help)
      assert.equals(4, state.filtered_count)
      assert.equals(4, state.total_count)
    end)

    it("should handle empty scripts list", function()
      menu.open({}, mock_execute)
      local state = menu.get_state()

      assert.equals(1, state.selected_index)
      assert.equals(0, state.filtered_count)
      assert.equals(0, state.total_count)
    end)
  end)

  describe("close", function()
    it("should close the menu", function()
      menu.open(test_scripts, mock_execute)
      assert.is_true(menu.is_open())

      menu.close()
      assert.is_false(menu.is_open())
    end)

    it("should reset state on close", function()
      menu.open(test_scripts, mock_execute)
      menu.actions.enter_search_mode()
      menu.actions.handle_search_input("b")
      menu.actions.toggle_help()

      menu.close()

      -- Reopen and check state is reset
      menu.open(test_scripts, mock_execute)
      local state = menu.get_state()

      assert.equals("", state.search_query)
      assert.is_false(state.search_mode)
      assert.is_false(state.show_help)
    end)
  end)

  describe("navigation", function()
    before_each(function()
      menu.open(test_scripts, mock_execute)
    end)

    it("should move down correctly", function()
      local state = menu.get_state()
      assert.equals(1, state.selected_index)

      menu.actions.move_down()
      state = menu.get_state()
      assert.equals(2, state.selected_index)

      menu.actions.move_down()
      state = menu.get_state()
      assert.equals(3, state.selected_index)
    end)

    it("should wrap around when moving down past last item", function()
      -- Move to last item
      menu.actions.go_to_last()
      local state = menu.get_state()
      assert.equals(4, state.selected_index)

      -- Move down should wrap to first
      menu.actions.move_down()
      state = menu.get_state()
      assert.equals(1, state.selected_index)
    end)

    it("should move up correctly", function()
      menu.actions.move_down()
      menu.actions.move_down()
      local state = menu.get_state()
      assert.equals(3, state.selected_index)

      menu.actions.move_up()
      state = menu.get_state()
      assert.equals(2, state.selected_index)
    end)

    it("should wrap around when moving up past first item", function()
      local state = menu.get_state()
      assert.equals(1, state.selected_index)

      -- Move up should wrap to last
      menu.actions.move_up()
      state = menu.get_state()
      assert.equals(4, state.selected_index)
    end)

    it("should go to first item with go_to_first", function()
      menu.actions.go_to_last()
      local state = menu.get_state()
      assert.equals(4, state.selected_index)

      menu.actions.go_to_first()
      state = menu.get_state()
      assert.equals(1, state.selected_index)
    end)

    it("should go to last item with go_to_last", function()
      local state = menu.get_state()
      assert.equals(1, state.selected_index)

      menu.actions.go_to_last()
      state = menu.get_state()
      assert.equals(4, state.selected_index)
    end)
  end)

  describe("search", function()
    before_each(function()
      menu.open(test_scripts, mock_execute)
    end)

    it("should enter search mode", function()
      menu.actions.enter_search_mode()
      local state = menu.get_state()
      assert.is_true(state.search_mode)
      assert.equals("", state.search_query)
    end)

    it("should filter scripts by name", function()
      menu.actions.enter_search_mode()
      menu.actions.handle_search_input("b")
      menu.actions.handle_search_input("u")
      menu.actions.handle_search_input("i")
      menu.actions.handle_search_input("l")
      menu.actions.handle_search_input("d")

      local state = menu.get_state()
      assert.equals("build", state.search_query)
      assert.equals(1, state.filtered_count)
    end)

    it("should filter scripts by description", function()
      menu.actions.enter_search_mode()
      menu.actions.handle_search_input("s")
      menu.actions.handle_search_input("t")
      menu.actions.handle_search_input("a")
      menu.actions.handle_search_input("g")

      local state = menu.get_state()
      assert.equals("stag", state.search_query)
      assert.equals(1, state.filtered_count) -- Only "deploy" has "staging"
    end)

    it("should handle backspace in search", function()
      menu.actions.enter_search_mode()
      menu.actions.handle_search_input("t")
      menu.actions.handle_search_input("e")
      menu.actions.handle_search_input("s")
      menu.actions.handle_search_input("t")

      local state = menu.get_state()
      assert.equals("test", state.search_query)

      menu.actions.handle_search_input("<BS>")
      state = menu.get_state()
      assert.equals("tes", state.search_query)
    end)

    it("should clear search on escape", function()
      menu.actions.enter_search_mode()
      menu.actions.handle_search_input("b")
      menu.actions.handle_search_input("u")

      local state = menu.get_state()
      assert.equals(1, state.filtered_count)

      menu.actions.handle_search_input("<Esc>")
      state = menu.get_state()
      assert.equals("", state.search_query)
      assert.is_false(state.search_mode)
      assert.equals(4, state.filtered_count)
    end)

    it("should be case insensitive", function()
      menu.actions.enter_search_mode()
      menu.actions.handle_search_input("B")
      menu.actions.handle_search_input("U")
      menu.actions.handle_search_input("I")
      menu.actions.handle_search_input("L")
      menu.actions.handle_search_input("D")

      local state = menu.get_state()
      assert.equals("BUILD", state.search_query)
      assert.equals(1, state.filtered_count) -- Should still find "build"
    end)

    it("should adjust selected_index when filtering reduces list", function()
      -- Select last item
      menu.actions.go_to_last()
      local state = menu.get_state()
      assert.equals(4, state.selected_index)

      -- Filter to fewer items
      menu.actions.enter_search_mode()
      menu.actions.handle_search_input("b")
      menu.actions.handle_search_input("u")
      menu.actions.handle_search_input("i")
      menu.actions.handle_search_input("l")
      menu.actions.handle_search_input("d")

      state = menu.get_state()
      -- selected_index should be clamped to valid range
      assert.equals(1, state.selected_index)
      assert.equals(1, state.filtered_count)
    end)
  end)

  describe("help", function()
    before_each(function()
      menu.open(test_scripts, mock_execute)
    end)

    it("should toggle help display", function()
      local state = menu.get_state()
      assert.is_false(state.show_help)

      menu.actions.toggle_help()
      state = menu.get_state()
      assert.is_true(state.show_help)

      menu.actions.toggle_help()
      state = menu.get_state()
      assert.is_false(state.show_help)
    end)

    it("should not navigate when help is shown", function()
      menu.actions.toggle_help()

      local state = menu.get_state()
      local initial_index = state.selected_index

      menu.actions.move_down()
      state = menu.get_state()
      assert.equals(initial_index, state.selected_index)

      menu.actions.move_up()
      state = menu.get_state()
      assert.equals(initial_index, state.selected_index)
    end)

    it("should close help on execute_selected", function()
      menu.actions.toggle_help()
      local state = menu.get_state()
      assert.is_true(state.show_help)

      menu.actions.execute_selected()
      state = menu.get_state()
      assert.is_false(state.show_help)
      -- Menu should still be open after just closing help
      assert.is_true(menu.is_open())
    end)
  end)

  describe("execute_selected", function()
    before_each(function()
      menu.open(test_scripts, mock_execute)
    end)

    it("should execute the selected script", function()
      -- Wait for scheduled callback
      local done = false
      menu.open(test_scripts, function(script)
        executed_script = script
        done = true
      end)

      menu.actions.execute_selected()

      -- Give vim.schedule time to run
      vim.wait(100, function()
        return done
      end)

      assert.is_not_nil(executed_script)
      assert.equals("build", executed_script.name)
    end)

    it("should execute the correct script after navigation", function()
      local done = false
      menu.open(test_scripts, function(script)
        executed_script = script
        done = true
      end)

      menu.actions.move_down()
      menu.actions.move_down()

      local state = menu.get_state()
      assert.equals(3, state.selected_index)

      menu.actions.execute_selected()

      vim.wait(100, function()
        return done
      end)

      assert.is_not_nil(executed_script)
      assert.equals("deploy", executed_script.name)
    end)

    it("should close menu after execution", function()
      menu.open(test_scripts, mock_execute)
      menu.actions.execute_selected()

      -- Menu should be closed
      assert.is_false(menu.is_open())
    end)

    it("should do nothing when no scripts", function()
      menu.open({}, mock_execute)
      menu.actions.execute_selected()

      assert.is_nil(executed_script)
    end)
  end)

  describe("is_open", function()
    it("should return false when menu not opened", function()
      assert.is_false(menu.is_open())
    end)

    it("should return true when menu is open", function()
      menu.open(test_scripts, mock_execute)
      assert.is_true(menu.is_open())
    end)

    it("should return false after closing", function()
      menu.open(test_scripts, mock_execute)
      menu.close()
      assert.is_false(menu.is_open())
    end)
  end)

  describe("custom configuration", function()
    it("should accept custom menu configuration", function()
      local custom_config = {
        width_ratio = 0.8,
        height_ratio = 0.7,
        border = "single",
        title = " Custom Title ",
      }

      local result = menu.open(test_scripts, mock_execute, custom_config)
      assert.is_true(result)
      assert.is_true(menu.is_open())
    end)
  end)
end)
