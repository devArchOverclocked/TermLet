-- Simple integration test for Python hyperlink functionality
-- Run with: nvim --headless --noplugin -u tests/minimal_init.lua -l tests/test_hyperlinks.lua

local stacktrace = require('termlet.stacktrace')

-- Setup with hyperlinks enabled
stacktrace.setup({
  hyperlinks = {
    enabled = true,
    fallback_to_extmarks = true,
  }
})

print("Testing Python stack trace hyperlink functionality...")
print()

-- Test 1: Python pattern with double quotes
local test1 = '  File "/home/user/test.py", line 10, in main'
local result1 = stacktrace.process_line(test1, "/home/user")
if result1 and result1.language == "python" and result1.line == 10 then
  print("✓ Test 1 PASSED: Python double quotes pattern")
else
  print("✗ Test 1 FAILED: Python double quotes pattern")
  os.exit(1)
end

-- Test 2: Python pattern with single quotes
local test2 = "  File '/home/user/test.py', line 10, in main"
local result2 = stacktrace.process_line(test2, "/home/user")
if result2 and result2.language == "python" and result2.line == 10 then
  print("✓ Test 2 PASSED: Python single quotes pattern")
else
  print("✗ Test 2 FAILED: Python single quotes pattern")
  os.exit(1)
end

-- Test 3: File URL creation
local url = stacktrace.create_file_url("/home/user/test.py", 10, 5)
if url == "file:///home/user/test.py:10:5" then
  print("✓ Test 3 PASSED: File URL creation")
else
  print("✗ Test 3 FAILED: File URL creation - got: " .. url)
  os.exit(1)
end

-- Test 4: OSC 8 hyperlink creation
local hyperlink = stacktrace.create_hyperlink("file:///test.py", "test.py")
if hyperlink:find("\27]8;;file:///test.py\27\\") and hyperlink:find("test.py") then
  print("✓ Test 4 PASSED: OSC 8 hyperlink creation")
else
  print("✗ Test 4 FAILED: OSC 8 hyperlink creation")
  os.exit(1)
end

-- Test 5: Extmark application
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'File "/home/user/test.py", line 10, in main',
})

local file_info = {
  path = "/home/user/test.py",
  line = 10,
  buffer_line = 1,
  language = "python",
  raw_line = 'File "/home/user/test.py", line 10, in main',
}

stacktrace.apply_hyperlink(buf, file_info)

local ns_id = vim.api.nvim_create_namespace("termlet_stacktrace_hyperlinks")
local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})

if #extmarks > 0 then
  print("✓ Test 5 PASSED: Extmark application")
else
  print("✗ Test 5 FAILED: Extmark application")
  vim.api.nvim_buf_delete(buf, { force = true })
  os.exit(1)
end

vim.api.nvim_buf_delete(buf, { force = true })

-- Test 6: Real Python traceback
local real_traceback = [[
Traceback (most recent call last):
  File "/home/mengsig/Projects/vibegit/workspaces/termlet/tests/test_python_error.py", line 61, in <module>
    outer_function()
  File "/home/mengsig/Projects/vibegit/workspaces/termlet/tests/test_python_error.py", line 23, in outer_function
    result = middle_function(None)
  File "/home/mengsig/Projects/vibegit/workspaces/termlet/tests/test_python_error.py", line 17, in middle_function
    inner_function()
  File "/home/mengsig/Projects/vibegit/workspaces/termlet/tests/test_python_error.py", line 11, in inner_function
    raise ValueError("Test error from inner function")
ValueError: Test error from inner function
]]

local lines = {}
for line in real_traceback:gmatch("[^\r\n]+") do
  table.insert(lines, line)
end

local results = stacktrace.process_output(lines, "/home/mengsig/Projects/vibegit/workspaces/termlet/tests")

-- Should find 4 file references in the traceback
if #results == 4 then
  print("✓ Test 6 PASSED: Real Python traceback parsing (found " .. #results .. " references)")
else
  print("✗ Test 6 FAILED: Real Python traceback parsing (expected 4, found " .. #results .. ")")
  os.exit(1)
end

print()
print("All tests passed! ✓")
print()
print("Summary:")
print("  - Python pattern matching (double and single quotes)")
print("  - File URL creation")
print("  - OSC 8 hyperlink generation")
print("  - Extmark-based clickability")
print("  - Real-world Python traceback parsing")
