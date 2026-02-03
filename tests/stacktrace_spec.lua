-- Tests for TermLet stacktrace module and parser plugin architecture
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.stacktrace", function()
  local stacktrace

  before_each(function()
    -- Clear cached modules to get fresh state
    package.loaded["termlet.stacktrace"] = nil
    package.loaded["termlet.parsers.python"] = nil
    package.loaded["termlet.parsers.csharp"] = nil
    package.loaded["termlet.parsers.javascript"] = nil
    package.loaded["termlet.parsers.java"] = nil
    stacktrace = require("termlet.stacktrace")
    stacktrace.clear_buffer()
    stacktrace.clear_all_metadata()
    stacktrace.clear_parsers()
  end)

  describe("setup", function()
    it("should initialize with default config", function()
      stacktrace.setup({})
      assert.is_true(stacktrace.is_enabled())
    end)

    it("should respect enabled config", function()
      stacktrace.setup({ enabled = false })
      assert.is_false(stacktrace.is_enabled())
    end)

    it("should register built-in patterns for all advertised languages", function()
      stacktrace.setup({})
      local patterns = stacktrace.get_patterns()
      -- Core languages
      assert.is_not_nil(patterns.python)
      assert.is_not_nil(patterns.csharp)
      assert.is_not_nil(patterns.javascript)
      assert.is_not_nil(patterns.javascript_alt)
      assert.is_not_nil(patterns.java)
      assert.is_not_nil(patterns.go)
      assert.is_not_nil(patterns.rust)
      assert.is_not_nil(patterns.lua)
      assert.is_not_nil(patterns.ruby)
      -- C/C++ source and header patterns
      assert.is_not_nil(patterns.c_source)
      assert.is_not_nil(patterns.cpp_source)
      assert.is_not_nil(patterns.cc_source)
      assert.is_not_nil(patterns.cxx_source)
      assert.is_not_nil(patterns.h_header)
      assert.is_not_nil(patterns.hpp_header)
      assert.is_not_nil(patterns.hh_header)
      assert.is_not_nil(patterns.hxx_header)
      -- Other languages
      assert.is_not_nil(patterns.php)
      assert.is_not_nil(patterns.perl)
      assert.is_not_nil(patterns.elixir)
      assert.is_not_nil(patterns.erlang)
      assert.is_not_nil(patterns.swift)
      assert.is_not_nil(patterns.kotlin)
      assert.is_not_nil(patterns.haskell)
    end)
  end)

  describe("parser validation", function()
    it("should reject parser without name", function()
      local parser = {
        patterns = {
          { pattern = "test", path_group = 1, line_group = 2 },
        },
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("name"))
    end)

    it("should reject parser with empty name", function()
      local parser = {
        name = "",
        patterns = {
          { pattern = "test", path_group = 1, line_group = 2 },
        },
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("name"))
    end)

    it("should reject parser without patterns", function()
      local parser = {
        name = "test",
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("patterns"))
    end)

    it("should reject parser with empty patterns array", function()
      local parser = {
        name = "test",
        patterns = {},
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("patterns"))
    end)

    it("should reject pattern without pattern field", function()
      local parser = {
        name = "test",
        patterns = {
          { path_group = 1, line_group = 2 },
        },
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("pattern"))
    end)

    it("should reject pattern with invalid Lua pattern", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "test[", path_group = 1, line_group = 2 },
        },
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("invalid"))
    end)

    it("should reject pattern without path_group", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "test", line_group = 2 },
        },
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("path_group"))
    end)

    it("should reject pattern without line_group", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "test", path_group = 1 },
        },
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("line_group"))
    end)

    it("should accept valid parser with all required fields", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("should accept parser with optional description", function()
      local parser = {
        name = "test",
        description = "Test parser",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      local ok, _err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should accept parser with optional column_group", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+):(%d+)", path_group = 1, line_group = 2, column_group = 3 },
        },
      }
      local ok, _err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should accept parser with optional resolve_path function", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
        resolve_path = function(path, _cwd)
          return path
        end,
      }
      local ok, _err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should accept parser with optional is_context_match function", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
        is_context_match = function(_lines, _index)
          return true
        end,
      }
      local ok, _err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should reject duplicate parser names", function()
      local parser1 = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      local parser2 = {
        name = "test",
        patterns = {
          { pattern = "other", path_group = 1, line_group = 2 },
        },
      }

      local ok1, _err1 = stacktrace.register_parser(parser1)
      assert.is_true(ok1)

      local ok2, err2 = stacktrace.register_parser(parser2)
      assert.is_false(ok2)
      assert.is_truthy(err2:match("already registered"))
    end)
  end)

  describe("parser registration", function()
    it("should register a valid parser", function()
      local parser = {
        name = "myparser",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      local ok = stacktrace.register_parser(parser)
      assert.is_true(ok)

      local retrieved = stacktrace.get_parser("myparser")
      assert.is_not_nil(retrieved)
      assert.are.equal("myparser", retrieved.name)
    end)

    it("should unregister a parser", function()
      local parser = {
        name = "myparser",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local ok = stacktrace.unregister_parser("myparser")
      assert.is_true(ok)

      local retrieved = stacktrace.get_parser("myparser")
      assert.is_nil(retrieved)
    end)

    it("should return false when unregistering non-existent parser", function()
      local ok = stacktrace.unregister_parser("nonexistent")
      assert.is_false(ok)
    end)

    it("should retrieve all registered parsers", function()
      local parser1 = {
        name = "parser1",
        patterns = {
          { pattern = "test1", path_group = 1, line_group = 2 },
        },
      }
      local parser2 = {
        name = "parser2",
        patterns = {
          { pattern = "test2", path_group = 1, line_group = 2 },
        },
      }

      stacktrace.register_parser(parser1)
      stacktrace.register_parser(parser2)

      local all_parsers = stacktrace.get_all_parsers()
      assert.are.equal(2, #all_parsers)
    end)

    it("should clear all parsers", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "test", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      stacktrace.clear_parsers()

      local all_parsers = stacktrace.get_all_parsers()
      assert.are.equal(0, #all_parsers)
    end)
  end)

  describe("line parsing", function()
    it("should parse a simple stack trace line", function()
      local parser = {
        name = "simple",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line("file.txt:42")
      assert.is_not_nil(result)
      assert.are.equal("simple", result.parser_name)
      assert.are.equal("file.txt", result.file_path)
      assert.are.equal(42, result.line_number)
      assert.is_nil(result.column_number)
    end)

    it("should parse line with column number", function()
      local parser = {
        name = "with_col",
        patterns = {
          { pattern = "([^:]+):(%d+):(%d+)", path_group = 1, line_group = 2, column_group = 3 },
        },
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line("file.txt:42:15")
      assert.is_not_nil(result)
      assert.are.equal(42, result.line_number)
      assert.are.equal(15, result.column_number)
    end)

    it("should return nil for non-matching line", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line("no match here")
      assert.is_nil(result)
    end)

    it("should try multiple patterns", function()
      local parser = {
        name = "multi",
        patterns = {
          { pattern = "Format1:%s+([^:]+):(%d+)", path_group = 1, line_group = 2 },
          { pattern = "Format2%s+([^:]+)%s+(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local result1 = stacktrace.parse_line("Format1: file.txt:42")
      assert.is_not_nil(result1)
      assert.are.equal("file.txt", result1.file_path)

      local result2 = stacktrace.parse_line("Format2 other.txt 99")
      assert.is_not_nil(result2)
      assert.are.equal("other.txt", result2.file_path)
    end)

    it("should use custom resolve_path function", function()
      local parser = {
        name = "custom_resolve",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
        resolve_path = function(path, _cwd)
          return "/resolved/" .. path
        end,
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line("file.txt:42")
      assert.is_not_nil(result)
      assert.are.equal("/resolved/file.txt", result.file_path)
    end)
  end)

  describe("multiple line parsing", function()
    it("should parse multiple lines", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local lines = {
        "file1.txt:10",
        "no match",
        "file2.txt:20",
      }

      local results = stacktrace.parse_lines(lines)
      assert.are.equal(2, #results)
      assert.are.equal("file1.txt", results[1].file_path)
      assert.are.equal(10, results[1].line_number)
      assert.are.equal(1, results[1].line_index)
      assert.are.equal("file2.txt", results[2].file_path)
      assert.are.equal(20, results[2].line_number)
      assert.are.equal(3, results[2].line_index)
    end)

    it("should return empty array for nil input", function()
      local results = stacktrace.parse_lines(nil)
      assert.are.equal(0, #results)
    end)

    it("should return empty array for empty lines", function()
      local results = stacktrace.parse_lines({})
      assert.are.equal(0, #results)
    end)
  end)

  describe("setup and configuration", function()
    it("should load built-in parsers from config", function()
      stacktrace.setup({
        languages = { "python" },
      })

      local parser = stacktrace.get_parser("python")
      assert.is_not_nil(parser)
      assert.are.equal("python", parser.name)
    end)

    it("should load multiple built-in parsers", function()
      stacktrace.setup({
        languages = { "python", "csharp" },
      })

      local python = stacktrace.get_parser("python")
      local csharp = stacktrace.get_parser("csharp")
      assert.is_not_nil(python)
      assert.is_not_nil(csharp)
    end)

    it("should load custom parsers from config", function()
      local custom_parser = {
        name = "custom",
        patterns = {
          { pattern = "CUSTOM:%s+([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }

      stacktrace.setup({
        custom_parsers = { custom_parser },
      })

      local parser = stacktrace.get_parser("custom")
      assert.is_not_nil(parser)
      assert.is_true(parser.custom)
    end)

    it("should warn on invalid built-in parser", function()
      -- Should not error, just warn
      stacktrace.setup({
        languages = { "nonexistent_language" },
      })
    end)

    it("should warn on invalid custom parser", function()
      local invalid_parser = {
        name = "invalid",
        -- Missing patterns
      }

      -- Should not error, just warn
      stacktrace.setup({
        custom_parsers = { invalid_parser },
      })
    end)

    it("should return config via get_config", function()
      local config = {
        enabled = true,
        languages = { "python" },
      }
      stacktrace.setup(config)

      local retrieved_config = stacktrace.get_config()
      assert.is_not_nil(retrieved_config)
      assert.is_true(retrieved_config.enabled)
    end)
  end)

  describe("Python parser", function()
    local python_parser

    before_each(function()
      package.loaded["termlet.parsers.python"] = nil
      python_parser = require("termlet.parsers.python")
      stacktrace.register_parser(python_parser)
    end)

    it("should parse standard Python traceback format", function()
      local line = '  File "/path/to/file.py", line 42, in function_name'
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("python", result.parser_name)
      assert.are.equal("/path/to/file.py", result.file_path)
      assert.are.equal(42, result.line_number)
    end)

    it("should parse Python traceback with single quotes", function()
      local line = "  File '/path/to/file.py', line 99, in method"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("/path/to/file.py", result.file_path)
      assert.are.equal(99, result.line_number)
    end)

    it("should parse pytest format", function()
      local line = "tests/test_module.py:42: AssertionError"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("tests/test_module.py", result.file_path)
      assert.are.equal(42, result.line_number)
    end)
  end)

  describe("C# parser", function()
    local csharp_parser

    before_each(function()
      package.loaded["termlet.parsers.csharp"] = nil
      csharp_parser = require("termlet.parsers.csharp")
      stacktrace.register_parser(csharp_parser)
    end)

    it("should parse standard .NET stack trace format with Windows path", function()
      local line = "   at ClassName.MethodName() in C:\\path\\to\\File.cs:line 42"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("csharp", result.parser_name)
      -- Verify full Windows path is captured (not just drive letter)
      -- resolve_path normalizes backslashes to forward slashes
      assert.are.equal("C:/path/to/File.cs", result.file_path)
      assert.are.equal(42, result.line_number)
    end)

    it("should parse Unix-style C# stack trace", function()
      local line = "   at ClassName.MethodName() in /path/to/File.cs:line 99"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("/path/to/File.cs", result.file_path)
      assert.are.equal(99, result.line_number)
    end)

    it("should parse MSBuild error format", function()
      local line = "File.cs(42,15): error CS1234: Error message"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("File.cs", result.file_path)
      assert.are.equal(42, result.line_number)
      assert.are.equal(15, result.column_number)
    end)

    it("should parse MSBuild error format with path containing forward slash", function()
      local line = "BV/APITest.cs(1887,62): error CS1503: Argument 1: cannot convert from"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("BV/APITest.cs", result.file_path)
      assert.are.equal(1887, result.line_number)
      assert.are.equal(62, result.column_number)
    end)

    it("should parse MSBuild error format with absolute Windows path", function()
      local line = "C:\\Projects\\MyApp\\Program.cs(10,5): warning CS0168: The variable"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("C:/Projects/MyApp/Program.cs", result.file_path)
      assert.are.equal(10, result.line_number)
      assert.are.equal(5, result.column_number)
    end)

    it("should parse MSBuild error format without column number", function()
      local line = "src/Utils.cs(123): error CS0246: The type or namespace"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("src/Utils.cs", result.file_path)
      assert.are.equal(123, result.line_number)
      assert.is_nil(result.column_number)
    end)

    it("should parse .NET exception with deeply nested path", function()
      local line = "   at MyNamespace.MyClass.MyMethod() in /home/dev/project/src/core/MyClass.cs:line 42"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("/home/dev/project/src/core/MyClass.cs", result.file_path)
      assert.are.equal(42, result.line_number)
    end)

    it("should parse MSBuild error with path containing spaces", function()
      local line = "My Project/My File.cs(10,5): error CS1234: The type or namespace"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("My Project/My File.cs", result.file_path)
      assert.are.equal(10, result.line_number)
      assert.are.equal(5, result.column_number)
    end)

    it("should parse MSBuild error with Windows path using backslashes", function()
      -- Test that the pattern correctly matches Windows backslash paths
      -- In real terminal output, this would be: C:\Users\Dev\Project\File.cs(42,15): error
      -- In Lua string literals, we need to escape backslashes, so \\ represents one backslash
      local line = "C:\\Users\\Dev\\Project\\File.cs(42,15): error CS1234: Error message"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      -- The resolve_path function normalizes backslashes to forward slashes
      assert.are.equal("C:/Users/Dev/Project/File.cs", result.file_path)
      assert.are.equal(42, result.line_number)
      assert.are.equal(15, result.column_number)
    end)
  end)

  describe("JavaScript parser", function()
    local js_parser

    before_each(function()
      package.loaded["termlet.parsers.javascript"] = nil
      js_parser = require("termlet.parsers.javascript")
      stacktrace.register_parser(js_parser)
    end)

    it("should parse Node.js stack trace format", function()
      local line = "    at functionName (/path/to/file.js:42:15)"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("javascript", result.parser_name)
      assert.are.equal("/path/to/file.js", result.file_path)
      assert.are.equal(42, result.line_number)
      assert.are.equal(15, result.column_number)
    end)

    it("should parse browser stack trace format", function()
      local line = "at http://localhost:3000/app.js:42:15"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("app.js", result.file_path)
      assert.are.equal(42, result.line_number)
    end)
  end)

  describe("Java parser", function()
    local java_parser

    before_each(function()
      package.loaded["termlet.parsers.java"] = nil
      java_parser = require("termlet.parsers.java")
      stacktrace.register_parser(java_parser)
    end)

    it("should parse standard Java stack trace format", function()
      local line = "\tat com.example.ClassName.methodName(FileName.java:42)"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("java", result.parser_name)
      assert.are.equal("FileName.java", result.file_path)
      assert.are.equal(42, result.line_number)
    end)

    it("should parse Java compiler error format", function()
      local line = "FileName.java:99: error: compilation error message"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("FileName.java", result.file_path)
      assert.are.equal(99, result.line_number)
    end)
  end)

  describe("setup idempotency", function()
    it("should allow calling setup() twice without errors", function()
      stacktrace.setup({
        languages = { "python" },
      })
      local python1 = stacktrace.get_parser("python")
      assert.is_not_nil(python1)

      -- Second call should not fail
      stacktrace.setup({
        languages = { "python", "csharp" },
      })
      local python2 = stacktrace.get_parser("python")
      local csharp = stacktrace.get_parser("csharp")
      assert.is_not_nil(python2)
      assert.is_not_nil(csharp)
    end)

    it("should replace parsers when setup() called with different config", function()
      stacktrace.setup({
        languages = { "python", "csharp" },
      })
      assert.is_not_nil(stacktrace.get_parser("python"))
      assert.is_not_nil(stacktrace.get_parser("csharp"))

      -- Second setup with only python
      stacktrace.setup({
        languages = { "python" },
      })
      assert.is_not_nil(stacktrace.get_parser("python"))
      assert.is_nil(stacktrace.get_parser("csharp"))
    end)
  end)

  describe("parser ordering determinism", function()
    it("should respect custom before builtin order", function()
      local custom_parser = {
        name = "custom_at",
        patterns = {
          { pattern = "%s+at%s+([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
        custom = true,
      }
      local builtin_parser = {
        name = "builtin_at",
        patterns = {
          { pattern = "%s+at%s+([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }

      stacktrace.register_parser(builtin_parser)
      stacktrace.register_parser(custom_parser)

      -- With default parser_order = { "custom", "builtin" }, custom should match first
      local result = stacktrace.parse_line("  at file.txt:42")
      assert.is_not_nil(result)
      assert.are.equal("custom_at", result.parser_name)
    end)

    it("should return parsers in insertion order via get_all_parsers", function()
      local parser_a = {
        name = "aaa",
        patterns = { { pattern = "test", path_group = 1, line_group = 2 } },
      }
      local parser_b = {
        name = "bbb",
        patterns = { { pattern = "test", path_group = 1, line_group = 2 } },
      }
      local parser_c = {
        name = "ccc",
        patterns = { { pattern = "test", path_group = 1, line_group = 2 } },
      }

      stacktrace.register_parser(parser_a)
      stacktrace.register_parser(parser_b)
      stacktrace.register_parser(parser_c)

      local all = stacktrace.get_all_parsers()
      assert.are.equal(3, #all)
      assert.are.equal("aaa", all[1].name)
      assert.are.equal("bbb", all[2].name)
      assert.are.equal("ccc", all[3].name)
    end)
  end)

  describe("empty optional column capture", function()
    it("should return nil column_number for empty optional capture", function()
      local parser = {
        name = "optional_col",
        patterns = {
          { pattern = "([^:]+):(%d+):?(%d*)", path_group = 1, line_group = 2, column_group = 3 },
        },
      }
      stacktrace.register_parser(parser)

      -- Line without column number - (%d*) matches empty string
      local result = stacktrace.parse_line("file.txt:42")
      assert.is_not_nil(result)
      assert.are.equal("file.txt", result.file_path)
      assert.are.equal(42, result.line_number)
      assert.is_nil(result.column_number)
    end)

    it("should return column_number when present", function()
      local parser = {
        name = "optional_col2",
        patterns = {
          { pattern = "([^:]+):(%d+):?(%d*)", path_group = 1, line_group = 2, column_group = 3 },
        },
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line("file.txt:42:15")
      assert.is_not_nil(result)
      assert.are.equal(15, result.column_number)
    end)
  end)

  describe("parse_line with invalid input types", function()
    it("should return nil for number input", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line(123)
      assert.is_nil(result)
    end)

    it("should return nil for table input", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line({})
      assert.is_nil(result)
    end)

    it("should return nil for boolean input", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }
      stacktrace.register_parser(parser)

      local result = stacktrace.parse_line(true)
      assert.is_nil(result)
    end)
  end)

  describe("is_context_match disambiguation", function()
    it("should use is_context_match to disambiguate in parse_lines", function()
      -- Register two parsers that both match "at" patterns
      local parser_csharp_like = {
        name = "csharp_like",
        patterns = {
          { pattern = "%s+at%s+(.+):(%d+)", path_group = 1, line_group = 2 },
        },
        is_context_match = function(lines, index)
          for i = math.max(1, index - 3), math.min(#lines, index + 3) do
            if lines[i] and lines[i]:match("%.cs:") then
              return true
            end
          end
          return false
        end,
      }
      local parser_java_like = {
        name = "java_like",
        patterns = {
          { pattern = "%s+at%s+(.+):(%d+)", path_group = 1, line_group = 2 },
        },
        is_context_match = function(lines, index)
          for i = math.max(1, index - 3), math.min(#lines, index + 3) do
            if lines[i] and lines[i]:match("%.java:") then
              return true
            end
          end
          return false
        end,
      }

      stacktrace.register_parser(parser_csharp_like)
      stacktrace.register_parser(parser_java_like)

      -- Java context lines
      local lines = {
        "Exception in thread main",
        "  at com.example.Class:42",
        "  at App.java:10",
      }

      local results = stacktrace.parse_lines(lines)
      -- The second line should disambiguate to java_like due to .java: context
      local java_match = nil
      for _, r in ipairs(results) do
        if r.line_index == 2 then
          java_match = r
          break
        end
      end
      assert.is_not_nil(java_match)
      assert.are.equal("java_like", java_match.parser_name)
    end)
  end)

  describe("setup does not mutate user objects", function()
    it("should not add .custom field to user-provided parser table", function()
      local my_parser = {
        name = "user_parser",
        patterns = {
          { pattern = "CUSTOM:%s+([^:]+):(%d+)", path_group = 1, line_group = 2 },
        },
      }

      stacktrace.setup({
        custom_parsers = { my_parser },
      })

      -- The original table should NOT have been mutated
      assert.is_nil(my_parser.custom)
    end)
  end)

  describe("C# parser Windows paths", function()
    local csharp_parser

    before_each(function()
      package.loaded["termlet.parsers.csharp"] = nil
      csharp_parser = require("termlet.parsers.csharp")
      stacktrace.register_parser(csharp_parser)
    end)

    it("should capture full Windows path including drive letter", function()
      local line = "   at MyClass.Method() in C:\\Users\\dev\\Project\\File.cs:line 42"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("csharp", result.parser_name)
      -- resolve_path normalizes backslashes to forward slashes
      assert.are.equal("C:/Users/dev/Project/File.cs", result.file_path)
      assert.are.equal(42, result.line_number)
    end)

    it("should capture full Windows path with D drive", function()
      local line = "   at MyClass.Method() in D:\\code\\src\\Program.cs:line 100"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      -- resolve_path normalizes backslashes to forward slashes
      assert.are.equal("D:/code/src/Program.cs", result.file_path)
      assert.are.equal(100, result.line_number)
    end)
  end)

  describe("register_pattern", function()
    it("should register a new pattern", function()
      stacktrace.register_pattern("custom", {
        pattern = "ERROR at (.+):(%d+)",
        file_pattern = "ERROR at (.+):%d+",
        line_pattern = ":(%d+)$",
      })

      local patterns = stacktrace.get_patterns()
      assert.is_not_nil(patterns.custom)
      assert.equals("ERROR at (.+):(%d+)", patterns.custom.pattern)
    end)

    it("should error on invalid language", function()
      assert.has_error(function()
        stacktrace.register_pattern(nil, { pattern = "test" })
      end)
    end)

    it("should error on missing pattern", function()
      assert.has_error(function()
        stacktrace.register_pattern("test", {})
      end)
    end)

    it("should error on invalid config type", function()
      assert.has_error(function()
        stacktrace.register_pattern("test", "not a table")
      end)
    end)
  end)

  describe("extract_file_info", function()
    before_each(function()
      stacktrace.setup({})
    end)

    it("should extract Python stack trace info", function()
      local line = 'File "/home/user/project/main.py", line 42, in run_tests'
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.python, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/main.py", info.path)
      assert.equals(42, info.line)
      assert.equals("run_tests", info.context)
    end)

    it("should extract C# stack trace info", function()
      local line = "   at MyNamespace.MyClass.MyMethod() in /home/user/project/Program.cs:line 123"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.csharp, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/Program.cs", info.path)
      assert.equals(123, info.line)
    end)

    it("should return nil for non-matching line", function()
      local line = "This is just a regular log message"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.python, "/home/user")

      assert.is_nil(info)
    end)
  end)

  describe("resolve_path", function()
    it("should return absolute paths unchanged", function()
      local result = stacktrace.resolve_path("/absolute/path/to/file.py", "/home/user")
      assert.equals("/absolute/path/to/file.py", result)
    end)

    it("should resolve relative paths using cwd", function()
      local result = stacktrace.resolve_path("src/main.py", "/home/user/project")
      assert.truthy(result:find("/home/user/project", 1, true))
      assert.truthy(result:find("src/main.py", 1, true))
    end)

    it("should handle Windows absolute paths", function()
      local result = stacktrace.resolve_path("C:\\Users\\test\\file.py", "/home/user")
      assert.equals("C:\\Users\\test\\file.py", result)
    end)

    it("should return path as-is when no cwd provided for relative path", function()
      local result = stacktrace.resolve_path("relative/path.py", nil)
      assert.equals("relative/path.py", result)
    end)

    it("should return nil for nil input", function()
      local result = stacktrace.resolve_path(nil, "/home/user")
      assert.is_nil(result)
    end)

    it("should expand tilde to home directory", function()
      local result = stacktrace.resolve_path("~/project/file.py", "/cwd")
      assert.truthy(result:sub(1, 1) == "/")
      assert.truthy(result:find("project/file.py", 1, true))
      assert.is_nil(result:find("^~"))
    end)
  end)

  describe("process_line", function()
    before_each(function()
      stacktrace.setup({})
    end)

    it("should detect Python stack trace line", function()
      local line = 'File "/home/user/test.py", line 10, in main'
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("python", result.language)
      assert.equals("/home/user/test.py", result.path)
      assert.equals(10, result.line)
    end)

    it("should return nil when disabled", function()
      stacktrace.disable()
      local line = 'File "/home/user/test.py", line 10, in main'
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_nil(result)
    end)

    it("should return nil for empty line", function()
      local result = stacktrace.process_line("", "/home/user")
      assert.is_nil(result)
    end)

    it("should return nil for nil line", function()
      local result = stacktrace.process_line(nil, "/home/user")
      assert.is_nil(result)
    end)
  end)

  describe("process_output", function()
    before_each(function()
      stacktrace.setup({})
    end)

    it("should process multiple lines and detect stack traces", function()
      local lines = {
        "Traceback (most recent call last):",
        '  File "/home/user/app.py", line 25, in main',
        "    result = process(data)",
        '  File "/home/user/utils.py", line 42, in process',
        "    return transform(data)",
        "TypeError: cannot transform NoneType",
      }

      local results = stacktrace.process_output(lines, "/home/user")

      assert.equals(2, #results)
      assert.equals("/home/user/app.py", results[1].path)
      assert.equals(25, results[1].line)
      assert.equals("/home/user/utils.py", results[2].path)
      assert.equals(42, results[2].line)
    end)

    it("should return empty table when disabled", function()
      stacktrace.disable()
      local lines = {
        'File "/home/user/test.py", line 10, in main',
      }

      local results = stacktrace.process_output(lines, "/home/user")
      assert.equals(0, #results)
    end)

    it("should return empty table for nil input", function()
      local results = stacktrace.process_output(nil, "/home/user")
      assert.equals(0, #results)
    end)

    it("should include line_index in results", function()
      local lines = {
        "Some log message",
        'File "/home/user/test.py", line 10, in main',
        "Another message",
      }

      local results = stacktrace.process_output(lines, "/home/user")

      assert.equals(1, #results)
      assert.equals(2, results[1].line_index)
    end)
  end)

  describe("metadata storage", function()
    it("should store and retrieve metadata", function()
      local file_info = { path = "/test/file.py", line = 10 }
      stacktrace.store_metadata(1, 5, file_info)

      local retrieved = stacktrace.get_metadata(1, 5)
      assert.equals("/test/file.py", retrieved.path)
      assert.equals(10, retrieved.line)
    end)

    it("should return nil for non-existent metadata", function()
      local result = stacktrace.get_metadata(999, 1)
      assert.is_nil(result)
    end)

    it("should clear metadata for specific buffer", function()
      stacktrace.store_metadata(1, 1, { path = "a.py" })
      stacktrace.store_metadata(2, 1, { path = "b.py" })

      stacktrace.clear_metadata(1)

      assert.is_nil(stacktrace.get_metadata(1, 1))
      assert.is_not_nil(stacktrace.get_metadata(2, 1))
    end)

    it("should clear all metadata", function()
      stacktrace.store_metadata(1, 1, { path = "a.py" })
      stacktrace.store_metadata(2, 1, { path = "b.py" })

      stacktrace.clear_all_metadata()

      assert.is_nil(stacktrace.get_metadata(1, 1))
      assert.is_nil(stacktrace.get_metadata(2, 1))
    end)
  end)

  describe("find_nearest_metadata", function()
    before_each(function()
      stacktrace.store_metadata(1, 5, { path = "file1.py", line = 10 })
      stacktrace.store_metadata(1, 20, { path = "file2.py", line = 20 })
    end)

    it("should find exact match", function()
      local result = stacktrace.find_nearest_metadata(1, 5)
      assert.equals("file1.py", result.path)
    end)

    it("should find nearby metadata within default range of 10", function()
      local result = stacktrace.find_nearest_metadata(1, 14)
      assert.is_not_nil(result)
      assert.equals("file2.py", result.path)
    end)

    it("should return nil when no metadata in range", function()
      local result = stacktrace.find_nearest_metadata(1, 40)
      assert.is_nil(result)
    end)

    it("should return nil for non-existent buffer", function()
      local result = stacktrace.find_nearest_metadata(999, 5)
      assert.is_nil(result)
    end)

    it("should respect custom range when specified", function()
      local result = stacktrace.find_nearest_metadata(1, 8, 3)
      assert.is_not_nil(result)
      assert.equals("file1.py", result.path)
    end)
  end)

  describe("enable/disable", function()
    it("should enable processing", function()
      stacktrace.setup({ enabled = false })
      assert.is_false(stacktrace.is_enabled())

      stacktrace.enable()
      assert.is_true(stacktrace.is_enabled())
    end)

    it("should disable processing", function()
      stacktrace.setup({ enabled = true })
      assert.is_true(stacktrace.is_enabled())

      stacktrace.disable()
      assert.is_false(stacktrace.is_enabled())
    end)
  end)

  describe("buffer management", function()
    it("should clear buffer", function()
      local data = { "line1", "line2" }
      stacktrace.process_terminal_output(data, "/home", nil)
      assert.equals(2, #stacktrace.get_buffer())

      stacktrace.clear_buffer()
      assert.equals(0, #stacktrace.get_buffer())
    end)

    it("should limit buffer size", function()
      stacktrace.setup({ buffer_size = 5 })

      local data = {}
      for i = 1, 10 do
        table.insert(data, "line" .. i)
      end

      stacktrace.process_terminal_output(data, "/home", nil)
      assert.equals(5, #stacktrace.get_buffer())
    end)
  end)

  describe("strip_ansi", function()
    before_each(function()
      stacktrace.setup({})
    end)

    it("should strip basic CSI escape sequences", function()
      local input = '\27[0m  File "/home/user/test.py", line 7, in <module>\27[0m'
      local result = stacktrace.strip_ansi(input)
      assert.equals('  File "/home/user/test.py", line 7, in <module>', result)
    end)

    it("should strip color codes", function()
      local input = "\27[31merror\27[0m: something failed at \27[1m/path/file.py\27[0m:42"
      local result = stacktrace.strip_ansi(input)
      assert.equals("error: something failed at /path/file.py:42", result)
    end)

    it("should return clean string unchanged", function()
      local input = 'File "/home/user/test.py", line 7, in main'
      local result = stacktrace.strip_ansi(input)
      assert.equals(input, result)
    end)
  end)

  describe("integration with termlet", function()
    local termlet

    before_each(function()
      package.loaded["termlet"] = nil
      package.loaded["termlet.menu"] = nil
      package.loaded["termlet.stacktrace"] = nil
      termlet = require("termlet")
    end)

    after_each(function()
      if termlet.close_menu then
        termlet.close_menu()
      end
      termlet.close_all_terminals()
    end)

    it("should expose stacktrace module", function()
      termlet.setup({ scripts = {} })
      assert.is_not_nil(termlet.stacktrace)
    end)

    it("should configure stacktrace via setup", function()
      termlet.setup({
        scripts = {},
        stacktrace = {
          enabled = false,
          languages = { "python" },
        },
      })

      assert.is_false(termlet.stacktrace.is_enabled())
    end)

    it("should have goto_stacktrace function", function()
      termlet.setup({ scripts = {} })
      assert.is_function(termlet.goto_stacktrace)
    end)

    it("should have get_stacktrace_at_cursor function", function()
      termlet.setup({ scripts = {} })
      assert.is_function(termlet.get_stacktrace_at_cursor)
    end)

    it("should initialize stacktrace when enabled in config", function()
      termlet.setup({
        scripts = {},
        stacktrace = {
          enabled = true,
          languages = { "python" },
        },
      })

      local parser = termlet.stacktrace.get_parser("python")
      assert.is_not_nil(parser)
    end)

    it("should detect MSBuild errors in terminal buffer via goto_stacktrace", function()
      termlet.setup({
        scripts = {},
        stacktrace = {
          enabled = true,
          -- Empty languages array should load all parsers (including csharp)
          languages = {},
        },
      })

      -- Create a buffer with MSBuild error output
      local buf = vim.api.nvim_create_buf(false, true)
      local lines = {
        "Building project...",
        "CCSO/engines/bv/Engine.cs(20,19): error CS1061: 'BVEngine' does not contain a definition for 'Run2'",
        "Build failed.",
      }
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      -- Simulate stacktrace detection (as would happen in terminal output processing)
      local cwd = vim.fn.getcwd()
      local results = termlet.stacktrace.scan_buffer_for_stacktraces(buf, cwd)

      -- Verify that the MSBuild error was detected
      assert.are.equal(1, #results)
      assert.are.equal("CCSO/engines/bv/Engine.cs", results[1].file_path)
      assert.are.equal(20, results[1].line_number)
      assert.are.equal(19, results[1].column_number)

      -- Verify metadata was stored at the correct line (line 2)
      local file_info = termlet.stacktrace.find_nearest_metadata(buf, 2)
      assert.is_not_nil(file_info)
      assert.are.equal("CCSO/engines/bv/Engine.cs", file_info.file_path)
      assert.are.equal(20, file_info.line_number)
      assert.are.equal(19, file_info.column_number)

      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should load all built-in parsers when languages array is empty", function()
      termlet.setup({
        scripts = {},
        stacktrace = {
          enabled = true,
          languages = {}, -- Should load all parsers
        },
      })

      -- Verify that csharp parser is loaded
      local csharp_parser = termlet.stacktrace.get_parser("csharp")
      assert.is_not_nil(csharp_parser, "C# parser should be loaded when languages={}")

      -- Verify other common parsers are also loaded
      local python_parser = termlet.stacktrace.get_parser("python")
      assert.is_not_nil(python_parser, "Python parser should be loaded when languages={}")
    end)
  end)
end)
