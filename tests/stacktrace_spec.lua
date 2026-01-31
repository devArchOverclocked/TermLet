-- Tests for TermLet stacktrace parser plugin architecture
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("stacktrace parser plugin system", function()
  local stacktrace

  before_each(function()
    -- Clear cached modules to get fresh state
    package.loaded["termlet.stacktrace"] = nil
    package.loaded["termlet.parsers.python"] = nil
    package.loaded["termlet.parsers.csharp"] = nil
    package.loaded["termlet.parsers.javascript"] = nil
    package.loaded["termlet.parsers.java"] = nil
    stacktrace = require("termlet.stacktrace")
    stacktrace.clear_parsers()
  end)

  describe("parser validation", function()
    it("should reject parser without name", function()
      local parser = {
        patterns = {
          { pattern = "test", path_group = 1, line_group = 2 }
        }
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("name"))
    end)

    it("should reject parser with empty name", function()
      local parser = {
        name = "",
        patterns = {
          { pattern = "test", path_group = 1, line_group = 2 }
        }
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
        patterns = {}
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("patterns"))
    end)

    it("should reject pattern without pattern field", function()
      local parser = {
        name = "test",
        patterns = {
          { path_group = 1, line_group = 2 }
        }
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("pattern"))
    end)

    it("should reject pattern with invalid Lua pattern", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "test[", path_group = 1, line_group = 2 }
        }
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("invalid"))
    end)

    it("should reject pattern without path_group", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "test", line_group = 2 }
        }
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("path_group"))
    end)

    it("should reject pattern without line_group", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "test", path_group = 1 }
        }
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_false(ok)
      assert.is_truthy(err:match("line_group"))
    end)

    it("should accept valid parser with all required fields", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
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
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should accept parser with optional column_group", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+):(%d+)", path_group = 1, line_group = 2, column_group = 3 }
        }
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should accept parser with optional resolve_path function", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        },
        resolve_path = function(path, cwd) return path end
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should accept parser with optional is_context_match function", function()
      local parser = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        },
        is_context_match = function(lines, index) return true end
      }
      local ok, err = stacktrace.register_parser(parser)
      assert.is_true(ok)
    end)

    it("should reject duplicate parser names", function()
      local parser1 = {
        name = "test",
        patterns = {
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
      }
      local parser2 = {
        name = "test",
        patterns = {
          { pattern = "other", path_group = 1, line_group = 2 }
        }
      }

      local ok1, err1 = stacktrace.register_parser(parser1)
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
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
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
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
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
          { pattern = "test1", path_group = 1, line_group = 2 }
        }
      }
      local parser2 = {
        name = "parser2",
        patterns = {
          { pattern = "test2", path_group = 1, line_group = 2 }
        }
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
          { pattern = "test", path_group = 1, line_group = 2 }
        }
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
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
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
          { pattern = "([^:]+):(%d+):(%d+)", path_group = 1, line_group = 2, column_group = 3 }
        }
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
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
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
        }
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
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        },
        resolve_path = function(path, cwd)
          return "/resolved/" .. path
        end
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
          { pattern = "([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
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
        languages = { "python" }
      })

      local parser = stacktrace.get_parser("python")
      assert.is_not_nil(parser)
      assert.are.equal("python", parser.name)
    end)

    it("should load multiple built-in parsers", function()
      stacktrace.setup({
        languages = { "python", "csharp" }
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
          { pattern = "CUSTOM:%s+([^:]+):(%d+)", path_group = 1, line_group = 2 }
        }
      }

      stacktrace.setup({
        custom_parsers = { custom_parser }
      })

      local parser = stacktrace.get_parser("custom")
      assert.is_not_nil(parser)
      assert.is_true(parser.custom)
    end)

    it("should warn on invalid built-in parser", function()
      -- Should not error, just warn
      stacktrace.setup({
        languages = { "nonexistent_language" }
      })
    end)

    it("should warn on invalid custom parser", function()
      local invalid_parser = {
        name = "invalid",
        -- Missing patterns
      }

      -- Should not error, just warn
      stacktrace.setup({
        custom_parsers = { invalid_parser }
      })
    end)

    it("should return config via get_config", function()
      local config = {
        enabled = true,
        languages = { "python" }
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

    it("should parse standard .NET stack trace format", function()
      local line = "   at ClassName.MethodName() in C:\\path\\to\\File.cs:line 42"
      local result = stacktrace.parse_line(line)

      assert.is_not_nil(result)
      assert.are.equal("csharp", result.parser_name)
      assert.is_truthy(result.file_path:match("File.cs"))
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

  describe("integration with termlet", function()
    local termlet

    before_each(function()
      package.loaded["termlet"] = nil
      package.loaded["termlet.stacktrace"] = nil
      package.loaded["termlet.menu"] = nil
      termlet = require("termlet")
    end)

    it("should expose stacktrace module", function()
      assert.is_not_nil(termlet.stacktrace)
      assert.is_function(termlet.stacktrace.register_parser)
    end)

    it("should initialize stacktrace when enabled in config", function()
      termlet.setup({
        scripts = {},
        stacktrace = {
          enabled = true,
          languages = { "python" }
        }
      })

      local parser = termlet.stacktrace.get_parser("python")
      assert.is_not_nil(parser)
    end)

    it("should not initialize stacktrace when disabled", function()
      termlet.setup({
        scripts = {},
        stacktrace = {
          enabled = false,
          languages = { "python" }
        }
      })

      -- Parser should not be registered
      local parser = termlet.stacktrace.get_parser("python")
      assert.is_nil(parser)
    end)
  end)
end)
