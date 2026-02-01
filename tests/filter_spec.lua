-- Tests for TermLet filter module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.filter", function()
  local filter

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.filter"] = nil
    filter = require("termlet.filter")
  end)

  after_each(function()
    -- Clean up
    filter.clear_all()
  end)

  describe("setup", function()
    it("should initialize with default config", function()
      filter.setup({})
      assert.is_not_nil(filter)
    end)

    it("should default to enabled=false", function()
      filter.setup({})
      local config = filter.get_config()
      assert.is_false(config.enabled)
    end)

    it("should accept custom config", function()
      filter.setup({
        enabled = false,
        show_only = { "error" },
        hide = { "debug" },
        highlight = {
          { pattern = "error", color = "#ff0000" },
        },
      })
      local config = filter.get_config()
      assert.is_false(config.enabled)
      assert.are.equal(1, #config.show_only)
      assert.are.equal(1, #config.hide)
      assert.are.equal(1, #config.highlight)
    end)
  end)

  describe("process_line", function()
    it("should show all lines when filters are disabled", function()
      filter.setup({ enabled = false })
      local filters = { enabled = false }

      local show, highlights = filter.process_line("error: something went wrong", filters)
      assert.is_true(show)
      assert.are.equal(0, #highlights)
    end)

    it("should filter lines with show_only", function()
      local filters = {
        enabled = true,
        show_only = { "error", "warning" },
        hide = {},
        highlight = {},
      }

      local show1, _ = filter.process_line("error: test", filters)
      local show2, _ = filter.process_line("warning: test", filters)
      local show3, _ = filter.process_line("info: test", filters)

      assert.is_true(show1)
      assert.is_true(show2)
      assert.is_false(show3)
    end)

    it("should filter lines with hide", function()
      local filters = {
        enabled = true,
        show_only = {},
        hide = { "debug", "verbose" },
        highlight = {},
      }

      local show1, _ = filter.process_line("error: test", filters)
      local show2, _ = filter.process_line("debug: test", filters)
      local show3, _ = filter.process_line("verbose output", filters)

      assert.is_true(show1)
      assert.is_false(show2)
      assert.is_false(show3)
    end)

    it("should combine show_only and hide filters", function()
      local filters = {
        enabled = true,
        show_only = { "error" },
        hide = { "ignored" },
        highlight = {},
      }

      local show1, _ = filter.process_line("error: test", filters)
      local show2, _ = filter.process_line("error: ignored", filters)
      local show3, _ = filter.process_line("warning: test", filters)

      assert.is_true(show1)
      assert.is_false(show2) -- matches show_only but also matches hide
      assert.is_false(show3) -- doesn't match show_only
    end)

    it("should find highlight matches", function()
      local filters = {
        enabled = true,
        show_only = {},
        hide = {},
        highlight = {
          { pattern = "error", color = "#ff0000" },
          { pattern = "warning", color = "#ffaa00" },
        },
      }

      local show, highlights = filter.process_line("error: test warning", filters)
      assert.is_true(show)
      assert.are.equal(2, #highlights)
      assert.is_truthy(highlights[1].start)
      assert.is_truthy(highlights[1]["end"])
      assert.are.equal("#ff0000", highlights[1].color)
    end)

    it("should handle case-insensitive matching", function()
      local filters = {
        enabled = true,
        show_only = { "ERROR" },
        hide = {},
        highlight = {},
      }

      local show1, _ = filter.process_line("error: test", filters)
      local show2, _ = filter.process_line("ERROR: test", filters)
      local show3, _ = filter.process_line("Error: test", filters)

      assert.is_true(show1)
      assert.is_true(show2)
      assert.is_true(show3)
    end)

    it("should handle multiple occurrences of the same pattern", function()
      local filters = {
        enabled = true,
        show_only = {},
        hide = {},
        highlight = {
          { pattern = "error", color = "#ff0000" },
        },
      }

      local show, highlights = filter.process_line("error: another error occurred", filters)
      assert.is_true(show)
      assert.are.equal(2, #highlights)
    end)

    it("should handle empty line", function()
      local filters = {
        enabled = true,
        show_only = {},
        hide = {},
        highlight = {},
      }

      local show, highlights = filter.process_line("", filters)
      assert.is_true(show)
      assert.are.equal(0, #highlights)
    end)
  end)

  describe("apply_filters", function()
    it("should return 0 for invalid buffer", function()
      local filters = { enabled = true, show_only = {}, hide = {}, highlight = {} }
      local count = filter.apply_filters(9999, filters)
      assert.are.equal(0, count)
    end)

    it("should return 0 when filters are disabled", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2", "line 3" })

      local filters = { enabled = false, show_only = {}, hide = {}, highlight = {} }
      local count = filter.apply_filters(buf, filters)

      assert.are.equal(0, count)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should filter lines from buffer while caching originals", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "error: something",
        "info: ignored",
        "error: another",
        "debug: ignored",
      })

      local filters = {
        enabled = true,
        show_only = { "error" },
        hide = {},
        highlight = {},
      }

      local count = filter.apply_filters(buf, filters)
      assert.are.equal(2, count) -- 2 lines hidden

      -- Buffer should show only filtered lines
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(2, #lines)
      assert.is_truthy(lines[1]:find("error"))
      assert.is_truthy(lines[2]:find("error"))

      -- Original lines should be cached
      assert.is_true(filter.has_original_lines(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should restore original lines when cleared", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local original = {
        "error: something",
        "info: ignored",
        "error: another",
        "debug: ignored",
      }
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)

      local filters = {
        enabled = true,
        show_only = { "error" },
        hide = {},
        highlight = {},
      }

      filter.apply_filters(buf, filters)

      -- Verify lines were filtered
      local filtered_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(2, #filtered_lines)

      -- Clear buffer (restores original)
      filter.clear_buffer(buf)

      -- Verify original lines are restored
      local restored_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(4, #restored_lines)
      assert.are.equal("error: something", restored_lines[1])
      assert.are.equal("info: ignored", restored_lines[2])
      assert.are.equal("error: another", restored_lines[3])
      assert.are.equal("debug: ignored", restored_lines[4])

      -- Cache should be cleared after restore
      assert.is_false(filter.has_original_lines(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should reapply filters from cached originals", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "error: something",
        "info: message",
        "warning: test",
        "debug: ignored",
      })

      -- Apply first filter (show only errors)
      local filters1 = {
        enabled = true,
        show_only = { "error" },
        hide = {},
        highlight = {},
      }
      filter.apply_filters(buf, filters1)
      local lines1 = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(1, #lines1)

      -- Reapply with different filter (show warnings) — should use cached originals
      local filters2 = {
        enabled = true,
        show_only = { "warning" },
        hide = {},
        highlight = {},
      }
      filter.apply_filters(buf, filters2)
      local lines2 = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(1, #lines2)
      assert.is_truthy(lines2[1]:find("warning"))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should apply highlights without filtering", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "error: something",
        "warning: test",
      })

      local filters = {
        enabled = true,
        show_only = {},
        hide = {},
        highlight = {
          { pattern = "error", color = "#ff0000" },
          { pattern = "warning", color = "#ffaa00" },
        },
      }

      local count = filter.apply_filters(buf, filters)
      assert.are.equal(0, count) -- no lines hidden

      -- Verify highlights were applied (check that extmarks exist)
      local ns_id = filter.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
      assert.is_true(#extmarks > 0)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should handle empty buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local filters = {
        enabled = true,
        show_only = { "error" },
        hide = {},
        highlight = {},
      }

      local count = filter.apply_filters(buf, filters)
      -- A new buffer has one empty line by default, which will be filtered
      assert.are.equal(1, count)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("clear_buffer", function()
    it("should clear highlights and restore original lines", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "error: test", "info: test" })

      local filters = {
        enabled = true,
        show_only = { "error" },
        hide = {},
        highlight = {
          { pattern = "error", color = "#ff0000" },
        },
      }

      filter.apply_filters(buf, filters)

      -- Verify only 1 line visible
      local filtered = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(1, #filtered)

      -- Clear buffer
      filter.clear_buffer(buf)

      -- Verify highlights are gone
      local ns_id = filter.get_namespace()
      local extmarks_after = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
      assert.are.equal(0, #extmarks_after)

      -- Verify all original lines restored
      local restored = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(2, #restored)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should handle invalid buffer gracefully", function()
      -- Should not error
      filter.clear_buffer(9999)
    end)
  end)

  describe("toggle_enabled", function()
    it("should toggle filter enabled state", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local filters = {
        enabled = true,
        show_only = {},
        hide = {},
        highlight = {},
      }

      local new_state = filter.toggle_enabled(buf, filters)
      assert.is_false(new_state)
      assert.is_false(filters.enabled)

      new_state = filter.toggle_enabled(buf, filters)
      assert.is_true(new_state)
      assert.is_true(filters.enabled)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should restore original lines when toggling off", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "error: test",
        "info: message",
        "debug: hidden",
      })

      local filters = {
        enabled = true,
        show_only = { "error" },
        hide = {},
        highlight = {},
      }

      -- Apply filters
      filter.apply_filters(buf, filters)
      local filtered = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(1, #filtered)

      -- Toggle off — should restore
      filter.toggle_enabled(buf, filters)
      local restored = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(3, #restored)
      assert.are.equal("error: test", restored[1])
      assert.are.equal("info: message", restored[2])
      assert.are.equal("debug: hidden", restored[3])

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should return false for nil filters", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local new_state = filter.toggle_enabled(buf, nil)
      assert.is_false(new_state)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("create_preset", function()
    it("should create errors preset", function()
      local preset = filter.create_preset("errors")
      assert.is_true(preset.enabled)
      assert.is_true(#preset.show_only > 0)
      assert.is_true(#preset.highlight > 0)
    end)

    it("should create warnings preset", function()
      local preset = filter.create_preset("warnings")
      assert.is_true(preset.enabled)
      assert.is_true(#preset.show_only > 0)
      assert.is_true(#preset.highlight > 0)
    end)

    it("should create info preset", function()
      local preset = filter.create_preset("info")
      assert.is_true(preset.enabled)
      assert.is_true(#preset.show_only > 0)
      assert.is_true(#preset.highlight > 0)
    end)

    it("should create all preset", function()
      local preset = filter.create_preset("all")
      assert.is_true(preset.enabled)
      assert.are.equal(0, #preset.show_only)
      assert.is_true(#preset.hide > 0)
      assert.is_true(#preset.highlight > 0)
    end)

    it("should default to all for unknown preset", function()
      local preset = filter.create_preset("unknown")
      assert.is_true(preset.enabled)
      assert.are.equal(0, #preset.show_only)
    end)
  end)

  describe("highlight_line", function()
    it("should highlight patterns in a line", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "error: test warning" })

      local rules = {
        { pattern = "error", color = "#ff0000" },
        { pattern = "warning", color = "#ffaa00" },
      }

      filter.highlight_line(buf, 1, "error: test warning", rules)

      local ns_id = filter.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
      assert.are.equal(2, #extmarks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should handle invalid buffer gracefully", function()
      -- Should not error
      filter.highlight_line(9999, 1, "test", {})
    end)

    it("should handle empty highlight rules", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })

      filter.highlight_line(buf, 1, "test", {})

      local ns_id = filter.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
      assert.are.equal(0, #extmarks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("get_namespace", function()
    it("should return a valid namespace ID", function()
      local ns_id = filter.get_namespace()
      assert.is_number(ns_id)
      assert.is_true(ns_id >= 0)
    end)

    it("should return the same namespace ID on multiple calls", function()
      local ns1 = filter.get_namespace()
      local ns2 = filter.get_namespace()
      assert.are.equal(ns1, ns2)
    end)
  end)

  describe("has_original_lines", function()
    it("should return false when no cache exists", function()
      local buf = vim.api.nvim_create_buf(false, true)
      assert.is_false(filter.has_original_lines(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should return true after applying filters", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "error: test", "info: test" })

      local filters = {
        enabled = true,
        show_only = { "error" },
        hide = {},
        highlight = {},
      }

      filter.apply_filters(buf, filters)
      assert.is_true(filter.has_original_lines(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("restore_buffer", function()
    it("should return false when no cache exists", function()
      local buf = vim.api.nvim_create_buf(false, true)
      assert.is_false(filter.restore_buffer(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should restore original content and clear cache", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2", "line 3" })

      local filters = {
        enabled = true,
        show_only = { "line 1" },
        hide = {},
        highlight = {},
      }

      filter.apply_filters(buf, filters)
      assert.are.equal(1, #vim.api.nvim_buf_get_lines(buf, 0, -1, false))

      local restored = filter.restore_buffer(buf)
      assert.is_true(restored)
      assert.are.equal(3, #vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.is_false(filter.has_original_lines(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
