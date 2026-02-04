-- Tests for TermLet History Module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.history", function()
  local history

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.history"] = nil
    history = require("termlet.history")
    history.clear_history()
  end)

  after_each(function()
    -- Clean up
    if history.is_open() then
      history.close()
    end
    history.clear_history()
  end)

  describe("add_entry", function()
    it("should add entry to history", function()
      history.add_entry({
        script_name = "test_script",
        exit_code = 0,
        execution_time = 1.5,
        timestamp = os.time(),
        working_dir = "/tmp",
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.are.equal("test_script", entries[1].script_name)
      assert.are.equal(0, entries[1].exit_code)
      assert.are.equal(1.5, entries[1].execution_time)
    end)

    it("should add timestamp if not provided", function()
      local before_time = os.time()
      history.add_entry({
        script_name = "test",
        exit_code = 0,
      })
      local after_time = os.time()

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.is_not_nil(entries[1].timestamp)
      assert.is_true(entries[1].timestamp >= before_time)
      assert.is_true(entries[1].timestamp <= after_time)
    end)

    it("should insert new entries at the beginning", function()
      history.add_entry({ script_name = "first", exit_code = 0 })
      history.add_entry({ script_name = "second", exit_code = 0 })
      history.add_entry({ script_name = "third", exit_code = 0 })

      local entries = history.get_entries()
      assert.are.equal("third", entries[1].script_name)
      assert.are.equal("second", entries[2].script_name)
      assert.are.equal("first", entries[3].script_name)
    end)

    it("should not add entry without script_name", function()
      history.add_entry({
        exit_code = 0,
        execution_time = 1.0,
      })

      local entries = history.get_entries()
      assert.are.equal(0, #entries)
    end)

    it("should enforce max_entries limit", function()
      history.set_max_entries(3)

      for i = 1, 5 do
        history.add_entry({ script_name = "script_" .. i, exit_code = 0 })
      end

      local entries = history.get_entries()
      assert.are.equal(3, #entries)
      -- Should keep most recent 3
      assert.are.equal("script_5", entries[1].script_name)
      assert.are.equal("script_4", entries[2].script_name)
      assert.are.equal("script_3", entries[3].script_name)
    end)
  end)

  describe("get_entries", function()
    it("should return empty list initially", function()
      local entries = history.get_entries()
      assert.are.equal(0, #entries)
    end)

    it("should return all entries", function()
      history.add_entry({ script_name = "test1", exit_code = 0 })
      history.add_entry({ script_name = "test2", exit_code = 1 })

      local entries = history.get_entries()
      assert.are.equal(2, #entries)
    end)
  end)

  describe("get_last_entry", function()
    it("should return nil when history is empty", function()
      local last = history.get_last_entry()
      assert.is_nil(last)
    end)

    it("should return most recent entry", function()
      history.add_entry({ script_name = "first", exit_code = 0 })
      history.add_entry({ script_name = "second", exit_code = 1 })

      local last = history.get_last_entry()
      assert.are.equal("second", last.script_name)
      assert.are.equal(1, last.exit_code)
    end)
  end)

  describe("clear_history", function()
    it("should clear all entries", function()
      history.add_entry({ script_name = "test1", exit_code = 0 })
      history.add_entry({ script_name = "test2", exit_code = 0 })

      history.clear_history()

      local entries = history.get_entries()
      assert.are.equal(0, #entries)
    end)

    it("should not error when history is already empty", function()
      history.clear_history()
      history.clear_history()
      -- Should not error
      assert.are.equal(0, #history.get_entries())
    end)
  end)

  describe("set_max_entries", function()
    it("should set maximum entries", function()
      history.set_max_entries(10)

      for i = 1, 15 do
        history.add_entry({ script_name = "script_" .. i, exit_code = 0 })
      end

      local entries = history.get_entries()
      assert.are.equal(10, #entries)
    end)

    it("should trim existing entries when reducing limit", function()
      history.set_max_entries(10)
      for i = 1, 10 do
        history.add_entry({ script_name = "script_" .. i, exit_code = 0 })
      end

      -- Reduce limit
      history.set_max_entries(5)

      local entries = history.get_entries()
      assert.are.equal(5, #entries)
      -- Should keep most recent 5
      assert.are.equal("script_10", entries[1].script_name)
    end)

    it("should ignore invalid max_entries values", function()
      history.set_max_entries(5)
      history.add_entry({ script_name = "test", exit_code = 0 })

      -- Try invalid values
      history.set_max_entries(0)
      history.set_max_entries(-1)
      history.set_max_entries("invalid")
      history.set_max_entries(nil)

      -- Should still work with previous valid value
      local entries = history.get_entries()
      assert.are.equal(1, #entries)
    end)
  end)

  describe("open", function()
    it("should return false when no history", function()
      local result = history.open(function() end)
      assert.is_false(result)
    end)

    it("should open history browser when entries exist", function()
      history.add_entry({ script_name = "test", exit_code = 0 })

      local result = history.open(function() end)
      assert.is_true(result)
      assert.is_true(history.is_open())
    end)

    it("should accept custom UI config", function()
      history.add_entry({ script_name = "test", exit_code = 0 })

      local result = history.open(function() end, {
        width_ratio = 0.8,
        height_ratio = 0.7,
        border = "double",
      })
      assert.is_true(result)
    end)
  end)

  describe("close", function()
    it("should close open history browser", function()
      history.add_entry({ script_name = "test", exit_code = 0 })
      history.open(function() end)
      assert.is_true(history.is_open())

      history.close()
      assert.is_false(history.is_open())
    end)

    it("should not error when no browser is open", function()
      history.close()
      -- Should not error
      assert.is_false(history.is_open())
    end)
  end)

  describe("is_open", function()
    it("should return false initially", function()
      assert.is_false(history.is_open())
    end)

    it("should return true when open", function()
      history.add_entry({ script_name = "test", exit_code = 0 })
      history.open(function() end)
      assert.is_true(history.is_open())
    end)
  end)

  describe("get_state", function()
    it("should return current state", function()
      history.add_entry({ script_name = "test1", exit_code = 0 })
      history.add_entry({ script_name = "test2", exit_code = 0 })

      local state = history.get_state()
      assert.is_number(state.entry_count)
      assert.is_number(state.max_entries)
      assert.are.equal(2, state.entry_count)
    end)
  end)

  describe("history tracking with various scenarios", function()
    it("should track successful execution", function()
      history.add_entry({
        script_name = "build",
        exit_code = 0,
        execution_time = 2.5,
        timestamp = os.time(),
        working_dir = "/project",
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.are.equal("build", entries[1].script_name)
      assert.are.equal(0, entries[1].exit_code)
    end)

    it("should track failed execution", function()
      history.add_entry({
        script_name = "test",
        exit_code = 1,
        execution_time = 0.5,
        timestamp = os.time(),
        working_dir = "/project",
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.are.equal(1, entries[1].exit_code)
    end)

    it("should store script configuration for re-running", function()
      local script_config = {
        name = "build",
        filename = "build.sh",
        root_dir = "/project",
      }

      history.add_entry({
        script_name = "build",
        exit_code = 0,
        execution_time = 1.0,
        timestamp = os.time(),
        working_dir = "/project",
        script = script_config,
      })

      local last = history.get_last_entry()
      assert.is_not_nil(last.script)
      assert.are.equal("build", last.script.name)
      assert.are.equal("build.sh", last.script.filename)
    end)

    it("should track multiple executions of same script", function()
      for i = 1, 3 do
        history.add_entry({
          script_name = "test",
          exit_code = i % 2, -- Alternate success/failure
          execution_time = i * 0.5,
          timestamp = os.time(),
          working_dir = "/project",
        })
      end

      local entries = history.get_entries()
      assert.are.equal(3, #entries)
      -- All should have same script name but different metadata
      assert.are.equal("test", entries[1].script_name)
      assert.are.equal("test", entries[2].script_name)
      assert.are.equal("test", entries[3].script_name)
    end)

    it("should track execution times accurately", function()
      history.add_entry({
        script_name = "quick",
        exit_code = 0,
        execution_time = 0.1,
        timestamp = os.time(),
      })

      history.add_entry({
        script_name = "slow",
        exit_code = 0,
        execution_time = 60.5,
        timestamp = os.time(),
      })

      local entries = history.get_entries()
      assert.are.equal(0.1, entries[2].execution_time)
      assert.are.equal(60.5, entries[1].execution_time)
    end)
  end)

  describe("output_lines storage", function()
    it("should store output_lines in history entry", function()
      local output = { "line 1", "line 2", "error at file.py:10" }
      history.add_entry({
        script_name = "failing_script",
        exit_code = 1,
        execution_time = 0.5,
        timestamp = os.time(),
        working_dir = "/project",
        output_lines = output,
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.is_not_nil(entries[1].output_lines)
      assert.are.equal(3, #entries[1].output_lines)
      assert.are.equal("error at file.py:10", entries[1].output_lines[3])
    end)

    it("should store nil output_lines for successful entries", function()
      history.add_entry({
        script_name = "success_script",
        exit_code = 0,
        execution_time = 1.0,
        timestamp = os.time(),
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.is_nil(entries[1].output_lines)
    end)
  end)

  describe("show_output", function()
    it("should return false when entry has no output_lines", function()
      local result = history.show_output({
        script_name = "test",
        exit_code = 1,
      })
      assert.is_false(result)
    end)

    it("should return false when entry is nil", function()
      local result = history.show_output(nil)
      assert.is_false(result)
    end)

    it("should return false when output_lines is empty", function()
      local result = history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = {},
      })
      assert.is_false(result)
    end)

    it("should open stacktrace viewer with output lines", function()
      local result = history.show_output({
        script_name = "failing_test",
        exit_code = 1,
        output_lines = { "Running tests...", "FAIL: test_example", "Error at line 42" },
      })
      assert.is_true(result)
      assert.is_true(history.is_stacktrace_open())

      -- Clean up
      history.close_stacktrace()
    end)

    it("should display correct content in stacktrace viewer", function()
      local output = { "line 1", "line 2", "line 3" }
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = output,
      })

      local buf = history._get_stacktrace_buf()
      assert.is_not_nil(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(3, #lines)
      assert.are.equal("line 1", lines[1])
      assert.are.equal("line 2", lines[2])
      assert.are.equal("line 3", lines[3])

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("close_stacktrace", function()
    it("should close stacktrace viewer", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error output" },
      })
      assert.is_true(history.is_stacktrace_open())

      history.close_stacktrace()
      assert.is_false(history.is_stacktrace_open())
    end)

    it("should not error when no stacktrace viewer is open", function()
      history.close_stacktrace()
      assert.is_false(history.is_stacktrace_open())
    end)
  end)

  describe("is_stacktrace_open", function()
    it("should return false initially", function()
      assert.is_false(history.is_stacktrace_open())
    end)

    it("should return true when stacktrace viewer is open", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      assert.is_true(history.is_stacktrace_open())

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("get_state with stacktrace", function()
    it("should include stacktrace_open in state", function()
      local state = history.get_state()
      assert.is_boolean(state.stacktrace_open)
      assert.is_false(state.stacktrace_open)
    end)

    it("should reflect open stacktrace in state", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })

      local state = history.get_state()
      assert.is_true(state.stacktrace_open)

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("close with stacktrace", function()
    it("should close both history and stacktrace when close is called", function()
      history.add_entry({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      history.open(function() end)
      assert.is_true(history.is_open())

      -- Open stacktrace viewer
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      assert.is_true(history.is_stacktrace_open())

      -- Close should close both
      history.close()
      assert.is_false(history.is_open())
      assert.is_false(history.is_stacktrace_open())
    end)
  end)

  describe("open with stacktrace_callback", function()
    it("should accept stacktrace_callback parameter", function()
      history.add_entry({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })

      local result = history.open(function() end, nil, function() end)
      assert.is_true(result)

      -- Clean up
      history.close()
    end)

    it("should work without stacktrace_callback", function()
      history.add_entry({
        script_name = "test",
        exit_code = 0,
      })

      local result = history.open(function() end)
      assert.is_true(result)

      -- Clean up
      history.close()
    end)
  end)

  describe("_get_stacktrace_buf", function()
    it("should return nil when no stacktrace is open", function()
      assert.is_nil(history._get_stacktrace_buf())
    end)

    it("should return buffer id when stacktrace is open", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })

      local buf = history._get_stacktrace_buf()
      assert.is_not_nil(buf)
      assert.is_true(vim.api.nvim_buf_is_valid(buf))

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("hide_stacktrace", function()
    it("should hide stacktrace without clearing entry reference", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error output" },
      })
      assert.is_true(history.is_stacktrace_open())

      history.hide_stacktrace()
      assert.is_false(history.is_stacktrace_open())
      -- Entry should still be available for toggle
      assert.is_not_nil(history.get_last_stacktrace_entry())
    end)

    it("should not error when no stacktrace viewer is open", function()
      history.hide_stacktrace()
      assert.is_false(history.is_stacktrace_open())
    end)
  end)

  describe("toggle_stacktrace", function()
    it("should hide visible stacktrace", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error line 1", "error line 2" },
      })
      assert.is_true(history.is_stacktrace_open())

      local visible = history.toggle_stacktrace()
      assert.is_false(visible)
      assert.is_false(history.is_stacktrace_open())
    end)

    it("should reopen hidden stacktrace", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error line 1", "error line 2" },
      })
      assert.is_true(history.is_stacktrace_open())

      -- Hide it
      history.toggle_stacktrace()
      assert.is_false(history.is_stacktrace_open())

      -- Toggle back open
      local visible = history.toggle_stacktrace()
      assert.is_true(visible)
      assert.is_true(history.is_stacktrace_open())

      -- Clean up
      history.close_stacktrace()
    end)

    it("should preserve content after toggle cycle", function()
      local output = { "line 1", "line 2", "error at file.py:10" }
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = output,
      })

      -- Hide and reopen
      history.toggle_stacktrace()
      history.toggle_stacktrace()

      local buf = history._get_stacktrace_buf()
      assert.is_not_nil(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(3, #lines)
      assert.are.equal("line 1", lines[1])
      assert.are.equal("line 2", lines[2])
      assert.are.equal("error at file.py:10", lines[3])

      -- Clean up
      history.close_stacktrace()
    end)

    it("should return false when no entry to toggle", function()
      local visible = history.toggle_stacktrace()
      assert.is_false(visible)
    end)

    it("should return false after close_stacktrace clears entry", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })

      -- Close (not hide) clears the entry
      history.close_stacktrace()

      local visible = history.toggle_stacktrace()
      assert.is_false(visible)
    end)
  end)

  describe("has_hidden_stacktrace", function()
    it("should return false initially", function()
      assert.is_false(history.has_hidden_stacktrace())
    end)

    it("should return false when stacktrace is open (not hidden)", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      assert.is_false(history.has_hidden_stacktrace())

      -- Clean up
      history.close_stacktrace()
    end)

    it("should return true when stacktrace is hidden", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      history.hide_stacktrace()
      assert.is_true(history.has_hidden_stacktrace())

      -- Clean up (close clears the entry)
      history.close_stacktrace()
    end)

    it("should return false after close_stacktrace", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      history.close_stacktrace()
      assert.is_false(history.has_hidden_stacktrace())
    end)
  end)

  describe("get_last_stacktrace_entry", function()
    it("should return nil initially", function()
      assert.is_nil(history.get_last_stacktrace_entry())
    end)

    it("should return entry after showing stacktrace", function()
      local entry = {
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      }
      history.show_output(entry)

      local last = history.get_last_stacktrace_entry()
      assert.is_not_nil(last)
      assert.are.equal("test", last.script_name)

      -- Clean up
      history.close_stacktrace()
    end)

    it("should return entry after hiding stacktrace", function()
      local entry = {
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      }
      history.show_output(entry)
      history.hide_stacktrace()

      local last = history.get_last_stacktrace_entry()
      assert.is_not_nil(last)
      assert.are.equal("test", last.script_name)

      -- Clean up
      history.close_stacktrace()
    end)

    it("should return nil after close_stacktrace", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      history.close_stacktrace()
      assert.is_nil(history.get_last_stacktrace_entry())
    end)
  end)

  describe("get_state with toggle fields", function()
    it("should include has_hidden_stacktrace in state", function()
      local s = history.get_state()
      assert.is_boolean(s.has_hidden_stacktrace)
      assert.is_false(s.has_hidden_stacktrace)
    end)

    it("should reflect hidden stacktrace in state", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      history.hide_stacktrace()

      local s = history.get_state()
      assert.is_false(s.stacktrace_open)
      assert.is_true(s.has_hidden_stacktrace)

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("stacktrace viewer s keymap", function()
    it("should have s keymap that hides stacktrace", function()
      local entry = {
        script_name = "test",
        exit_code = 1,
        output_lines = { "error output" },
      }
      history.show_output(entry)
      assert.is_true(history.is_stacktrace_open())

      local buf = history._get_stacktrace_buf()
      assert.is_not_nil(buf)

      -- Verify the 's' keymap exists on the buffer
      local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
      local has_s_keymap = false
      for _, km in ipairs(keymaps) do
        if km.lhs == "s" then
          has_s_keymap = true
          break
        end
      end
      assert.is_true(has_s_keymap)

      -- Clean up
      history.close_stacktrace()
    end)

    it("should have Esc and q keymaps on stacktrace viewer", function()
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })

      local buf = history._get_stacktrace_buf()
      local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
      local has_q = false
      local has_esc = false
      for _, km in ipairs(keymaps) do
        if km.lhs == "q" then
          has_q = true
        end
        if km.lhs == "<Esc>" then
          has_esc = true
        end
      end
      assert.is_true(has_q)
      assert.is_true(has_esc)

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("toggle_stacktrace with reopen_stacktrace", function()
    it("should preserve entry reference after multiple toggle cycles", function()
      local entry = {
        script_name = "test",
        exit_code = 1,
        output_lines = { "error line 1", "error line 2" },
      }
      history.show_output(entry)

      -- Cycle: hide -> reopen -> hide -> reopen
      for _ = 1, 3 do
        history.toggle_stacktrace() -- hide
        assert.is_false(history.is_stacktrace_open())
        assert.is_not_nil(history.get_last_stacktrace_entry())

        history.toggle_stacktrace() -- reopen
        assert.is_true(history.is_stacktrace_open())
        assert.is_not_nil(history.get_last_stacktrace_entry())
      end

      -- Clean up
      history.close_stacktrace()
    end)

    it("should restore content correctly after reopen", function()
      local output = { "first line", "second line", "third line" }
      history.show_output({
        script_name = "test",
        exit_code = 1,
        output_lines = output,
      })

      -- Toggle off and on
      history.toggle_stacktrace()
      history.toggle_stacktrace()

      local buf = history._get_stacktrace_buf()
      assert.is_not_nil(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(3, #lines)
      assert.are.equal("first line", lines[1])
      assert.are.equal("second line", lines[2])
      assert.are.equal("third line", lines[3])

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("output_lines truncation", function()
    it("should store large output_lines in history entry", function()
      -- Simulate what execute_script does: store only the tail
      local large_output = {}
      for i = 1, 2000 do
        large_output[i] = "output line " .. i
      end

      -- Apply truncation logic matching execute_script
      local max_output_lines = 1000
      local output_lines
      if #large_output > max_output_lines then
        output_lines = { unpack(large_output, #large_output - max_output_lines + 1) }
      else
        output_lines = large_output
      end

      history.add_entry({
        script_name = "verbose_build",
        exit_code = 1,
        execution_time = 5.0,
        timestamp = os.time(),
        working_dir = "/project",
        output_lines = output_lines,
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.are.equal(1000, #entries[1].output_lines)
      -- Should contain the last 1000 lines (1001-2000)
      assert.are.equal("output line 1001", entries[1].output_lines[1])
      assert.are.equal("output line 2000", entries[1].output_lines[1000])
    end)

    it("should pass through output_lines under the limit", function()
      local small_output = {}
      for i = 1, 50 do
        small_output[i] = "line " .. i
      end

      local max_output_lines = 1000
      local output_lines
      if #small_output > max_output_lines then
        output_lines = { unpack(small_output, #small_output - max_output_lines + 1) }
      else
        output_lines = small_output
      end

      history.add_entry({
        script_name = "small_script",
        exit_code = 1,
        execution_time = 0.5,
        timestamp = os.time(),
        output_lines = output_lines,
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.are.equal(50, #entries[1].output_lines)
      assert.are.equal("line 1", entries[1].output_lines[1])
      assert.are.equal("line 50", entries[1].output_lines[50])
    end)

    it("should preserve stacktrace at end of truncated output", function()
      local output = {}
      for i = 1, 1500 do
        output[i] = "build output line " .. i
      end
      -- Add stacktrace lines at the end (these should be preserved)
      output[1501] = "Traceback (most recent call last):"
      output[1502] = '  File "/project/test.py", line 42, in test_func'
      output[1503] = "    assert False"
      output[1504] = "AssertionError"

      local max_output_lines = 1000
      local output_lines
      if #output > max_output_lines then
        output_lines = { unpack(output, #output - max_output_lines + 1) }
      else
        output_lines = output
      end

      history.add_entry({
        script_name = "failing_test",
        exit_code = 1,
        execution_time = 2.0,
        timestamp = os.time(),
        output_lines = output_lines,
      })

      local entries = history.get_entries()
      assert.are.equal(1000, #entries[1].output_lines)
      -- Stacktrace should be at the end
      assert.are.equal("AssertionError", entries[1].output_lines[1000])
      assert.are.equal("    assert False", entries[1].output_lines[999])
      assert.are.equal('  File "/project/test.py", line 42, in test_func', entries[1].output_lines[998])
      assert.are.equal("Traceback (most recent call last):", entries[1].output_lines[997])
    end)

    it("should handle custom max_output_lines value", function()
      local output = {}
      for i = 1, 100 do
        output[i] = "line " .. i
      end

      -- Use a custom smaller limit
      local max_output_lines = 20
      local output_lines
      if #output > max_output_lines then
        output_lines = { unpack(output, #output - max_output_lines + 1) }
      else
        output_lines = output
      end

      history.add_entry({
        script_name = "custom_limit_test",
        exit_code = 1,
        execution_time = 0.5,
        timestamp = os.time(),
        output_lines = output_lines,
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.are.equal(20, #entries[1].output_lines)
      -- Should contain lines 81-100
      assert.are.equal("line 81", entries[1].output_lines[1])
      assert.are.equal("line 100", entries[1].output_lines[20])
    end)
  end)

  describe("integration with execution flow", function()
    it("should maintain history order across multiple operations", function()
      -- Simulate multiple script executions
      local scripts = { "build", "test", "deploy", "lint" }

      for i, name in ipairs(scripts) do
        history.add_entry({
          script_name = name,
          exit_code = 0,
          execution_time = i * 0.5,
          timestamp = os.time() + i,
        })
      end

      local entries = history.get_entries()
      assert.are.equal(4, #entries)
      -- Most recent should be "lint"
      assert.are.equal("lint", entries[1].script_name)
      assert.are.equal("deploy", entries[2].script_name)
      assert.are.equal("test", entries[3].script_name)
      assert.are.equal("build", entries[4].script_name)
    end)

    it("should handle rapid successive executions", function()
      for i = 1, 10 do
        history.add_entry({
          script_name = "rapid_test_" .. i,
          exit_code = 0,
          execution_time = 0.01,
          timestamp = os.time(),
        })
      end

      local entries = history.get_entries()
      assert.are.equal(10, #entries)
    end)
  end)
end)

describe("termlet history integration", function()
  local termlet

  before_each(function()
    -- Clear cached modules
    package.loaded["termlet"] = nil
    package.loaded["termlet.history"] = nil
    termlet = require("termlet")
  end)

  after_each(function()
    if termlet.close_history then
      termlet.close_history()
    end
    termlet.close_all_terminals()
  end)

  describe("setup", function()
    it("should accept history configuration", function()
      termlet.setup({
        scripts = {},
        history = {
          enabled = true,
          max_entries = 100,
        },
      })
      -- Should not error
      assert.is_not_nil(termlet)
    end)

    it("should initialize with default history config", function()
      termlet.setup({
        scripts = {},
      })
      -- Should not error and use defaults
      assert.is_not_nil(termlet)
    end)

    it("should accept max_output_lines in history config", function()
      termlet.setup({
        scripts = {},
        history = {
          enabled = true,
          max_entries = 50,
          max_output_lines = 500,
        },
      })
      -- Should not error
      assert.is_not_nil(termlet)
    end)
  end)

  describe("show_history", function()
    it("should return false when no history", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.show_history()
      assert.is_false(result)
    end)

    it("should notify when history is disabled", function()
      termlet.setup({
        scripts = {},
        history = { enabled = false },
      })

      local result = termlet.show_history()
      assert.is_false(result)
    end)
  end)

  describe("rerun_last", function()
    it("should return false when no history", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.rerun_last()
      assert.is_false(result)
    end)
  end)

  describe("get_history", function()
    it("should return empty list initially", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local entries = termlet.get_history()
      assert.are.equal(0, #entries)
    end)
  end)

  describe("clear_history", function()
    it("should not error when history is empty", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      termlet.clear_history()
      -- Should not error
      assert.are.equal(0, #termlet.get_history())
    end)
  end)

  describe("is_history_open", function()
    it("should return false initially", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      assert.is_false(termlet.is_history_open())
    end)
  end)

  describe("toggle_history", function()
    it("should not error when toggling with no history", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      -- Should not error, just notify
      termlet.toggle_history()
    end)
  end)

  describe("show_history_stacktrace", function()
    it("should return false when entry is nil", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.show_history_stacktrace(nil)
      assert.is_false(result)
    end)

    it("should return false when entry has no output_lines", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.show_history_stacktrace({
        script_name = "test",
        exit_code = 1,
      })
      assert.is_false(result)
    end)

    it("should return false when output_lines is empty", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.show_history_stacktrace({
        script_name = "test",
        exit_code = 1,
        output_lines = {},
      })
      assert.is_false(result)
    end)

    it("should open stacktrace viewer for failed entry with output", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
        stacktrace = { enabled = true },
      })

      local result = termlet.show_history_stacktrace({
        script_name = "failing_test",
        exit_code = 1,
        working_dir = "/tmp",
        output_lines = {
          "Running tests...",
          "FAIL: test_example",
          'File "/tmp/test.py", line 42, in test_func',
          "  assert False",
          "AssertionError",
        },
      })
      assert.is_true(result)

      -- Clean up
      termlet.history.close_stacktrace()
    end)

    it("should show output even when stacktrace detection is disabled", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
        stacktrace = { enabled = false },
      })

      local result = termlet.show_history_stacktrace({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error output line 1", "error output line 2" },
      })
      assert.is_true(result)

      -- Clean up
      termlet.history.close_stacktrace()
    end)
  end)

  describe("toggle_stacktrace", function()
    it("should return false when no stacktrace has been shown", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local visible = termlet.toggle_stacktrace()
      assert.is_false(visible)
    end)

    it("should hide visible stacktrace", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
        stacktrace = { enabled = true },
      })

      termlet.show_history_stacktrace({
        script_name = "test",
        exit_code = 1,
        working_dir = "/tmp",
        output_lines = { "error at line 1" },
      })
      assert.is_true(termlet.history.is_stacktrace_open())

      local visible = termlet.toggle_stacktrace()
      assert.is_false(visible)
      assert.is_false(termlet.history.is_stacktrace_open())

      -- Clean up
      termlet.history.close_stacktrace()
    end)

    it("should reopen hidden stacktrace", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
        stacktrace = { enabled = true },
      })

      termlet.show_history_stacktrace({
        script_name = "test",
        exit_code = 1,
        working_dir = "/tmp",
        output_lines = { "error at line 1", "more output" },
      })

      -- Hide
      termlet.toggle_stacktrace()
      assert.is_false(termlet.history.is_stacktrace_open())

      -- Reopen
      local visible = termlet.toggle_stacktrace()
      assert.is_true(visible)
      assert.is_true(termlet.history.is_stacktrace_open())

      -- Clean up
      termlet.history.close_stacktrace()
    end)
  end)
end)
