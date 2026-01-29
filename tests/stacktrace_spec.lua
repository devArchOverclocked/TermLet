-- Tests for TermLet stacktrace module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.stacktrace", function()
  local stacktrace

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.stacktrace"] = nil
    stacktrace = require("termlet.stacktrace")
    stacktrace.clear_buffer()
    stacktrace.clear_all_metadata()
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
      -- Newly added languages
      assert.is_not_nil(patterns.c_cpp)
      assert.is_not_nil(patterns.c_cpp_header)
      assert.is_not_nil(patterns.php)
      assert.is_not_nil(patterns.perl)
      assert.is_not_nil(patterns.elixir)
      assert.is_not_nil(patterns.erlang)
      assert.is_not_nil(patterns.swift)
      assert.is_not_nil(patterns.kotlin)
      assert.is_not_nil(patterns.haskell)
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

    it("should extract JavaScript stack trace info with function name", function()
      local line = "    at myFunction (/home/user/project/index.js:25:10)"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.javascript, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/index.js", info.path)
      assert.equals(25, info.line)
      assert.equals(10, info.column)
      assert.equals("myFunction", info.context)
    end)

    it("should extract Go stack trace info", function()
      local line = "	/home/user/project/main.go:42 +0x456"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.go, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/main.go", info.path)
      assert.equals(42, info.line)
    end)

    it("should extract Java stack trace info", function()
      local line = "	at com.example.MyClass.method(MyFile.java:55)"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.java, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("MyFile.java", info.original_path)
      assert.equals(55, info.line)
    end)

    it("should extract Lua stack trace info", function()
      local line = "	/home/user/project/init.lua:123: attempt to index nil value"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.lua, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/init.lua", info.path)
      assert.equals(123, info.line)
    end)

    it("should extract Ruby stack trace info", function()
      local line = "/home/user/project/app.rb:78:in `calculate'"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.ruby, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/app.rb", info.path)
      assert.equals(78, info.line)
      assert.equals("calculate", info.context)
    end)

    it("should extract Rust stack trace info", function()
      local line = "   at /home/user/project/main.rs:42:15"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.rust, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/main.rs", info.path)
      assert.equals(42, info.line)
      assert.equals(15, info.column)
    end)

    it("should extract Elixir stack trace info", function()
      local line = "    lib/my_app/worker.ex:42: MyApp.Worker.run/1"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.elixir, "/home/user/project")

      assert.is_not_nil(info)
      assert.truthy(info.original_path:find("worker%.ex"))
      assert.equals(42, info.line)
    end)

    it("should extract Erlang stack trace info", function()
      local line = '{module,function,1,[{file,"src/module.erl"},{line,42}]}'
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.erlang, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("src/module.erl", info.original_path)
      assert.equals(42, info.line)
    end)

    it("should extract Swift stack trace info", function()
      local line = "/home/user/project/main.swift:42:15: error: something went wrong"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.swift, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/main.swift", info.path)
      assert.equals(42, info.line)
      assert.equals(15, info.column)
    end)

    it("should extract Kotlin stack trace info", function()
      local line = "	at com.example.MyClass.method(MyFile.kt:55)"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.kotlin, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("MyFile.kt", info.original_path)
      assert.equals(55, info.line)
    end)

    it("should extract Haskell stack trace info", function()
      local line = "/home/user/project/Main.hs:42:15: error:"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.haskell, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/Main.hs", info.path)
      assert.equals(42, info.line)
      assert.equals(15, info.column)
    end)

    it("should extract PHP stack trace info", function()
      local line = "#0 /home/user/project/index.php(42): ClassName->method()"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.php, "/home/user/project")

      assert.is_not_nil(info)
      assert.truthy(info.path:find("index%.php"))
      assert.equals(42, info.line)
    end)

    it("should extract Perl stack trace info", function()
      local line = "at /home/user/project/script.pl line 42."
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.perl, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/script.pl", info.path)
      assert.equals(42, info.line)
    end)

    it("should extract C/C++ stack trace info", function()
      local line = "/home/user/project/main.cpp:42:15: error: expected ';'"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.c_cpp, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/main.cpp", info.path)
      assert.equals(42, info.line)
    end)

    it("should extract C header file stack trace info", function()
      local line = "/home/user/project/utils.h:10:5: warning: unused variable"
      local patterns = stacktrace.get_patterns()
      local info = stacktrace.extract_file_info(line, patterns.c_cpp_header, "/home/user/project")

      assert.is_not_nil(info)
      assert.equals("/home/user/project/utils.h", info.path)
      assert.equals(10, info.line)
      assert.equals(5, info.column)
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
      -- The result should contain the cwd
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
      -- After tilde expansion, path should start with / (absolute)
      assert.truthy(result:sub(1, 1) == "/")
      -- Should contain the rest of the path
      assert.truthy(result:find("project/file.py", 1, true))
      -- Should NOT start with ~
      assert.is_nil(result:find("^~"))
    end)

    it("should expand tilde with subdirectory", function()
      local result = stacktrace.resolve_path("~/src/main.py", nil)
      assert.truthy(result:sub(1, 1) == "/")
      assert.truthy(result:find("src/main.py", 1, true))
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

    it("should detect C/C++ compiler error line", function()
      local line = "/home/user/main.cpp:42:15: error: expected ';'"
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("c_cpp", result.language)
      assert.equals(42, result.line)
    end)

    it("should detect PHP stack trace line", function()
      local line = "#0 /home/user/index.php(42): ClassName->method()"
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("php", result.language)
      assert.equals(42, result.line)
    end)

    it("should detect Perl stack trace line", function()
      local line = "at /home/user/script.pl line 42."
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("perl", result.language)
      assert.equals(42, result.line)
    end)

    it("should detect Elixir stack trace line", function()
      local line = "    lib/my_app/worker.ex:42: MyApp.Worker.run/1"
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("elixir", result.language)
      assert.equals(42, result.line)
    end)

    it("should detect Swift stack trace line", function()
      local line = "/home/user/main.swift:42:15: error: something went wrong"
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("swift", result.language)
      assert.equals(42, result.line)
    end)

    it("should detect Kotlin stack trace line", function()
      local line = "	at com.example.MyClass.method(MyFile.kt:55)"
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("kotlin", result.language)
      assert.equals(55, result.line)
    end)

    it("should detect Haskell stack trace line", function()
      local line = "/home/user/Main.hs:42:15: error:"
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("haskell", result.language)
      assert.equals(42, result.line)
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
        '    result = process(data)',
        '  File "/home/user/utils.py", line 42, in process',
        '    return transform(data)',
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

  describe("process_terminal_output", function()
    before_each(function()
      stacktrace.setup({})
    end)

    it("should process terminal data and add to buffer", function()
      local data = {
        'File "/home/user/test.py", line 10, in main',
        "Error occurred",
      }

      stacktrace.process_terminal_output(data, "/home/user", nil)
      local buffer = stacktrace.get_buffer()

      assert.equals(2, #buffer)
    end)

    it("should store metadata when buffer_id provided", function()
      local data = {
        'File "/home/user/test.py", line 10, in main',
      }

      -- buffer_id 123 is not a valid Neovim buffer, so terminal_line_count = 0
      -- First non-empty line gets line_offset=1, so metadata key = 0 + 1 = 1
      stacktrace.process_terminal_output(data, "/home/user", 123)
      local metadata = stacktrace.get_buffer_metadata(123)

      assert.is_not_nil(metadata[1])
      assert.equals("/home/user/test.py", metadata[1].path)
    end)

    it("should key metadata on offset-based line numbers", function()
      local data = {
        "Some log line with no trace",
        'File "/home/user/test.py", line 10, in main',
      }

      stacktrace.process_terminal_output(data, "/home/user", 456)
      local metadata = stacktrace.get_buffer_metadata(456)

      -- Both lines are non-empty, so line_offset increments for each.
      -- The stack trace is the 2nd non-empty line -> key = 0 + 2 = 2
      assert.is_nil(metadata[1]) -- First line is not a stack trace
      assert.is_not_nil(metadata[2])
      assert.equals("/home/user/test.py", metadata[2].path)
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
      stacktrace.store_metadata(1, 10, { path = "file2.py", line = 20 })
    end)

    it("should find exact match", function()
      local result = stacktrace.find_nearest_metadata(1, 5)
      assert.equals("file1.py", result.path)
    end)

    it("should find nearby metadata above", function()
      local result = stacktrace.find_nearest_metadata(1, 7, 5)
      assert.equals("file1.py", result.path)
    end)

    it("should find nearby metadata below", function()
      local result = stacktrace.find_nearest_metadata(1, 8, 5)
      assert.equals("file2.py", result.path)
    end)

    it("should return nil when no metadata in range", function()
      local result = stacktrace.find_nearest_metadata(1, 100, 5)
      assert.is_nil(result)
    end)

    it("should return nil for non-existent buffer", function()
      local result = stacktrace.find_nearest_metadata(999, 5)
      assert.is_nil(result)
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

  describe("language filtering", function()
    before_each(function()
      stacktrace.setup({ languages = { "python" } })
    end)

    it("should detect enabled language", function()
      local line = 'File "/home/user/test.py", line 10, in main'
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_not_nil(result)
      assert.equals("python", result.language)
    end)

    it("should not detect disabled language", function()
      local line = "   at MyClass.Method() in /home/user/Program.cs:line 42"
      local result = stacktrace.process_line(line, "/home/user")

      assert.is_nil(result)
    end)
  end)

  describe("pattern ordering and priority", function()
    before_each(function()
      stacktrace.setup({})
    end)

    it("should return patterns in priority order via get_pattern_list", function()
      local list = stacktrace.get_pattern_list()
      assert.is_true(#list > 0)
      -- Verify descending priority order
      for i = 2, #list do
        assert.is_true(list[i - 1].priority >= list[i].priority,
          "Pattern " .. list[i - 1].language .. " (priority " .. list[i - 1].priority ..
          ") should come before " .. list[i].language .. " (priority " .. list[i].priority .. ")")
      end
    end)

    it("should match higher-priority patterns first", function()
      -- Python pattern has priority 10, so it should match before any lower-priority pattern
      local line = 'File "/home/user/test.py", line 10, in main'
      local result = stacktrace.process_line(line, "/home/user")
      assert.is_not_nil(result)
      assert.equals("python", result.language)
    end)

    it("should allow re-registering a pattern with new priority", function()
      stacktrace.register_pattern("custom_high", {
        pattern = "CUSTOM: (.+):(%d+)",
        file_pattern = "CUSTOM: (.+):%d+",
        line_pattern = ":(%d+)$",
        priority = 100,
      })

      local list = stacktrace.get_pattern_list()
      -- The custom_high pattern should be first due to highest priority
      assert.equals("custom_high", list[1].language)
    end)
  end)

  describe("get_patterns immutability", function()
    before_each(function()
      stacktrace.setup({})
    end)

    it("should return a copy, not a reference", function()
      local patterns1 = stacktrace.get_patterns()
      local patterns2 = stacktrace.get_patterns()
      -- Modifying the returned table should not affect future calls
      patterns1.python = nil
      assert.is_not_nil(patterns2.python)
      -- Get a fresh copy and verify python is still there
      local patterns3 = stacktrace.get_patterns()
      assert.is_not_nil(patterns3.python)
    end)

    it("should return a deep copy from get_pattern_list", function()
      local list1 = stacktrace.get_pattern_list()
      local list2 = stacktrace.get_pattern_list()
      -- Modifying the returned list should not affect internal state
      table.remove(list1, 1)
      assert.is_true(#list2 > #list1)
    end)
  end)

  describe("get_config", function()
    it("should return current configuration", function()
      stacktrace.setup({
        enabled = true,
        buffer_size = 100,
        languages = { "python", "javascript" },
      })

      local cfg = stacktrace.get_config()
      assert.is_true(cfg.enabled)
      assert.equals(100, cfg.buffer_size)
      assert.equals(2, #cfg.languages)
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
  end)
end)
