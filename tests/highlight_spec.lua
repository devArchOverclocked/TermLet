-- Tests for TermLet highlight module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.highlight", function()
  local highlight

  before_each(function()
    -- Clear cached modules to get fresh state
    package.loaded["termlet.highlight"] = nil
    highlight = require("termlet.highlight")
  end)

  after_each(function()
    -- Clean up any highlights
    if highlight then
      highlight.clear_all()
    end
  end)

  describe("setup", function()
    it("should initialize with default config", function()
      highlight.setup({})
      assert.is_true(highlight.is_enabled())
      local config = highlight.get_config()
      assert.equals("underline", config.style)
      assert.equals("TermLetStackTracePath", config.hl_group)
    end)

    it("should respect enabled config", function()
      highlight.setup({ enabled = false })
      assert.is_false(highlight.is_enabled())
    end)

    it("should accept custom style", function()
      highlight.setup({ style = "color" })
      local config = highlight.get_config()
      assert.equals("color", config.style)
    end)

    it("should accept custom highlight group", function()
      highlight.setup({ hl_group = "MyCustomGroup" })
      local config = highlight.get_config()
      assert.equals("MyCustomGroup", config.hl_group)
    end)

    it("should accept 'both' style", function()
      highlight.setup({ style = "both" })
      local config = highlight.get_config()
      assert.equals("both", config.style)
    end)

    it("should accept 'none' style", function()
      highlight.setup({ style = "none" })
      local config = highlight.get_config()
      assert.equals("none", config.style)
    end)

    it("should reject invalid style and fall back to 'underline'", function()
      highlight.setup({ style = "bold" })
      local config = highlight.get_config()
      assert.equals("underline", config.style)
    end)

    it("should reject non-string invalid style and fall back to 'underline'", function()
      highlight.setup({ style = 123 })
      local config = highlight.get_config()
      assert.equals("underline", config.style)
    end)
  end)

  describe("enable/disable", function()
    it("should enable highlighting", function()
      highlight.setup({ enabled = false })
      assert.is_false(highlight.is_enabled())

      highlight.enable()
      assert.is_true(highlight.is_enabled())
    end)

    it("should disable highlighting", function()
      highlight.setup({ enabled = true })
      assert.is_true(highlight.is_enabled())

      highlight.disable()
      assert.is_false(highlight.is_enabled())
    end)
  end)

  describe("namespace", function()
    it("should create and return namespace ID", function()
      local ns = highlight.get_namespace()
      assert.is_number(ns)
      assert.is_true(ns >= 0)
    end)

    it("should return same namespace ID on multiple calls", function()
      local ns1 = highlight.get_namespace()
      local ns2 = highlight.get_namespace()
      assert.equals(ns1, ns2)
    end)
  end)

  describe("highlight_file_path", function()
    local bufnr

    before_each(function()
      -- Create a test buffer
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "File \"/path/to/file.py\", line 42, in function",
        "Some other line",
      })
      highlight.setup({ enabled = true, style = "underline" })
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should apply extmark to specified range", function()
      highlight.highlight_file_path(bufnr, 1, 6, 21)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

      assert.equals(1, #extmarks)
      assert.equals(0, extmarks[1][2]) -- line (0-indexed)
      assert.equals(6, extmarks[1][3]) -- start_col
    end)

    it("should not apply extmark when disabled", function()
      highlight.disable()
      highlight.highlight_file_path(bufnr, 1, 6, 21)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

      assert.equals(0, #extmarks)
    end)

    it("should not apply extmark when style is 'none'", function()
      highlight.setup({ enabled = true, style = "none" })
      highlight.highlight_file_path(bufnr, 1, 6, 21)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

      assert.equals(0, #extmarks)
    end)

    it("should handle invalid buffer gracefully", function()
      -- Should not error
      highlight.highlight_file_path(9999, 1, 0, 10)
    end)
  end)

  describe("highlight_stacktrace_line", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      highlight.setup({ enabled = true, style = "underline" })
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should highlight Python stack trace line", function()
      local line_text = 'File "/home/user/test.py", line 42, in main'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line_text })

      local file_info = {
        path = "/home/user/test.py",
        original_path = "/home/user/test.py",
        line = 42,
      }

      local result = highlight.highlight_stacktrace_line(bufnr, 1, line_text, file_info)
      assert.is_true(result)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.equals(1, #extmarks)
    end)

    it("should highlight with original_path not resolved path", function()
      local line_text = 'File "src/test.py", line 42, in main'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line_text })

      local file_info = {
        path = "/absolute/path/src/test.py", -- resolved
        original_path = "src/test.py", -- what appears in output
        line = 42,
      }

      local result = highlight.highlight_stacktrace_line(bufnr, 1, line_text, file_info)
      assert.is_true(result)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.equals(1, #extmarks)
    end)

    it("should return false when path not found in line", function()
      local line_text = "Some random log message"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line_text })

      local file_info = {
        path = "/home/user/test.py",
        original_path = "/home/user/test.py",
        line = 42,
      }

      local result = highlight.highlight_stacktrace_line(bufnr, 1, line_text, file_info)
      assert.is_false(result)
    end)

    it("should return false when disabled", function()
      highlight.disable()

      local line_text = 'File "/home/user/test.py", line 42, in main'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line_text })

      local file_info = {
        path = "/home/user/test.py",
        original_path = "/home/user/test.py",
        line = 42,
      }

      local result = highlight.highlight_stacktrace_line(bufnr, 1, line_text, file_info)
      assert.is_false(result)
    end)

    it("should return false when file_info is nil", function()
      local line_text = 'File "/home/user/test.py", line 42, in main'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line_text })

      local result = highlight.highlight_stacktrace_line(bufnr, 1, line_text, nil)
      assert.is_false(result)
    end)

    it("should return false when file_info has no original_path", function()
      local line_text = 'File "/home/user/test.py", line 42, in main'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line_text })

      local file_info = {
        path = "/home/user/test.py",
        line = 42,
      }

      local result = highlight.highlight_stacktrace_line(bufnr, 1, line_text, file_info)
      assert.is_false(result)
    end)
  end)

  describe("clear_buffer", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'File "/home/user/test.py", line 42, in main',
      })
      highlight.setup({ enabled = true })
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should clear all extmarks from buffer", function()
      -- Add some highlights
      highlight.highlight_file_path(bufnr, 1, 6, 21)

      local ns = highlight.get_namespace()
      local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.equals(1, #extmarks_before)

      -- Clear
      highlight.clear_buffer(bufnr)

      local extmarks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.equals(0, #extmarks_after)
    end)

    it("should handle invalid buffer gracefully", function()
      -- Should not error
      highlight.clear_buffer(9999)
    end)
  end)

  describe("clear_all", function()
    local bufnr1, bufnr2

    before_each(function()
      bufnr1 = vim.api.nvim_create_buf(false, true)
      bufnr2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr1, 0, -1, false, { "line 1" })
      vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, { "line 2" })
      highlight.setup({ enabled = true })
    end)

    after_each(function()
      if bufnr1 and vim.api.nvim_buf_is_valid(bufnr1) then
        vim.api.nvim_buf_delete(bufnr1, { force = true })
      end
      if bufnr2 and vim.api.nvim_buf_is_valid(bufnr2) then
        vim.api.nvim_buf_delete(bufnr2, { force = true })
      end
    end)

    it("should clear extmarks from all buffers", function()
      -- Add highlights to both buffers
      highlight.highlight_file_path(bufnr1, 1, 0, 5)
      highlight.highlight_file_path(bufnr2, 1, 0, 5)

      local ns = highlight.get_namespace()
      local extmarks1_before = vim.api.nvim_buf_get_extmarks(bufnr1, ns, 0, -1, {})
      local extmarks2_before = vim.api.nvim_buf_get_extmarks(bufnr2, ns, 0, -1, {})
      assert.equals(1, #extmarks1_before)
      assert.equals(1, #extmarks2_before)

      -- Clear all
      highlight.clear_all()

      local extmarks1_after = vim.api.nvim_buf_get_extmarks(bufnr1, ns, 0, -1, {})
      local extmarks2_after = vim.api.nvim_buf_get_extmarks(bufnr2, ns, 0, -1, {})
      assert.equals(0, #extmarks1_after)
      assert.equals(0, #extmarks2_after)
    end)
  end)

  describe("integration with stacktrace", function()
    local stacktrace
    local bufnr

    before_each(function()
      package.loaded["termlet.stacktrace"] = nil
      package.loaded["termlet.highlight"] = nil
      stacktrace = require("termlet.stacktrace")
      highlight = require("termlet.highlight")

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "Traceback (most recent call last):",
        '  File "/home/user/test.py", line 42, in main',
        "    result = process(data)",
        "TypeError: something went wrong",
      })

      stacktrace.setup({})
      highlight.setup({ enabled = true, style = "underline" })
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      stacktrace.clear_buffer()
      stacktrace.clear_all_metadata()
      highlight.clear_all()
    end)

    it("should highlight detected stack traces in buffer", function()
      stacktrace.scan_buffer_for_stacktraces(bufnr, "/home/user")

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

      -- Should have one extmark for the file path
      assert.equals(1, #extmarks)
      -- Extmark should be on line 2 (0-indexed line 1)
      assert.equals(1, extmarks[1][2])
    end)

    it("should not highlight when highlighting is disabled", function()
      highlight.disable()
      stacktrace.scan_buffer_for_stacktraces(bufnr, "/home/user")

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

      assert.equals(0, #extmarks)
    end)
  end)

  describe("highlight styles", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'File "/home/user/test.py", line 42, in main',
      })
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should apply underline style", function()
      highlight.setup({ enabled = true, style = "underline" })
      highlight.highlight_file_path(bufnr, 1, 6, 21)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

      assert.equals(1, #extmarks)
      local details = extmarks[1][4]
      -- Underline is applied via highlight group for "underline" style
      assert.is_truthy(details.hl_group)
      assert.is_truthy(details.hl_group:match("Underline"))
    end)

    it("should apply color style without underline", function()
      highlight.setup({ enabled = true, style = "color" })
      highlight.highlight_file_path(bufnr, 1, 6, 21)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

      assert.equals(1, #extmarks)
      local details = extmarks[1][4]
      -- Should have highlight group but no explicit underline in extmark
      assert.is_truthy(details.hl_group)
      assert.is_nil(details.underline)
    end)

    it("should apply both color and underline", function()
      highlight.setup({ enabled = true, style = "both" })
      highlight.highlight_file_path(bufnr, 1, 6, 21)

      local ns = highlight.get_namespace()
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

      assert.equals(1, #extmarks)
      local details = extmarks[1][4]
      -- Both color and underline are applied via highlight group for "both" style
      assert.is_truthy(details.hl_group)
      assert.is_truthy(details.hl_group:match("Both"))
    end)
  end)
end)
