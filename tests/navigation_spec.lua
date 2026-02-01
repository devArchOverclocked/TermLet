-- Tests for TermLet navigation module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.navigation", function()
  local navigation
  local stacktrace
  local termlet

  before_each(function()
    -- Clear cached modules to get fresh state
    package.loaded["termlet.navigation"] = nil
    package.loaded["termlet.stacktrace"] = nil
    package.loaded["termlet"] = nil

    navigation = require("termlet.navigation")
    stacktrace = require("termlet.stacktrace")
    termlet = require("termlet")

    stacktrace.clear_buffer()
    stacktrace.clear_all_metadata()
    stacktrace.clear_parsers()
  end)

  describe("setup", function()
    it("should initialize with default config", function()
      navigation.setup({})
      assert.is_true(navigation.is_enabled())
      local config = navigation.get_config()
      assert.are.equal(']e', config.keymaps.next_error)
      assert.are.equal('[e', config.keymaps.prev_error)
      assert.are.equal('split', config.open_command)
      assert.is_true(config.wrap_navigation)
    end)

    it("should merge user config with defaults", function()
      navigation.setup({
        keymaps = {
          next_error = ']d',
          prev_error = '[d',
        },
        open_command = 'vsplit',
        wrap_navigation = false,
      })

      local config = navigation.get_config()
      assert.are.equal(']d', config.keymaps.next_error)
      assert.are.equal('[d', config.keymaps.prev_error)
      assert.are.equal('vsplit', config.open_command)
      assert.is_false(config.wrap_navigation)
    end)

    it("should respect enabled config", function()
      navigation.setup({ enabled = false })
      assert.is_false(navigation.is_enabled())
    end)
  end)

  describe("enable/disable", function()
    it("should enable navigation", function()
      navigation.setup({ enabled = false })
      assert.is_false(navigation.is_enabled())

      navigation.enable()
      assert.is_true(navigation.is_enabled())
    end)

    it("should disable navigation", function()
      navigation.setup({ enabled = true })
      assert.is_true(navigation.is_enabled())

      navigation.disable()
      assert.is_false(navigation.is_enabled())
    end)
  end)

  describe("jump_to_next", function()
    it("should notify when no locations found", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      -- Mock vim.notify
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        notify_called = true
        assert.is_truthy(msg:match("No stack trace locations"))
      end

      navigation.jump_to_next(buf)
      assert.is_true(notify_called)

      vim.notify = original_notify
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should jump to next location", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      -- Add content to buffer (20 lines)
      local lines = {}
      for i = 1, 20 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      -- Create a window for the buffer
      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = 80,
        height = 20,
        row = 0,
        col = 0,
      })

      -- Setup stacktrace module
      stacktrace.setup({})
      navigation.setup({})

      -- Add mock metadata
      stacktrace.store_metadata(buf, 5, {
        path = '/test/file1.py',
        line = 10,
        column = 5,
      })
      stacktrace.store_metadata(buf, 10, {
        path = '/test/file2.py',
        line = 20,
        column = 10,
      })
      stacktrace.store_metadata(buf, 15, {
        path = '/test/file3.py',
        line = 30,
        column = 15,
      })

      -- Set cursor to line 1
      vim.api.nvim_win_set_cursor(win, {1, 0})

      -- Jump to next
      navigation.jump_to_next(buf)

      -- Should move to line 5
      local cursor = vim.api.nvim_win_get_cursor(win)
      assert.are.equal(5, cursor[1])

      -- Jump to next again
      navigation.jump_to_next(buf)

      -- Should move to line 10
      cursor = vim.api.nvim_win_get_cursor(win)
      assert.are.equal(10, cursor[1])

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should wrap around when wrap_navigation is true", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      -- Add content to buffer
      local lines = {}
      for i = 1, 20 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = 80,
        height = 20,
        row = 0,
        col = 0,
      })

      stacktrace.setup({})
      navigation.setup({ wrap_navigation = true })

      stacktrace.store_metadata(buf, 5, {
        path = '/test/file1.py',
        line = 10,
      })
      stacktrace.store_metadata(buf, 10, {
        path = '/test/file2.py',
        line = 20,
      })

      -- Set cursor to line 15 (after all locations)
      vim.api.nvim_win_set_cursor(win, {15, 0})

      -- Jump to next should wrap to first location
      navigation.jump_to_next(buf)

      local cursor = vim.api.nvim_win_get_cursor(win)
      assert.are.equal(5, cursor[1])

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should not wrap when wrap_navigation is false", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      -- Add content to buffer
      local lines = {}
      for i = 1, 20 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = 80,
        height = 20,
        row = 0,
        col = 0,
      })

      stacktrace.setup({})
      navigation.setup({ wrap_navigation = false })

      stacktrace.store_metadata(buf, 5, {
        path = '/test/file1.py',
        line = 10,
      })

      -- Set cursor to line 10 (after all locations)
      vim.api.nvim_win_set_cursor(win, {10, 0})

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        notify_called = true
        assert.is_truthy(msg:match("No more stack trace locations"))
      end

      navigation.jump_to_next(buf)

      assert.is_true(notify_called)

      vim.notify = original_notify
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("jump_to_prev", function()
    it("should jump to previous location", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      -- Add content to buffer
      local lines = {}
      for i = 1, 20 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = 80,
        height = 20,
        row = 0,
        col = 0,
      })

      stacktrace.setup({})
      navigation.setup({})

      stacktrace.store_metadata(buf, 5, {
        path = '/test/file1.py',
        line = 10,
      })
      stacktrace.store_metadata(buf, 10, {
        path = '/test/file2.py',
        line = 20,
      })
      stacktrace.store_metadata(buf, 15, {
        path = '/test/file3.py',
        line = 30,
      })

      -- Set cursor to line 20
      vim.api.nvim_win_set_cursor(win, {20, 0})

      -- Jump to previous
      navigation.jump_to_prev(buf)

      -- Should move to line 15
      local cursor = vim.api.nvim_win_get_cursor(win)
      assert.are.equal(15, cursor[1])

      -- Jump to previous again
      navigation.jump_to_prev(buf)

      -- Should move to line 10
      cursor = vim.api.nvim_win_get_cursor(win)
      assert.are.equal(10, cursor[1])

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should wrap around when wrap_navigation is true", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      -- Add content to buffer
      local lines = {}
      for i = 1, 20 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = 80,
        height = 20,
        row = 0,
        col = 0,
      })

      stacktrace.setup({})
      navigation.setup({ wrap_navigation = true })

      stacktrace.store_metadata(buf, 5, {
        path = '/test/file1.py',
        line = 10,
      })
      stacktrace.store_metadata(buf, 10, {
        path = '/test/file2.py',
        line = 20,
      })

      -- Set cursor to line 1 (before all locations)
      vim.api.nvim_win_set_cursor(win, {1, 0})

      -- Jump to previous should wrap to last location
      navigation.jump_to_prev(buf)

      local cursor = vim.api.nvim_win_get_cursor(win)
      assert.are.equal(10, cursor[1])

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("list_all_locations", function()
    it("should notify when no locations found", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        notify_called = true
        assert.is_truthy(msg:match("No stack trace locations"))
      end

      navigation.list_all_locations(buf)
      assert.is_true(notify_called)

      vim.notify = original_notify
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should populate location list with stack trace entries", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      -- Add content to buffer
      local lines = {}
      for i = 1, 20 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = 80,
        height = 20,
        row = 0,
        col = 0,
      })

      stacktrace.setup({})
      navigation.setup({})

      stacktrace.store_metadata(buf, 5, {
        path = '/test/file1.py',
        line = 10,
        column = 5,
        context = 'test_function',
      })
      stacktrace.store_metadata(buf, 10, {
        path = '/test/file2.py',
        line = 20,
        column = 10,
        context = 'another_function',
      })

      navigation.list_all_locations(buf, true)

      -- Check location list was populated
      local loclist = vim.fn.getloclist(0)
      assert.are.equal(2, #loclist)
      -- Check the first entry
      local first = loclist[1]
      -- getloclist returns bufnr, not filename directly
      local first_name = first.bufnr ~= 0 and vim.api.nvim_buf_get_name(first.bufnr) or first.filename or ''
      assert.is_truthy(first_name:match('file1%.py$'))
      assert.are.equal(10, first.lnum)
      assert.are.equal(5, first.col)

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("setup_buffer_keymaps", function()
    it("should setup keymaps when enabled", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      navigation.setup({ enabled = true })
      navigation.setup_buffer_keymaps(buf)

      -- Check that keymaps were created
      local keymaps = vim.api.nvim_buf_get_keymap(buf, 'n')

      local has_next = false
      local has_prev = false
      local has_open = false

      for _, keymap in ipairs(keymaps) do
        if keymap.lhs == ']e' then
          has_next = true
        elseif keymap.lhs == '[e' then
          has_prev = true
        elseif keymap.lhs == 'gf' or keymap.lhs == '<CR>' then
          has_open = true
        end
      end

      assert.is_true(has_next)
      assert.is_true(has_prev)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should not setup keymaps when disabled", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      navigation.setup({ enabled = false })

      -- Count keymaps before
      local keymaps_before = vim.api.nvim_buf_get_keymap(buf, 'n')
      local count_before = #keymaps_before

      navigation.setup_buffer_keymaps(buf)

      -- Count keymaps after
      local keymaps_after = vim.api.nvim_buf_get_keymap(buf, 'n')
      local count_after = #keymaps_after

      -- Should be the same (no new keymaps added)
      assert.are.equal(count_before, count_after)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should support custom keymaps", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)

      navigation.setup({
        enabled = true,
        keymaps = {
          next_error = ']d',
          prev_error = '[d',
          open_file = '<leader>o',
          list_errors = '<leader>l',
        },
      })

      navigation.setup_buffer_keymaps(buf)

      local keymaps = vim.api.nvim_buf_get_keymap(buf, 'n')

      local has_next = false
      local has_prev = false

      for _, keymap in ipairs(keymaps) do
        if keymap.lhs == ']d' then
          has_next = true
        elseif keymap.lhs == '[d' then
          has_prev = true
        end
      end

      assert.is_true(has_next)
      assert.is_true(has_prev)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
