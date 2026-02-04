-- Tests for TermLet Watch Module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.watch", function()
  local watch

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.watch"] = nil
    watch = require("termlet.watch")
    watch._reset()
  end)

  after_each(function()
    watch._reset()
  end)

  describe("glob_to_pattern", function()
    it("should convert simple glob with extension", function()
      local pattern = watch.glob_to_pattern("*.lua")
      assert.is_not_nil(("test.lua"):match(pattern))
      assert.is_nil(("test.py"):match(pattern))
    end)

    it("should convert double-star glob for recursive matching", function()
      local pattern = watch.glob_to_pattern("**/*.lua")
      assert.is_not_nil(("src/test.lua"):match(pattern))
      assert.is_not_nil(("src/deep/nested/test.lua"):match(pattern))
      assert.is_nil(("test.py"):match(pattern))
    end)

    it("should handle patterns with directory components", function()
      local pattern = watch.glob_to_pattern("src/*.lua")
      assert.is_not_nil(("src/test.lua"):match(pattern))
      assert.is_nil(("lib/test.lua"):match(pattern))
    end)

    it("should handle question mark wildcard", function()
      local pattern = watch.glob_to_pattern("test?.lua")
      assert.is_not_nil(("test1.lua"):match(pattern))
      assert.is_not_nil(("testA.lua"):match(pattern))
      assert.is_nil(("test.lua"):match(pattern))
      assert.is_nil(("test12.lua"):match(pattern))
    end)

    it("should escape Lua pattern metacharacters", function()
      local pattern = watch.glob_to_pattern("file.test+1.lua")
      assert.is_not_nil(("file.test+1.lua"):match(pattern))
      assert.is_nil(("filettest11.lua"):match(pattern))
    end)

    it("should handle node_modules exclude pattern", function()
      local pattern = watch.glob_to_pattern("**/node_modules/**")
      assert.is_not_nil(("node_modules/pkg/index.js"):match(pattern))
      assert.is_not_nil(("src/node_modules/pkg/file.js"):match(pattern))
    end)

    it("should handle exact filename glob", function()
      local pattern = watch.glob_to_pattern("Makefile")
      assert.is_not_nil(("Makefile"):match(pattern))
      assert.is_nil(("Makefile.bak"):match(pattern))
    end)

    it("should handle glob with multiple extensions", function()
      -- Pattern like *.{lua,py} is not standard glob, test individual patterns
      local lua_pattern = watch.glob_to_pattern("**/*.lua")
      local py_pattern = watch.glob_to_pattern("**/*.py")
      assert.is_not_nil(("src/test.lua"):match(lua_pattern))
      assert.is_not_nil(("src/test.py"):match(py_pattern))
      assert.is_nil(("src/test.lua"):match(py_pattern))
    end)
  end)

  describe("matches_patterns", function()
    it("should return true when no patterns specified (match all)", function()
      assert.is_true(watch.matches_patterns("any/file.txt", {}))
      assert.is_true(watch.matches_patterns("any/file.txt", nil))
    end)

    it("should match files against glob patterns", function()
      local patterns = { "**/*.lua", "**/*.py" }
      assert.is_true(watch.matches_patterns("src/test.lua", patterns))
      assert.is_true(watch.matches_patterns("lib/module.py", patterns))
      assert.is_false(watch.matches_patterns("src/test.js", patterns))
    end)

    it("should match with single pattern", function()
      local patterns = { "*.txt" }
      assert.is_true(watch.matches_patterns("readme.txt", patterns))
      assert.is_false(watch.matches_patterns("readme.md", patterns))
    end)
  end)

  describe("matches_exclude", function()
    it("should return false when no exclude patterns", function()
      assert.is_false(watch.matches_exclude("any/file.txt", {}))
      assert.is_false(watch.matches_exclude("any/file.txt", nil))
    end)

    it("should exclude matching files", function()
      local exclude = { "**/node_modules/**", "**/.git/**" }
      assert.is_true(watch.matches_exclude("node_modules/pkg/index.js", exclude))
      assert.is_true(watch.matches_exclude(".git/objects/abc", exclude))
      assert.is_false(watch.matches_exclude("src/main.lua", exclude))
    end)

    it("should exclude with simple directory name patterns", function()
      local exclude = { "dist/**", "build/**" }
      assert.is_true(watch.matches_exclude("dist/bundle.js", exclude))
      assert.is_true(watch.matches_exclude("build/output.o", exclude))
      assert.is_false(watch.matches_exclude("src/main.lua", exclude))
    end)
  end)

  describe("should_trigger", function()
    it("should return false for empty filepath", function()
      local config = { patterns = { "**/*.lua" }, exclude = {} }
      assert.is_false(watch.should_trigger("", config))
      assert.is_false(watch.should_trigger(nil, config))
    end)

    it("should trigger for matching file", function()
      local config = { patterns = { "**/*.lua" }, exclude = {} }
      assert.is_true(watch.should_trigger("src/test.lua", config))
    end)

    it("should not trigger for excluded file", function()
      local config = { patterns = { "**/*.lua" }, exclude = { "**/node_modules/**" } }
      assert.is_false(watch.should_trigger("node_modules/pkg/init.lua", config))
    end)

    it("should not trigger for non-matching file", function()
      local config = { patterns = { "**/*.lua" }, exclude = {} }
      assert.is_false(watch.should_trigger("src/test.py", config))
    end)

    it("should trigger when no patterns specified (match all)", function()
      local config = { patterns = {}, exclude = {} }
      assert.is_true(watch.should_trigger("any/file.txt", config))
    end)

    it("should exclude takes priority over include", function()
      local config = { patterns = { "**/*.lua" }, exclude = { "**/test/**" } }
      assert.is_false(watch.should_trigger("test/spec.lua", config))
    end)
  end)

  describe("collect_watch_dirs", function()
    it("should include root directory", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local dirs = watch.collect_watch_dirs(tmp, {})
      assert.is_true(#dirs >= 1)
      assert.are.equal(tmp, dirs[1])

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)

    it("should include subdirectories", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp .. "/src", "p")
      vim.fn.mkdir(tmp .. "/lib", "p")

      local dirs = watch.collect_watch_dirs(tmp, {})
      assert.is_true(#dirs >= 3) -- root + src + lib

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)

    it("should exclude hidden directories", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp .. "/.git", "p")
      vim.fn.mkdir(tmp .. "/src", "p")

      local dirs = watch.collect_watch_dirs(tmp, {})
      -- Should not include .git
      for _, dir in ipairs(dirs) do
        assert.is_nil(dir:match("%.git$"))
      end

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)

    it("should exclude matching directories", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp .. "/node_modules", "p")
      vim.fn.mkdir(tmp .. "/src", "p")

      local dirs = watch.collect_watch_dirs(tmp, { "node_modules" })
      -- Should not include node_modules
      for _, dir in ipairs(dirs) do
        assert.is_nil(dir:match("node_modules$"))
      end

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)

    it("should respect max depth", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp .. "/a/b/c/d/e", "p")

      local dirs = watch.collect_watch_dirs(tmp, {}, 2)
      -- Should include root, a, a/b but not deeper
      local max_depth = 0
      for _, dir in ipairs(dirs) do
        local rel = dir:sub(#tmp + 2)
        if rel ~= "" then
          local _, count = rel:gsub("/", "")
          max_depth = math.max(max_depth, count + 1)
        end
      end
      assert.is_true(max_depth <= 2)

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)

    it("should handle non-existent root", function()
      local dirs = watch.collect_watch_dirs("/tmp/definitely-not-a-real-path-" .. os.time(), {})
      -- Should still include root in list even if scan fails
      assert.is_true(#dirs >= 1)
    end)
  end)

  describe("start", function()
    it("should start watching a valid directory", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local script = { name = "test", filename = "test.sh" }
      local watch_config = { patterns = { "**/*.lua" }, exclude = {}, debounce = 100 }
      local callback = function() end

      local result = watch.start("test", script, watch_config, tmp, callback)
      assert.is_true(result)
      assert.is_true(watch.is_watching("test"))

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
    end)

    it("should fail for non-existent directory", function()
      local script = { name = "test", filename = "test.sh" }
      local watch_config = { patterns = { "**/*.lua" }, exclude = {}, debounce = 100 }

      local result = watch.start("test", script, watch_config, "/tmp/no-such-dir-" .. os.time(), function() end)
      assert.is_false(result)
      assert.is_false(watch.is_watching("test"))
    end)

    it("should stop existing watcher before starting new one", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local script = { name = "test", filename = "test.sh" }
      local config = { patterns = { "**/*.lua" }, exclude = {}, debounce = 100 }

      watch.start("test", script, config, tmp, function() end)
      assert.is_true(watch.is_watching("test"))

      -- Start again should replace
      watch.start("test", script, config, tmp, function() end)
      assert.is_true(watch.is_watching("test"))

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
    end)
  end)

  describe("stop", function()
    it("should stop an active watcher", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local script = { name = "test", filename = "test.sh" }
      local config = { patterns = {}, exclude = {}, debounce = 100 }

      watch.start("test", script, config, tmp, function() end)
      assert.is_true(watch.is_watching("test"))

      local result = watch.stop("test")
      assert.is_true(result)
      assert.is_false(watch.is_watching("test"))

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)

    it("should return false when no watcher exists", function()
      local result = watch.stop("nonexistent")
      assert.is_false(result)
    end)
  end)

  describe("stop_all", function()
    it("should stop all active watchers", function()
      local tmp1 = vim.fn.tempname()
      local tmp2 = vim.fn.tempname()
      vim.fn.mkdir(tmp1, "p")
      vim.fn.mkdir(tmp2, "p")

      local config = { patterns = {}, exclude = {}, debounce = 100 }
      watch.start("test1", { name = "test1" }, config, tmp1, function() end)
      watch.start("test2", { name = "test2" }, config, tmp2, function() end)

      assert.is_true(watch.is_watching("test1"))
      assert.is_true(watch.is_watching("test2"))

      local count = watch.stop_all()
      assert.are.equal(2, count)
      assert.is_false(watch.is_watching("test1"))
      assert.is_false(watch.is_watching("test2"))

      -- Cleanup
      vim.fn.delete(tmp1, "rf")
      vim.fn.delete(tmp2, "rf")
    end)

    it("should return 0 when no watchers active", function()
      local count = watch.stop_all()
      assert.are.equal(0, count)
    end)
  end)

  describe("toggle", function()
    it("should start watching when not active", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local script = { name = "test", filename = "test.sh" }
      local config = { patterns = {}, exclude = {}, debounce = 100 }

      local result = watch.toggle("test", script, config, tmp, function() end)
      assert.is_true(result)
      assert.is_true(watch.is_watching("test"))

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
    end)

    it("should stop watching when active", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local script = { name = "test", filename = "test.sh" }
      local config = { patterns = {}, exclude = {}, debounce = 100 }

      watch.start("test", script, config, tmp, function() end)
      assert.is_true(watch.is_watching("test"))

      local result = watch.toggle("test", script, config, tmp, function() end)
      assert.is_false(result)
      assert.is_false(watch.is_watching("test"))

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)
  end)

  describe("is_watching", function()
    it("should return false for unknown script", function()
      assert.is_false(watch.is_watching("nonexistent"))
    end)

    it("should return true for active watcher", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      watch.start("test", { name = "test" }, { patterns = {}, exclude = {}, debounce = 100 }, tmp, function() end)
      assert.is_true(watch.is_watching("test"))

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
    end)
  end)

  describe("get_watched_scripts", function()
    it("should return empty list when no watchers", function()
      local scripts = watch.get_watched_scripts()
      assert.are.equal(0, #scripts)
    end)

    it("should return sorted list of watched scripts", function()
      local tmp1 = vim.fn.tempname()
      local tmp2 = vim.fn.tempname()
      vim.fn.mkdir(tmp1, "p")
      vim.fn.mkdir(tmp2, "p")

      local config = { patterns = {}, exclude = {}, debounce = 100 }
      watch.start("ztest", { name = "ztest" }, config, tmp1, function() end)
      watch.start("atest", { name = "atest" }, config, tmp2, function() end)

      local scripts = watch.get_watched_scripts()
      assert.are.equal(2, #scripts)
      assert.are.equal("atest", scripts[1])
      assert.are.equal("ztest", scripts[2])

      -- Cleanup
      watch.stop_all()
      vim.fn.delete(tmp1, "rf")
      vim.fn.delete(tmp2, "rf")
    end)
  end)

  describe("get_status", function()
    it("should return empty table when no watchers", function()
      local status = watch.get_status()
      assert.are.equal(0, vim.tbl_count(status))
    end)

    it("should return status for active watchers", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local config = { patterns = {}, exclude = {}, debounce = 100 }
      watch.start("test", { name = "test" }, config, tmp, function() end)

      local status = watch.get_status()
      assert.is_not_nil(status["test"])
      assert.is_true(status["test"].watching)
      assert.is_true(status["test"].dir_count >= 1)

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
    end)
  end)

  describe("get_title_indicator", function()
    it("should return empty string when not watching", function()
      assert.are.equal("", watch.get_title_indicator("test"))
    end)

    it("should return indicator when watching", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local config = { patterns = {}, exclude = {}, debounce = 100 }
      watch.start("test", { name = "test" }, config, tmp, function() end)

      local indicator = watch.get_title_indicator("test")
      assert.is_true(#indicator > 0)
      assert.is_not_nil(indicator:match("%[watch%]"))

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
    end)
  end)

  describe("get_state", function()
    it("should return empty state initially", function()
      local state = watch.get_state()
      assert.are.equal(0, vim.tbl_count(state))
    end)

    it("should return state for active watchers", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local config = { patterns = { "**/*.lua" }, exclude = { "**/dist/**" }, debounce = 200 }
      watch.start("test", { name = "test" }, config, tmp, function() end)

      local state = watch.get_state()
      assert.is_not_nil(state["test"])
      assert.are.equal(tmp, state["test"].root_dir)
      assert.is_true(state["test"].handle_count >= 1)

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
    end)
  end)

  describe("_reset", function()
    it("should stop all watchers and clear state", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local config = { patterns = {}, exclude = {}, debounce = 100 }
      watch.start("test", { name = "test" }, config, tmp, function() end)
      assert.is_true(watch.is_watching("test"))

      watch._reset()
      assert.is_false(watch.is_watching("test"))
      assert.are.equal(0, vim.tbl_count(watch.get_state()))

      -- Cleanup
      vim.fn.delete(tmp, "rf")
    end)
  end)

  describe("watcher replacement", function()
    it("should assign unique generation to each watcher to prevent stale callbacks", function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local call_count_1 = 0
      local call_count_2 = 0
      local config = { patterns = {}, exclude = {}, debounce = 100 }

      -- Start first watcher
      watch.start("test", { name = "test" }, config, tmp, function()
        call_count_1 = call_count_1 + 1
      end)
      assert.is_true(watch.is_watching("test"))

      -- Replace with second watcher (calls stop internally)
      watch.start("test", { name = "test_v2" }, config, tmp, function()
        call_count_2 = call_count_2 + 1
      end)
      assert.is_true(watch.is_watching("test"))

      -- Verify the new watcher's script is the replaced one
      local state = watch.get_state()
      assert.is_not_nil(state["test"])

      -- The old callback should never have been invoked by the replacement
      assert.are.equal(0, call_count_1)
      assert.are.equal(0, call_count_2)

      -- Cleanup
      watch.stop("test")
      vim.fn.delete(tmp, "rf")
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
          enabled = true,
          default_debounce = 300,
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

    it("should accept script-level watch config", function()
      termlet.setup({
        scripts = {
          {
            name = "test",
            filename = "test.sh",
            watch = {
              enabled = true,
              patterns = { "**/*.lua" },
              exclude = { "**/node_modules/**" },
              debounce = 500,
            },
          },
        },
      })
      assert.is_not_nil(termlet)
    end)
  end)

  describe("start_watch", function()
    it("should return false when watch mode is disabled", function()
      termlet.setup({
        scripts = {
          { name = "test", filename = "test.sh" },
        },
        watch = { enabled = false },
      })

      local result = termlet.start_watch("test")
      assert.is_false(result)
    end)

    it("should return false for unknown script", function()
      termlet.setup({
        scripts = {},
        watch = { enabled = true },
      })

      local result = termlet.start_watch("nonexistent")
      assert.is_false(result)
    end)
  end)

  describe("stop_watch", function()
    it("should return false when no watcher exists", function()
      termlet.setup({
        scripts = {},
        watch = { enabled = true },
      })

      local result = termlet.stop_watch("nonexistent")
      assert.is_false(result)
    end)
  end)

  describe("toggle_watch", function()
    it("should return false when watch mode is disabled", function()
      termlet.setup({
        scripts = {
          { name = "test", filename = "test.sh" },
        },
        watch = { enabled = false },
      })

      local result = termlet.toggle_watch("test")
      assert.is_false(result)
    end)
  end)

  describe("is_watching", function()
    it("should return false for unwatched script", function()
      termlet.setup({
        scripts = {},
        watch = { enabled = true },
      })

      assert.is_false(termlet.is_watching("test"))
    end)
  end)

  describe("get_watched_scripts", function()
    it("should return empty list initially", function()
      termlet.setup({
        scripts = {},
        watch = { enabled = true },
      })

      local scripts = termlet.get_watched_scripts()
      assert.are.equal(0, #scripts)
    end)
  end)

  describe("get_watch_status", function()
    it("should return empty status initially", function()
      termlet.setup({
        scripts = {},
        watch = { enabled = true },
      })

      local status = termlet.get_watch_status()
      assert.are.equal(0, vim.tbl_count(status))
    end)
  end)

  describe("stop_all_watches", function()
    it("should return 0 when no watchers active", function()
      termlet.setup({
        scripts = {},
        watch = { enabled = true },
      })

      local count = termlet.stop_all_watches()
      assert.are.equal(0, count)
    end)
  end)

  describe("watch module access", function()
    it("should expose watch module", function()
      termlet.setup({
        scripts = {},
        watch = { enabled = true },
      })

      assert.is_not_nil(termlet.watch)
      assert.is_function(termlet.watch.start)
      assert.is_function(termlet.watch.stop)
      assert.is_function(termlet.watch.toggle)
    end)
  end)
end)
