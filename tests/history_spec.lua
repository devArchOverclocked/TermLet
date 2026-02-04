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

  describe("get_last_failed_entry", function()
    it("should return nil when history is empty", function()
      local entry = history.get_last_failed_entry()
      assert.is_nil(entry)
    end)

    it("should return nil when all entries succeeded", function()
      history.add_entry({ script_name = "build", exit_code = 0, output_lines = { "ok" } })
      history.add_entry({ script_name = "test", exit_code = 0, output_lines = { "passed" } })

      local entry = history.get_last_failed_entry()
      assert.is_nil(entry)
    end)

    it("should return the most recent failed entry with output", function()
      history.add_entry({
        script_name = "first_fail",
        exit_code = 1,
        output_lines = { "error: first" },
      })
      history.add_entry({
        script_name = "success",
        exit_code = 0,
        output_lines = { "ok" },
      })
      history.add_entry({
        script_name = "second_fail",
        exit_code = 2,
        output_lines = { "error: second" },
      })

      local entry = history.get_last_failed_entry()
      assert.is_not_nil(entry)
      assert.are.equal("second_fail", entry.script_name)
      assert.are.equal(2, entry.exit_code)
    end)

    it("should skip failed entries without output_lines", function()
      history.add_entry({
        script_name = "no_output_fail",
        exit_code = 1,
      })
      history.add_entry({
        script_name = "with_output_fail",
        exit_code = 1,
        output_lines = { "traceback line 1", "traceback line 2" },
      })

      -- The entry with output should come first (most recent)
      local entry = history.get_last_failed_entry()
      assert.is_not_nil(entry)
      assert.are.equal("with_output_fail", entry.script_name)
    end)

    it("should skip failed entries with empty output_lines", function()
      history.add_entry({
        script_name = "empty_output",
        exit_code = 1,
        output_lines = {},
      })

      local entry = history.get_last_failed_entry()
      assert.is_nil(entry)
    end)
  end)

  describe("show_stacktrace", function()
    it("should return false when entry is nil", function()
      local result = history.show_stacktrace(nil)
      assert.is_false(result)
    end)

    it("should return false when entry has no output_lines", function()
      local result = history.show_stacktrace({
        script_name = "test",
        exit_code = 1,
      })
      assert.is_false(result)
    end)

    it("should return false when entry has empty output_lines", function()
      local result = history.show_stacktrace({
        script_name = "test",
        exit_code = 1,
        output_lines = {},
      })
      assert.is_false(result)
    end)

    it("should return false when entry succeeded (exit_code 0)", function()
      local result = history.show_stacktrace({
        script_name = "test",
        exit_code = 0,
        output_lines = { "some output" },
      })
      assert.is_false(result)
    end)

    it("should open stacktrace window for failed entry with output", function()
      local result = history.show_stacktrace({
        script_name = "failing_script",
        exit_code = 1,
        output_lines = {
          "Traceback (most recent call last):",
          '  File "test.py", line 10, in main',
          "    raise ValueError('bad value')",
          "ValueError: bad value",
        },
      })
      assert.is_true(result)
      assert.is_true(history.is_stacktrace_open())

      -- Clean up
      history.close_stacktrace()
    end)

    it("should close existing stacktrace window when opening new one", function()
      history.show_stacktrace({
        script_name = "first",
        exit_code = 1,
        output_lines = { "error 1" },
      })
      assert.is_true(history.is_stacktrace_open())

      history.show_stacktrace({
        script_name = "second",
        exit_code = 2,
        output_lines = { "error 2" },
      })
      assert.is_true(history.is_stacktrace_open())

      -- Clean up
      history.close_stacktrace()
    end)
  end)

  describe("close_stacktrace", function()
    it("should close open stacktrace window", function()
      history.show_stacktrace({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      assert.is_true(history.is_stacktrace_open())

      history.close_stacktrace()
      assert.is_false(history.is_stacktrace_open())
    end)

    it("should not error when no stacktrace is open", function()
      history.close_stacktrace()
      assert.is_false(history.is_stacktrace_open())
    end)
  end)

  describe("is_stacktrace_open", function()
    it("should return false initially", function()
      assert.is_false(history.is_stacktrace_open())
    end)

    it("should return true when stacktrace is open", function()
      history.show_stacktrace({
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      })
      assert.is_true(history.is_stacktrace_open())

      history.close_stacktrace()
    end)
  end)

  describe("toggle_stacktrace", function()
    it("should open stacktrace when closed", function()
      local entry = {
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      }
      local result = history.toggle_stacktrace(entry)
      assert.is_true(result)
      assert.is_true(history.is_stacktrace_open())

      history.close_stacktrace()
    end)

    it("should close stacktrace when open", function()
      local entry = {
        script_name = "test",
        exit_code = 1,
        output_lines = { "error" },
      }
      history.show_stacktrace(entry)
      assert.is_true(history.is_stacktrace_open())

      local result = history.toggle_stacktrace(entry)
      assert.is_false(result)
      assert.is_false(history.is_stacktrace_open())
    end)
  end)

  describe("output_lines in history entries", function()
    it("should store output_lines in entry", function()
      local output = { "line 1", "line 2", "error: something failed" }
      history.add_entry({
        script_name = "test",
        exit_code = 1,
        output_lines = output,
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.is_not_nil(entries[1].output_lines)
      assert.are.equal(3, #entries[1].output_lines)
      assert.are.equal("line 1", entries[1].output_lines[1])
    end)

    it("should handle entries without output_lines", function()
      history.add_entry({
        script_name = "test",
        exit_code = 0,
      })

      local entries = history.get_entries()
      assert.are.equal(1, #entries)
      assert.is_nil(entries[1].output_lines)
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

  describe("show_last_stacktrace", function()
    it("should return false when no failed executions", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.show_last_stacktrace()
      assert.is_false(result)
    end)

    it("should return false when no history at all", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.show_last_stacktrace()
      assert.is_false(result)
    end)
  end)

  describe("toggle_last_stacktrace", function()
    it("should return false when no failed executions", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local result = termlet.toggle_last_stacktrace()
      assert.is_false(result)
    end)
  end)

  describe("is_stacktrace_open", function()
    it("should return false initially", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      assert.is_false(termlet.is_stacktrace_open())
    end)
  end)

  describe("close_stacktrace", function()
    it("should not error when no stacktrace is open", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      termlet.close_stacktrace()
      assert.is_false(termlet.is_stacktrace_open())
    end)
  end)

  describe("stacktrace from history integration", function()
    it("should show stacktrace for failed entry added to history", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      -- Add a failed entry with output
      local history_module = require("termlet.history")
      history_module.add_entry({
        script_name = "failing_build",
        exit_code = 1,
        output_lines = {
          "Compiling...",
          "error: undefined reference",
          "  at main.c:42",
        },
      })

      local result = termlet.show_last_stacktrace()
      assert.is_true(result)
      assert.is_true(termlet.is_stacktrace_open())

      -- Toggle should close it
      local toggle_result = termlet.toggle_last_stacktrace()
      assert.is_false(toggle_result)
      assert.is_false(termlet.is_stacktrace_open())
    end)

    it("should skip successful entries when showing last stacktrace", function()
      termlet.setup({
        scripts = {},
        history = { enabled = true },
      })

      local history_module = require("termlet.history")
      -- Add a failed entry first, then a successful one
      history_module.add_entry({
        script_name = "failed_test",
        exit_code = 1,
        output_lines = { "FAIL: test_something" },
      })
      history_module.add_entry({
        script_name = "build_ok",
        exit_code = 0,
        output_lines = { "Build complete" },
      })

      -- Should show the failed entry, not the successful one
      local result = termlet.show_last_stacktrace()
      assert.is_true(result)
      assert.is_true(termlet.is_stacktrace_open())

      termlet.close_stacktrace()
    end)
  end)
end)
