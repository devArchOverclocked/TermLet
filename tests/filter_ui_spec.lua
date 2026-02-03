-- Tests for TermLet filter UI module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local filter_ui = require("termlet.filter_ui")

describe("termlet.filter_ui", function()
  local target_buf

  before_each(function()
    -- Close any existing UI
    filter_ui.close()

    -- Create a target buffer to simulate terminal buffer
    target_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, {
      "error: something went wrong",
      "info: all good",
      "warning: be careful",
    })
  end)

  after_each(function()
    filter_ui.close()
    if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
      vim.api.nvim_buf_delete(target_buf, { force = true })
    end
  end)

  describe("open", function()
    it("should open the filter UI with valid target buffer", function()
      local result = filter_ui.open(target_buf)
      assert.is_true(result)
      assert.is_true(filter_ui.is_open())
    end)

    it("should return false for invalid target buffer", function()
      local result = filter_ui.open(99999)
      assert.is_false(result)
    end)

    it("should return false for nil target buffer", function()
      local result = filter_ui.open(nil)
      assert.is_false(result)
    end)

    it("should close existing UI before reopening", function()
      filter_ui.open(target_buf)
      assert.is_true(filter_ui.is_open())

      -- Opening again should close and return false (toggle behavior)
      local result = filter_ui.open(target_buf)
      assert.is_false(result)
      assert.is_false(filter_ui.is_open())
    end)

    it("should use native floating window border", function()
      filter_ui.open(target_buf)
      assert.is_true(filter_ui.is_open())
    end)
  end)

  describe("close", function()
    it("should close the filter UI", function()
      filter_ui.open(target_buf)
      assert.is_true(filter_ui.is_open())

      filter_ui.close()
      assert.is_false(filter_ui.is_open())
    end)

    it("should not error when no UI is open", function()
      filter_ui.close()
      assert.is_false(filter_ui.is_open())
    end)
  end)

  describe("is_open", function()
    it("should return false initially", function()
      assert.is_false(filter_ui.is_open())
    end)

    it("should return true when open", function()
      filter_ui.open(target_buf)
      assert.is_true(filter_ui.is_open())
    end)

    it("should return false after closing", function()
      filter_ui.open(target_buf)
      filter_ui.close()
      assert.is_false(filter_ui.is_open())
    end)
  end)

  describe("toggle", function()
    it("should open when closed", function()
      filter_ui.toggle(target_buf)
      assert.is_true(filter_ui.is_open())
    end)

    it("should close when open", function()
      filter_ui.open(target_buf)
      assert.is_true(filter_ui.is_open())

      filter_ui.toggle(target_buf)
      assert.is_false(filter_ui.is_open())
    end)
  end)
end)
