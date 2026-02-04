-- Tests for TermLet Watch Module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.watch", function()
  local watch

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.watch"] = nil
    watch = require("termlet.watch")
    watch.stop_all()
  end)

  after_each(function()
    watch.stop_all()
  end)

  describe("glob_to_pattern", function()
    it("should convert simple extension glob", function()
      local pattern = watch._glob_to_pattern("*.lua")
      assert.is_truthy(("test.lua"):match(pattern))
      assert.is_truthy(("init.lua"):match(pattern))
      assert.is_falsy(("test.py"):match(pattern))
    end)

    it("should convert glob with question mark", function()
      local pattern = watch._glob_to_pattern("test?.lua")
      assert.is_truthy(("test1.lua"):match(pattern))
      assert.is_truthy(("testA.lua"):match(pattern))
      assert.is_falsy(("test12.lua"):match(pattern))
      assert.is_falsy(("test.lua"):match(pattern))
    end)

    it("should convert double star glob for recursive matching", function()
      local pattern = watch._glob_to_pattern("**/*.lua")
      assert.is_truthy(("src/init.lua"):match(pattern))
      assert.is_truthy(("a/b/c/test.lua"):match(pattern))
      assert.is_falsy(("test.py"):match(pattern))
    end)

    it("should handle plain filename", function()
      local pattern = watch._glob_to_pattern("Makefile")
      assert.is_truthy(("Makefile"):match(pattern))
      assert.is_falsy(("Makefile.bak"):match(pattern))
    end)

    it("should escape Lua pattern metacharacters", function()
      local pattern = watch._glob_to_pattern("file.min.js")
      assert.is_truthy(("file.min.js"):match(pattern))
      assert.is_falsy(("filexminxjs"):match(pattern))
    end)

    it("should handle mixed wildcards", function()
      local pattern = watch._glob_to_pattern("src/**/*.test.?s")
      assert.is_truthy(("src/components/App.test.ts"):match(pattern))
      assert.is_truthy(("src/utils/helper.test.js"):match(pattern))
      assert.is_falsy(("src/App.test.css"):match(pattern))
    end)
  end)

  describe("matches_patterns", function()
    it("should match files against patterns", function()
      local patterns = { "*.lua", "*.py" }
      assert.is_true(watch._matches_patterns("test.lua", patterns))
      assert.is_true(watch._matches_patterns("script.py", patterns))
      assert.is_false(watch._matches_patterns("file.js", patterns))
    end)

    it("should return false for empty patterns", function()
      assert.is_false(watch._matches_patterns("test.lua", {}))
      assert.is_false(watch._matches_patterns("test.lua", nil))
    end)

    it("should match recursive patterns", function()
      local patterns = { "**/*.lua" }
      assert.is_true(watch._matches_patterns("src/test.lua", patterns))
      assert.is_true(watch._matches_patterns("deep/nested/file.lua", patterns))
    end)
  end)

  describe("is_excluded", function()
    it("should detect excluded paths", function()
      local exclude = { "node_modules", ".git" }
      assert.is_true(watch._is_excluded("node_modules", exclude))
      assert.is_true(watch._is_excluded(".git", exclude))
      assert.is_false(watch._is_excluded("src", exclude))
    end)

    it("should return false for nil exclude list", function()
      assert.is_false(watch._is_excluded("anything", nil))
    end)

    it("should return false for empty exclude list", function()
      assert.is_false(watch._is_excluded("anything", {}))
    end)

    it("should match partial paths containing excluded names", function()
      local exclude = { "node_modules" }
      assert.is_true(watch._is_excluded("path/node_modules/file", exclude))
    end)
  end)

  describe("collect_watch_dirs", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return root directory when no subdirs", function()
      local dirs = watch._collect_watch_dirs(test_root, {})
      assert.are.equal(1, #dirs)
      assert.are.equal(test_root, dirs[1])
    end)

    it("should collect subdirectories", function()
      vim.fn.mkdir(test_root .. "/src", "p")
      vim.fn.mkdir(test_root .. "/lib", "p")

      local dirs = watch._collect_watch_dirs(test_root, {})
      assert.is_true(#dirs >= 3) -- root + src + lib
    end)

    it("should exclude specified directories", function()
      vim.fn.mkdir(test_root .. "/src", "p")
      vim.fn.mkdir(test_root .. "/node_modules", "p")
      vim.fn.mkdir(test_root .. "/.git", "p")

      local dirs = watch._collect_watch_dirs(test_root, { "node_modules", ".git" })

      -- Should have root and src, but not node_modules or .git
      local dir_names = {}
      for _, d in ipairs(dirs) do
        table.insert(dir_names, vim.fn.fnamemodify(d, ":t"))
      end

      local has_node_modules = false
      local has_git = false
      for _, name in ipairs(dir_names) do
        if name == "node_modules" then
          has_node_modules = true
        end
        if name == ".git" then
          has_git = true
        end
      end

      assert.is_false(has_node_modules)
      assert.is_false(has_git)
    end)

    it("should collect nested directories recursively", function()
      vim.fn.mkdir(test_root .. "/a/b/c", "p")

      local dirs = watch._collect_watch_dirs(test_root, {})
      assert.is_true(#dirs >= 4) -- root + a + b + c
    end)

    it("should respect max depth", function()
      vim.fn.mkdir(test_root .. "/a/b/c/d/e", "p")

      local dirs = watch._collect_watch_dirs(test_root, {}, 2)
      -- Should get root + a + b, but not c/d/e
      assert.is_true(#dirs <= 4) -- root + a + b (+ maybe a couple)
    end)
  end)

  describe("start", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
      vim.fn.mkdir(test_root .. "/src", "p")
    end)

    after_each(function()
      watch.stop_all()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should start watching a directory", function()
      local script = { name = "test", filename = "test.sh" }
      local watch_config = { patterns = { "*.lua" } }

      local result = watch.start("test", script, watch_config, test_root)
      assert.is_true(result)
      assert.is_true(watch.is_watching("test"))
    end)

    it("should return false without patterns", function()
      local script = { name = "test", filename = "test.sh" }
      local watch_config = { patterns = {} }

      local result = watch.start("test", script, watch_config, test_root)
      assert.is_false(result)
    end)

    it("should return false without nil patterns", function()
      local script = { name = "test", filename = "test.sh" }
      local watch_config = {}

      local result = watch.start("test", script, watch_config, test_root)
      assert.is_false(result)
    end)

    it("should return false with nil script_name", function()
      local result = watch.start(nil, {}, { patterns = { "*.lua" } }, test_root)
      assert.is_false(result)
    end)

    it("should return false with nil root_dir", function()
      local result = watch.start("test", {}, { patterns = { "*.lua" } }, nil)
      assert.is_false(result)
    end)

    it("should return false for nonexistent root_dir", function()
      local result = watch.start("test", {}, { patterns = { "*.lua" } }, "/nonexistent/path/12345")
      assert.is_false(result)
    end)

    it("should replace existing watcher when starting again", function()
      local script = { name = "test", filename = "test.sh" }
      local watch_config = { patterns = { "*.lua" } }

      watch.start("test", script, watch_config, test_root)
      assert.is_true(watch.is_watching("test"))

      -- Start again with different patterns
      watch.start("test", script, { patterns = { "*.py" } }, test_root)
      assert.is_true(watch.is_watching("test"))

      local cfg = watch.get_watch_config("test")
      assert.are.same({ "*.py" }, cfg.patterns)
    end)

    it("should support watching multiple scripts", function()
      local script1 = { name = "build", filename = "build.sh" }
      local script2 = { name = "test", filename = "test.sh" }

      watch.start("build", script1, { patterns = { "*.lua" } }, test_root)
      watch.start("test", script2, { patterns = { "*.py" } }, test_root)

      assert.is_true(watch.is_watching("build"))
      assert.is_true(watch.is_watching("test"))
    end)
  end)

  describe("stop", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      watch.stop_all()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should stop watching a script", function()
      local script = { name = "test", filename = "test.sh" }
      watch.start("test", script, { patterns = { "*.lua" } }, test_root)
      assert.is_true(watch.is_watching("test"))

      watch.stop("test")
      assert.is_false(watch.is_watching("test"))
    end)

    it("should not error when stopping unwatched script", function()
      watch.stop("nonexistent")
      -- Should not error
      assert.is_false(watch.is_watching("nonexistent"))
    end)
  end)

  describe("stop_all", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should stop all watchers", function()
      local script1 = { name = "build", filename = "build.sh" }
      local script2 = { name = "test", filename = "test.sh" }

      watch.start("build", script1, { patterns = { "*.lua" } }, test_root)
      watch.start("test", script2, { patterns = { "*.py" } }, test_root)

      assert.is_true(watch.is_watching("build"))
      assert.is_true(watch.is_watching("test"))

      watch.stop_all()

      assert.is_false(watch.is_watching("build"))
      assert.is_false(watch.is_watching("test"))
    end)

    it("should not error when no watchers exist", function()
      watch.stop_all()
      -- Should not error
      assert.are.equal(0, #watch.get_watched_scripts())
    end)
  end)

  describe("toggle", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      watch.stop_all()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should enable watching when not active", function()
      local script = { name = "test", filename = "test.sh" }
      local result = watch.toggle("test", script, { patterns = { "*.lua" } }, test_root)
      assert.is_true(result)
      assert.is_true(watch.is_watching("test"))
    end)

    it("should disable watching when active", function()
      local script = { name = "test", filename = "test.sh" }
      watch.start("test", script, { patterns = { "*.lua" } }, test_root)
      assert.is_true(watch.is_watching("test"))

      local result = watch.toggle("test", script, { patterns = { "*.lua" } }, test_root)
      assert.is_false(result)
      assert.is_false(watch.is_watching("test"))
    end)
  end)

  describe("is_watching", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      watch.stop_all()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return false for unknown script", function()
      assert.is_false(watch.is_watching("nonexistent"))
    end)

    it("should return true for active watcher", function()
      local script = { name = "test", filename = "test.sh" }
      watch.start("test", script, { patterns = { "*.lua" } }, test_root)
      assert.is_true(watch.is_watching("test"))
    end)

    it("should return false after stopping", function()
      local script = { name = "test", filename = "test.sh" }
      watch.start("test", script, { patterns = { "*.lua" } }, test_root)
      watch.stop("test")
      assert.is_false(watch.is_watching("test"))
    end)
  end)

  describe("get_watch_config", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      watch.stop_all()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return nil for unknown script", function()
      local cfg = watch.get_watch_config("nonexistent")
      assert.is_nil(cfg)
    end)

    it("should return config for active watcher", function()
      local script = { name = "test", filename = "test.sh" }
      watch.start("test", script, { patterns = { "*.lua", "*.py" }, debounce = 300 }, test_root)

      local cfg = watch.get_watch_config("test")
      assert.is_not_nil(cfg)
      assert.are.same({ "*.lua", "*.py" }, cfg.patterns)
      assert.are.equal(300, cfg.debounce)
    end)

    it("should return a copy (not a reference)", function()
      local script = { name = "test", filename = "test.sh" }
      watch.start("test", script, { patterns = { "*.lua" } }, test_root)

      local cfg1 = watch.get_watch_config("test")
      local cfg2 = watch.get_watch_config("test")
      assert.are_not.equal(cfg1, cfg2) -- Different table references
      assert.are.same(cfg1, cfg2) -- Same content
    end)
  end)

  describe("get_watched_scripts", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      watch.stop_all()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return empty list when nothing is watched", function()
      local scripts = watch.get_watched_scripts()
      assert.are.equal(0, #scripts)
    end)

    it("should return list of watched scripts", function()
      local script1 = { name = "build", filename = "build.sh" }
      local script2 = { name = "test", filename = "test.sh" }

      watch.start("build", script1, { patterns = { "*.lua" } }, test_root)
      watch.start("test", script2, { patterns = { "*.py" } }, test_root)

      local scripts = watch.get_watched_scripts()
      assert.are.equal(2, #scripts)
      -- Should be sorted
      assert.are.equal("build", scripts[1])
      assert.are.equal("test", scripts[2])
    end)

    it("should exclude stopped watchers", function()
      local script1 = { name = "build", filename = "build.sh" }
      local script2 = { name = "test", filename = "test.sh" }

      watch.start("build", script1, { patterns = { "*.lua" } }, test_root)
      watch.start("test", script2, { patterns = { "*.py" } }, test_root)
      watch.stop("build")

      local scripts = watch.get_watched_scripts()
      assert.are.equal(1, #scripts)
      assert.are.equal("test", scripts[1])
    end)
  end)

  describe("get_state", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      watch.stop_all()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return empty state when no watchers", function()
      local state = watch.get_state()
      assert.are.same({}, state)
    end)

    it("should return watcher state", function()
      local script = { name = "test", filename = "test.sh" }
      watch.start("test", script, { patterns = { "*.lua" } }, test_root)

      local state = watch.get_state()
      assert.is_not_nil(state["test"])
      assert.is_true(state["test"].enabled)
      assert.is_true(state["test"].handle_count > 0)
      assert.are.equal(test_root, state["test"].root_dir)
    end)
  end)

  describe("set_execute_callback", function()
    it("should accept a callback function", function()
      local called = false
      watch.set_execute_callback(function()
        called = true
      end)
      -- Just verify it doesn't error
      assert.is_false(called)
    end)
  end)

  describe("set_debug_log", function()
    it("should accept a log function", function()
      watch.set_debug_log(function() end)
      -- Should not error
    end)

    it("should accept nil to reset", function()
      watch.set_debug_log(nil)
      -- Should not error
    end)
  end)

  describe("default_watch_config", function()
    it("should have expected defaults", function()
      local defaults = watch._default_watch_config
      assert.is_false(defaults.enabled)
      assert.is_table(defaults.patterns)
      assert.are.equal(0, #defaults.patterns)
      assert.is_table(defaults.exclude)
      assert.is_true(#defaults.exclude > 0)
      assert.are.equal(500, defaults.debounce)
    end)
  end)
end)

describe("termlet watch integration", function()
  local termlet

  before_each(function()
    -- Clear cached modules
    package.loaded["termlet"] = nil
    package.loaded["termlet.watch"] = nil
    termlet = require("termlet")
  end)

  after_each(function()
    if termlet.stop_all_watches then
      termlet.stop_all_watches()
    end
    termlet.close_all_terminals()
  end)

  describe("setup", function()
    it("should accept watch configuration", function()
      termlet.setup({
        scripts = {},
        watch = {
          debounce = 300,
          exclude = { "vendor" },
        },
      })
      assert.is_not_nil(termlet)
    end)

    it("should initialize with default watch config", function()
      termlet.setup({
        scripts = {},
      })
      assert.is_not_nil(termlet)
    end)
  end)

  describe("start_watch", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      termlet.stop_all_watches()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return false without script name", function()
      termlet.setup({ scripts = {} })
      local result = termlet.start_watch(nil)
      assert.is_false(result)
    end)

    it("should return false for unknown script", function()
      termlet.setup({ scripts = {} })
      local result = termlet.start_watch("nonexistent")
      assert.is_false(result)
    end)

    it("should return false when no watch patterns configured", function()
      termlet.setup({
        root_dir = test_root,
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })
      local result = termlet.start_watch("build")
      assert.is_false(result)
    end)

    it("should start watching when properly configured", function()
      termlet.setup({
        root_dir = test_root,
        scripts = {
          {
            name = "test",
            filename = "test.sh",
            watch = {
              patterns = { "*.lua" },
            },
          },
        },
      })

      local result = termlet.start_watch("test")
      assert.is_true(result)
      assert.is_true(termlet.is_watching("test"))
    end)

    it("should return false when no root_dir available", function()
      termlet.setup({
        scripts = {
          {
            name = "test",
            filename = "test.sh",
            watch = {
              patterns = { "*.lua" },
            },
          },
        },
      })
      local result = termlet.start_watch("test")
      assert.is_false(result)
    end)
  end)

  describe("stop_watch", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      termlet.stop_all_watches()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should stop an active watcher", function()
      termlet.setup({
        root_dir = test_root,
        scripts = {
          {
            name = "test",
            filename = "test.sh",
            watch = { patterns = { "*.lua" } },
          },
        },
      })

      termlet.start_watch("test")
      assert.is_true(termlet.is_watching("test"))

      termlet.stop_watch("test")
      assert.is_false(termlet.is_watching("test"))
    end)

    it("should not error on unwatched script", function()
      termlet.setup({ scripts = {} })
      termlet.stop_watch("nonexistent")
      -- Should not error
    end)
  end)

  describe("toggle_watch", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      termlet.stop_all_watches()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return false without script name", function()
      termlet.setup({ scripts = {} })
      local result = termlet.toggle_watch(nil)
      assert.is_false(result)
    end)

    it("should enable then disable watch", function()
      termlet.setup({
        root_dir = test_root,
        scripts = {
          {
            name = "test",
            filename = "test.sh",
            watch = { patterns = { "*.lua" } },
          },
        },
      })

      -- Toggle on
      local result = termlet.toggle_watch("test")
      assert.is_true(result)
      assert.is_true(termlet.is_watching("test"))

      -- Toggle off
      result = termlet.toggle_watch("test")
      assert.is_false(result)
      assert.is_false(termlet.is_watching("test"))
    end)
  end)

  describe("is_watching", function()
    it("should return false for unknown script", function()
      termlet.setup({ scripts = {} })
      assert.is_false(termlet.is_watching("nonexistent"))
    end)
  end)

  describe("get_watched_scripts", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      termlet.stop_all_watches()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should return empty list when nothing watched", function()
      termlet.setup({ scripts = {} })
      local scripts = termlet.get_watched_scripts()
      assert.are.equal(0, #scripts)
    end)

    it("should return list of watched scripts", function()
      termlet.setup({
        root_dir = test_root,
        scripts = {
          {
            name = "build",
            filename = "build.sh",
            watch = { patterns = { "*.lua" } },
          },
          {
            name = "test",
            filename = "test.sh",
            watch = { patterns = { "*.py" } },
          },
        },
      })

      termlet.start_watch("build")
      termlet.start_watch("test")

      local scripts = termlet.get_watched_scripts()
      assert.are.equal(2, #scripts)
    end)
  end)

  describe("stop_all_watches", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should stop all watchers", function()
      termlet.setup({
        root_dir = test_root,
        scripts = {
          {
            name = "build",
            filename = "build.sh",
            watch = { patterns = { "*.lua" } },
          },
          {
            name = "test",
            filename = "test.sh",
            watch = { patterns = { "*.py" } },
          },
        },
      })

      termlet.start_watch("build")
      termlet.start_watch("test")
      assert.are.equal(2, #termlet.get_watched_scripts())

      termlet.stop_all_watches()
      assert.are.equal(0, #termlet.get_watched_scripts())
    end)

    it("should not error when no watchers active", function()
      termlet.setup({ scripts = {} })
      termlet.stop_all_watches()
      -- Should not error
    end)
  end)

  describe("watch module access", function()
    it("should expose watch module", function()
      termlet.setup({ scripts = {} })
      assert.is_not_nil(termlet.watch)
      assert.is_function(termlet.watch.start)
      assert.is_function(termlet.watch.stop)
      assert.is_function(termlet.watch.is_watching)
    end)
  end)

  describe("watch config merging", function()
    local test_root

    before_each(function()
      test_root = vim.fn.tempname()
      vim.fn.mkdir(test_root, "p")
    end)

    after_each(function()
      termlet.stop_all_watches()
      if test_root and vim.fn.isdirectory(test_root) == 1 then
        vim.fn.delete(test_root, "rf")
      end
    end)

    it("should merge global and script watch configs", function()
      termlet.setup({
        root_dir = test_root,
        scripts = {
          {
            name = "test",
            filename = "test.sh",
            watch = {
              patterns = { "*.lua" },
              debounce = 300,
            },
          },
        },
        watch = {
          debounce = 500,
          exclude = { "vendor" },
        },
      })

      termlet.start_watch("test")
      local cfg = termlet.watch.get_watch_config("test")
      assert.is_not_nil(cfg)
      -- Script-level debounce should override global
      assert.are.equal(300, cfg.debounce)
      assert.are.same({ "*.lua" }, cfg.patterns)
    end)

    it("should use script root_dir over global", function()
      local script_root = vim.fn.tempname()
      vim.fn.mkdir(script_root, "p")

      termlet.setup({
        root_dir = test_root,
        scripts = {
          {
            name = "test",
            filename = "test.sh",
            root_dir = script_root,
            watch = { patterns = { "*.lua" } },
          },
        },
      })

      termlet.start_watch("test")
      local state = termlet.watch.get_state()
      assert.is_not_nil(state["test"])
      assert.are.equal(script_root, state["test"].root_dir)

      vim.fn.delete(script_root, "rf")
    end)
  end)
end)
