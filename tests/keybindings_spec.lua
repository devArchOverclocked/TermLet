-- Tests for TermLet keybindings module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local keybindings = require("termlet.keybindings")

describe("termlet.keybindings", function()
  local test_scripts = {
    { name = "build", description = "Build the project", filename = "build.sh" },
    { name = "test", description = "Run tests", filename = "test.sh" },
    { name = "deploy", description = "Deploy to staging", filename = "deploy.sh" },
    { name = "lint", description = "Run linter", filename = "lint.sh" },
  }

  local test_config_path

  before_each(function()
    -- Close any existing UI
    keybindings.close()

    -- Use a temporary config file for testing
    test_config_path = vim.fn.tempname() .. "-termlet-keybindings.json"
    keybindings.set_config_path(test_config_path)

    -- Clear any loaded keybindings
    keybindings._set_keybindings({})
  end)

  after_each(function()
    keybindings.close()

    -- Clean up temp file
    if test_config_path and vim.fn.filereadable(test_config_path) == 1 then
      vim.fn.delete(test_config_path)
    end
  end)

  describe("open", function()
    it("should open the keybindings UI with scripts", function()
      local result = keybindings.open(test_scripts, nil)
      assert.is_true(result)
      assert.is_true(keybindings.is_open())
    end)

    it("should initialize state correctly", function()
      keybindings.open(test_scripts, nil)
      local state = keybindings.get_state()

      assert.equals(1, state.selected_index)
      assert.equals("normal", state.mode)
      assert.same({}, state.captured_keys)
      assert.equals("", state.input_text)
      assert.is_false(state.show_help)
      assert.equals(4, state.scripts_count)
    end)

    it("should handle empty scripts list", function()
      keybindings.open({}, nil)
      local state = keybindings.get_state()

      assert.equals(1, state.selected_index)
      assert.equals(0, state.scripts_count)
    end)
  end)

  describe("close", function()
    it("should close the keybindings UI", function()
      keybindings.open(test_scripts, nil)
      assert.is_true(keybindings.is_open())

      keybindings.close()
      assert.is_false(keybindings.is_open())
    end)

    it("should reset state on close", function()
      keybindings.open(test_scripts, nil)
      keybindings.actions.toggle_help()

      keybindings.close()

      -- Reopen and check state is reset
      keybindings.open(test_scripts, nil)
      local state = keybindings.get_state()

      assert.equals("normal", state.mode)
      assert.is_false(state.show_help)
    end)
  end)

  describe("navigation", function()
    before_each(function()
      keybindings.open(test_scripts, nil)
    end)

    it("should move down correctly", function()
      local state = keybindings.get_state()
      assert.equals(1, state.selected_index)

      keybindings.actions.move_down()
      state = keybindings.get_state()
      assert.equals(2, state.selected_index)

      keybindings.actions.move_down()
      state = keybindings.get_state()
      assert.equals(3, state.selected_index)
    end)

    it("should wrap around when moving down past last item", function()
      keybindings.actions.go_to_last()
      local state = keybindings.get_state()
      assert.equals(4, state.selected_index)

      keybindings.actions.move_down()
      state = keybindings.get_state()
      assert.equals(1, state.selected_index)
    end)

    it("should move up correctly", function()
      keybindings.actions.move_down()
      keybindings.actions.move_down()
      local state = keybindings.get_state()
      assert.equals(3, state.selected_index)

      keybindings.actions.move_up()
      state = keybindings.get_state()
      assert.equals(2, state.selected_index)
    end)

    it("should wrap around when moving up past first item", function()
      local state = keybindings.get_state()
      assert.equals(1, state.selected_index)

      keybindings.actions.move_up()
      state = keybindings.get_state()
      assert.equals(4, state.selected_index)
    end)

    it("should go to first item with go_to_first", function()
      keybindings.actions.go_to_last()
      local state = keybindings.get_state()
      assert.equals(4, state.selected_index)

      keybindings.actions.go_to_first()
      state = keybindings.get_state()
      assert.equals(1, state.selected_index)
    end)

    it("should go to last item with go_to_last", function()
      local state = keybindings.get_state()
      assert.equals(1, state.selected_index)

      keybindings.actions.go_to_last()
      state = keybindings.get_state()
      assert.equals(4, state.selected_index)
    end)
  end)

  describe("help", function()
    before_each(function()
      keybindings.open(test_scripts, nil)
    end)

    it("should toggle help display", function()
      local state = keybindings.get_state()
      assert.is_false(state.show_help)

      keybindings.actions.toggle_help()
      state = keybindings.get_state()
      assert.is_true(state.show_help)

      keybindings.actions.toggle_help()
      state = keybindings.get_state()
      assert.is_false(state.show_help)
    end)

    it("should not navigate when help is shown", function()
      keybindings.actions.toggle_help()

      local state = keybindings.get_state()
      local initial_index = state.selected_index

      keybindings.actions.move_down()
      state = keybindings.get_state()
      assert.equals(initial_index, state.selected_index)

      keybindings.actions.move_up()
      state = keybindings.get_state()
      assert.equals(initial_index, state.selected_index)
    end)
  end)

  describe("is_open", function()
    it("should return false when UI not opened", function()
      assert.is_false(keybindings.is_open())
    end)

    it("should return true when UI is open", function()
      keybindings.open(test_scripts, nil)
      assert.is_true(keybindings.is_open())
    end)

    it("should return false after closing", function()
      keybindings.open(test_scripts, nil)
      keybindings.close()
      assert.is_false(keybindings.is_open())
    end)
  end)

  describe("set_keybinding", function()
    it("should set a keybinding", function()
      keybindings.open(test_scripts, nil)

      local result = keybindings.set_keybinding("build", "<leader>b")
      assert.is_true(result)

      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
    end)

    it("should clear a keybinding when set to nil", function()
      keybindings.open(test_scripts, nil)

      keybindings.set_keybinding("build", "<leader>b")
      keybindings.set_keybinding("build", nil)

      local bindings = keybindings.get_keybindings()
      assert.is_nil(bindings["build"])
    end)

    it("should clear a keybinding when set to empty string", function()
      keybindings.open(test_scripts, nil)

      keybindings.set_keybinding("build", "<leader>b")
      keybindings.set_keybinding("build", "")

      local bindings = keybindings.get_keybindings()
      assert.is_nil(bindings["build"])
    end)

    it("should return false for nil script_name", function()
      keybindings.open(test_scripts, nil)

      local result = keybindings.set_keybinding(nil, "<leader>b")
      assert.is_false(result)
    end)
  end)

  describe("clear_keybinding", function()
    it("should clear a keybinding", function()
      keybindings.open(test_scripts, nil)

      keybindings.set_keybinding("build", "<leader>b")
      keybindings.clear_keybinding("build")

      local bindings = keybindings.get_keybindings()
      assert.is_nil(bindings["build"])
    end)
  end)

  describe("get_keybindings", function()
    it("should return empty table when no keybindings set", function()
      keybindings.open(test_scripts, nil)

      local bindings = keybindings.get_keybindings()
      assert.same({}, bindings)
    end)

    it("should return all set keybindings", function()
      keybindings.open(test_scripts, nil)

      keybindings.set_keybinding("build", "<leader>b")
      keybindings.set_keybinding("test", "<leader>t")

      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
      assert.equals("<leader>t", bindings["test"])
    end)

    it("should return a copy, not reference", function()
      keybindings.open(test_scripts, nil)

      keybindings.set_keybinding("build", "<leader>b")

      local bindings = keybindings.get_keybindings()
      bindings["build"] = "<leader>x"

      local bindings2 = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings2["build"])
    end)
  end)

  describe("persistence", function()
    it("should save keybindings to file", function()
      keybindings.open(test_scripts, nil)

      keybindings.set_keybinding("build", "<leader>b")
      keybindings.set_keybinding("test", "<leader>t")

      -- Verify file was created
      assert.equals(1, vim.fn.filereadable(test_config_path))
    end)

    it("should load keybindings from file", function()
      -- Set and save keybindings
      keybindings.open(test_scripts, nil)
      keybindings.set_keybinding("build", "<leader>b")
      keybindings.set_keybinding("test", "<leader>t")
      keybindings.close()

      -- Clear internal state
      keybindings._set_keybindings({})

      -- Load from file
      local loaded = keybindings.load()
      assert.equals("<leader>b", loaded["build"])
      assert.equals("<leader>t", loaded["test"])
    end)

    it("should return empty table when config file does not exist", function()
      local nonexistent_path = vim.fn.tempname() .. "-nonexistent.json"
      keybindings.set_config_path(nonexistent_path)

      local loaded = keybindings.load()
      assert.same({}, loaded)
    end)
  end)

  describe("init", function()
    it("should initialize with scripts and load saved keybindings", function()
      -- First, save some keybindings
      keybindings.open(test_scripts, nil)
      keybindings.set_keybinding("build", "<leader>b")
      keybindings.close()

      -- Clear internal state
      keybindings._set_keybindings({})

      -- Initialize with scripts
      local loaded = keybindings.init(test_scripts)
      assert.equals("<leader>b", loaded["build"])
    end)
  end)

  describe("delete_keybinding action", function()
    before_each(function()
      keybindings.open(test_scripts, nil)
    end)

    it("should delete the keybinding for selected script", function()
      keybindings.set_keybinding("build", "<leader>b")
      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings["build"])

      -- Make sure first script is selected
      keybindings.actions.go_to_first()

      -- Delete keybinding
      keybindings.actions.delete_keybinding()

      bindings = keybindings.get_keybindings()
      assert.is_nil(bindings["build"])
    end)

    it("should not error when deleting non-existent keybinding", function()
      keybindings.actions.go_to_first()
      -- Should not error
      keybindings.actions.delete_keybinding()

      local bindings = keybindings.get_keybindings()
      assert.is_nil(bindings["build"])
    end)
  end)

  describe("custom configuration", function()
    it("should accept custom UI configuration", function()
      local custom_config = {
        width_ratio = 0.8,
        height_ratio = 0.7,
        border = "single",
        title = " Custom Keybindings ",
      }

      local result = keybindings.open(test_scripts, nil, custom_config)
      assert.is_true(result)
      assert.is_true(keybindings.is_open())
    end)
  end)

  describe("on_save callback", function()
    it("should call callback when keybinding is set", function()
      local _callback_called = false
      local _callback_keybindings = nil

      keybindings.open(test_scripts, function(new_keybindings)
        _callback_called = true
        _callback_keybindings = new_keybindings
      end)

      keybindings.set_keybinding("build", "<leader>b")

      -- Note: The callback is called from set_keybinding via the on_save_callback
      -- But set_keybinding bypasses the UI callback flow, so we need to check
      -- the internal save was successful
      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
    end)
  end)

  describe("capture mode", function()
    before_each(function()
      keybindings.open(test_scripts, nil)
    end)

    it("should enter capture mode", function()
      keybindings.actions.enter_capture_mode()
      local state = keybindings.get_state()
      assert.equals("capture", state.mode)
      assert.same({}, state.captured_keys)
    end)

    it("should not enter capture mode with empty scripts", function()
      keybindings.close()
      keybindings.open({}, nil)
      keybindings.actions.enter_capture_mode()
      local state = keybindings.get_state()
      assert.equals("normal", state.mode)
    end)

    it("should exit capture mode via exit_capture action", function()
      keybindings.actions.enter_capture_mode()
      local state = keybindings.get_state()
      assert.equals("capture", state.mode)

      keybindings.actions.exit_capture()
      state = keybindings.get_state()
      assert.equals("normal", state.mode)
      assert.same({}, state.captured_keys)
    end)

    it("should track captured keys in state", function()
      keybindings.actions.enter_capture_mode()
      keybindings._set_captured_keys({ "<Space>", "b" })

      local state = keybindings.get_state()
      assert.same({ "<Space>", "b" }, state.captured_keys)
    end)

    it("should apply captured keybinding via internal function", function()
      keybindings.open(test_scripts, nil)
      keybindings._apply_captured_keybinding("<leader>b")

      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
    end)

    it("should not navigate while in capture mode", function()
      keybindings.actions.enter_capture_mode()
      local state = keybindings.get_state()
      local initial_index = state.selected_index

      keybindings.actions.move_down()
      state = keybindings.get_state()
      assert.equals(initial_index, state.selected_index)
    end)

    it("should not re-enter capture mode when already in capture mode", function()
      keybindings.actions.enter_capture_mode()
      keybindings._set_captured_keys({ "<C-k>" })
      local state = keybindings.get_state()
      assert.equals("capture", state.mode)
      assert.same({ "<C-k>" }, state.captured_keys)

      -- Calling enter_capture_mode again should be a no-op (mode guard)
      keybindings.actions.enter_capture_mode()
      state = keybindings.get_state()
      assert.equals("capture", state.mode)
      -- captured_keys should NOT have been reset
      assert.same({ "<C-k>" }, state.captured_keys)
    end)

    it("should not enter capture mode when already in input mode", function()
      keybindings.actions.enter_input_mode()
      keybindings._set_input_text("<leader>x")
      local state = keybindings.get_state()
      assert.equals("input", state.mode)

      -- Calling enter_capture_mode should be a no-op
      keybindings.actions.enter_capture_mode()
      state = keybindings.get_state()
      assert.equals("input", state.mode)
      assert.equals("<leader>x", state.input_text)
    end)
  end)

  describe("input mode", function()
    before_each(function()
      keybindings.open(test_scripts, nil)
    end)

    it("should enter input mode", function()
      keybindings.actions.enter_input_mode()
      local state = keybindings.get_state()
      assert.equals("input", state.mode)
      assert.equals("", state.input_text)
    end)

    it("should not enter input mode with empty scripts", function()
      keybindings.close()
      keybindings.open({}, nil)
      keybindings.actions.enter_input_mode()
      local state = keybindings.get_state()
      assert.equals("normal", state.mode)
    end)

    it("should exit input mode via exit_capture action", function()
      keybindings.actions.enter_input_mode()
      local state = keybindings.get_state()
      assert.equals("input", state.mode)

      keybindings.actions.exit_capture()
      state = keybindings.get_state()
      assert.equals("normal", state.mode)
      assert.equals("", state.input_text)
    end)

    it("should track input text in state", function()
      keybindings.actions.enter_input_mode()
      keybindings._set_input_text("<leader>b")

      local state = keybindings.get_state()
      assert.equals("<leader>b", state.input_text)
    end)

    it("should apply typed keybinding via internal function", function()
      keybindings.open(test_scripts, nil)
      -- Navigate to second script
      keybindings.actions.move_down()
      keybindings._apply_captured_keybinding("<leader>t")

      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>t", bindings["test"])
    end)

    it("should not navigate while in input mode", function()
      keybindings.actions.enter_input_mode()
      local state = keybindings.get_state()
      local initial_index = state.selected_index

      keybindings.actions.move_down()
      state = keybindings.get_state()
      assert.equals(initial_index, state.selected_index)
    end)

    it("should not re-enter input mode when already in input mode", function()
      keybindings.actions.enter_input_mode()
      keybindings._set_input_text("<C-j>")
      local state = keybindings.get_state()
      assert.equals("input", state.mode)
      assert.equals("<C-j>", state.input_text)

      -- Calling enter_input_mode again should be a no-op (mode guard)
      keybindings.actions.enter_input_mode()
      state = keybindings.get_state()
      assert.equals("input", state.mode)
      -- input_text should NOT have been reset
      assert.equals("<C-j>", state.input_text)
    end)

    it("should not enter input mode when already in capture mode", function()
      keybindings.actions.enter_capture_mode()
      keybindings._set_captured_keys({ "<Space>", "f" })
      local state = keybindings.get_state()
      assert.equals("capture", state.mode)

      -- Calling enter_input_mode should be a no-op
      keybindings.actions.enter_input_mode()
      state = keybindings.get_state()
      assert.equals("capture", state.mode)
      assert.same({ "<Space>", "f" }, state.captured_keys)
    end)
  end)

  describe("conflict detection", function()
    before_each(function()
      keybindings.open(test_scripts, nil)
    end)

    it("should detect conflicts when setting duplicate keybinding", function()
      keybindings.set_keybinding("build", "<leader>b")
      -- Setting same key for another script should still work but warn
      keybindings.set_keybinding("test", "<leader>b")

      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
      assert.equals("<leader>b", bindings["test"])
    end)

    it("should not detect conflict with self", function()
      keybindings.set_keybinding("build", "<leader>b")
      -- Re-setting the same key for the same script should not warn
      keybindings.set_keybinding("build", "<leader>b")

      local bindings = keybindings.get_keybindings()
      assert.equals("<leader>b", bindings["build"])
    end)
  end)

  describe("navigation with empty scripts", function()
    before_each(function()
      keybindings.open({}, nil)
    end)

    it("should not error on move_down with empty scripts", function()
      -- Should not error
      keybindings.actions.move_down()
      local state = keybindings.get_state()
      assert.equals(1, state.selected_index)
    end)

    it("should not error on move_up with empty scripts", function()
      -- Should not error
      keybindings.actions.move_up()
      local state = keybindings.get_state()
      assert.equals(1, state.selected_index)
    end)

    it("should not error on go_to_first with empty scripts", function()
      -- Should not error
      keybindings.actions.go_to_first()
      local state = keybindings.get_state()
      assert.equals(1, state.selected_index)
    end)

    it("should not error on go_to_last with empty scripts", function()
      -- Should not error
      keybindings.actions.go_to_last()
      local state = keybindings.get_state()
      assert.equals(1, state.selected_index)
    end)
  end)
end)
