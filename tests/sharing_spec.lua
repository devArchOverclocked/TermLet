-- Tests for TermLet Sharing Module (Export/Import)
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.sharing", function()
  local sharing

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.sharing"] = nil
    sharing = require("termlet.sharing")
  end)

  -- =========================================================================
  -- Sensitive field detection
  -- =========================================================================

  describe("_is_sensitive_field", function()
    it("should identify sensitive fields", function()
      local sensitive = { "root_dir", "cmd", "on_stdout" }
      assert.is_true(sharing._is_sensitive_field("root_dir", sensitive))
      assert.is_true(sharing._is_sensitive_field("cmd", sensitive))
      assert.is_true(sharing._is_sensitive_field("on_stdout", sensitive))
    end)

    it("should not flag non-sensitive fields", function()
      local sensitive = { "root_dir", "cmd" }
      assert.is_false(sharing._is_sensitive_field("name", sensitive))
      assert.is_false(sharing._is_sensitive_field("filename", sensitive))
      assert.is_false(sharing._is_sensitive_field("description", sensitive))
    end)

    it("should handle empty sensitive list", function()
      assert.is_false(sharing._is_sensitive_field("root_dir", {}))
    end)
  end)

  -- =========================================================================
  -- Script filtering
  -- =========================================================================

  describe("_filter_script", function()
    it("should copy simple fields", function()
      local script = { name = "test", filename = "test.sh" }
      local result = sharing._filter_script(script, false, {})
      assert.are.equal("test", result.name)
      assert.are.equal("test.sh", result.filename)
    end)

    it("should exclude sensitive fields when requested", function()
      local script = {
        name = "test",
        filename = "test.sh",
        root_dir = "/secret/path",
        cmd = "./custom.sh",
      }
      local result = sharing._filter_script(script, true, { "root_dir", "cmd" })
      assert.are.equal("test", result.name)
      assert.are.equal("test.sh", result.filename)
      assert.is_nil(result.root_dir)
      assert.is_nil(result.cmd)
    end)

    it("should keep sensitive fields when not excluded", function()
      local script = {
        name = "test",
        filename = "test.sh",
        root_dir = "/path",
      }
      local result = sharing._filter_script(script, false, { "root_dir" })
      assert.are.equal("/path", result.root_dir)
    end)

    it("should skip function values", function()
      local script = {
        name = "test",
        filename = "test.sh",
        on_stdout = function() end,
      }
      local result = sharing._filter_script(script, false, {})
      assert.are.equal("test", result.name)
      assert.is_nil(result.on_stdout)
    end)

    it("should deep copy nested tables", function()
      local script = {
        name = "test",
        filters = {
          enabled = true,
          show_only = { "ERROR" },
        },
      }
      local result = sharing._filter_script(script, false, {})
      assert.are.equal(true, result.filters.enabled)
      assert.are.equal("ERROR", result.filters.show_only[1])
    end)
  end)

  -- =========================================================================
  -- Lua serializer
  -- =========================================================================

  describe("_serialize_lua", function()
    it("should serialize strings", function()
      local result = sharing._serialize_lua("hello")
      assert.is_truthy(result:find("hello"))
    end)

    it("should serialize numbers", function()
      assert.are.equal("42", sharing._serialize_lua(42))
      assert.are.equal("3.14", sharing._serialize_lua(3.14))
    end)

    it("should serialize booleans", function()
      assert.are.equal("true", sharing._serialize_lua(true))
      assert.are.equal("false", sharing._serialize_lua(false))
    end)

    it("should serialize nil", function()
      assert.are.equal("nil", sharing._serialize_lua(nil))
    end)

    it("should serialize empty tables", function()
      assert.are.equal("{}", sharing._serialize_lua({}))
    end)

    it("should serialize arrays", function()
      local result = sharing._serialize_lua({ "a", "b", "c" })
      assert.is_truthy(result:find('"a"'))
      assert.is_truthy(result:find('"b"'))
      assert.is_truthy(result:find('"c"'))
    end)

    it("should serialize dictionaries with sorted keys", function()
      local result = sharing._serialize_lua({ name = "test", filename = "test.sh" })
      assert.is_truthy(result:find("name"))
      assert.is_truthy(result:find("filename"))
    end)

    it("should handle nested tables", function()
      local input = {
        scripts = {
          { name = "build" },
        },
      }
      local result = sharing._serialize_lua(input)
      assert.is_truthy(result:find("scripts"))
      assert.is_truthy(result:find("build"))
    end)

    it("should escape special characters in strings", function()
      local result = sharing._serialize_lua('hello "world"')
      -- %q escaping should handle quotes
      assert.is_truthy(result:find("hello"))
    end)
  end)

  -- =========================================================================
  -- JSON pretty printing
  -- =========================================================================

  describe("_pretty_print_json", function()
    it("should produce multi-line output for objects", function()
      local compact = '{"name":"test","version":1}'
      local pretty = sharing._pretty_print_json(compact)
      assert.is_truthy(pretty:find("\n"))
    end)

    it("should indent nested structures", function()
      local compact = '{"scripts":[{"name":"build"}]}'
      local pretty = sharing._pretty_print_json(compact)
      assert.is_truthy(pretty:find("\n"))
      assert.is_truthy(pretty:find("  "))
    end)

    it("should preserve string content with special characters", function()
      local compact = '{"name":"hello \\"world\\""}'
      local pretty = sharing._pretty_print_json(compact)
      assert.is_truthy(pretty:find("hello"))
    end)
  end)

  -- =========================================================================
  -- Format detection
  -- =========================================================================

  describe("_detect_format", function()
    it("should detect JSON format", function()
      assert.are.equal("json", sharing._detect_format("config.json"))
    end)

    it("should detect Lua format", function()
      assert.are.equal("lua", sharing._detect_format("config.lua"))
    end)

    it("should default to JSON for unknown extensions", function()
      assert.are.equal("json", sharing._detect_format("config.yaml"))
      assert.are.equal("json", sharing._detect_format("config.txt"))
      assert.are.equal("json", sharing._detect_format("config"))
    end)
  end)

  -- =========================================================================
  -- Export config
  -- =========================================================================

  describe("export_config", function()
    local sample_scripts = {
      {
        name = "build",
        filename = "build.sh",
        description = "Build the project",
      },
      {
        name = "test",
        filename = "test.sh",
        description = "Run tests",
        depends_on = { "build" },
      },
    }

    it("should export to JSON format", function()
      local content, err = sharing.export_config(sample_scripts, { format = "json" })
      assert.is_nil(err)
      assert.is_not_nil(content)

      -- Should be valid JSON
      local decoded = vim.fn.json_decode(content)
      assert.is_not_nil(decoded)
      assert.is_not_nil(decoded.scripts)
      assert.are.equal(2, #decoded.scripts)
      assert.are.equal("build", decoded.scripts[1].name)
    end)

    it("should export to Lua format", function()
      local content, err = sharing.export_config(sample_scripts, { format = "lua" })
      assert.is_nil(err)
      assert.is_not_nil(content)
      assert.is_truthy(content:find("^return"))
      assert.is_truthy(content:find("build"))
      assert.is_truthy(content:find("test"))
    end)

    it("should include version field", function()
      local content, err = sharing.export_config(sample_scripts, { format = "json" })
      assert.is_nil(err)
      local decoded = vim.fn.json_decode(content)
      assert.are.equal(1, decoded.version)
    end)

    it("should exclude sensitive fields by default", function()
      local scripts = {
        {
          name = "build",
          filename = "build.sh",
          root_dir = "/secret/path",
          cmd = "./custom.sh",
        },
      }
      local content, err = sharing.export_config(scripts, { format = "json" })
      assert.is_nil(err)
      local decoded = vim.fn.json_decode(content)
      assert.is_nil(decoded.scripts[1].root_dir)
      assert.is_nil(decoded.scripts[1].cmd)
    end)

    it("should include sensitive fields when exclude_sensitive is false", function()
      local scripts = {
        {
          name = "build",
          filename = "build.sh",
          root_dir = "/my/path",
        },
      }
      local content, err = sharing.export_config(scripts, { format = "json", exclude_sensitive = false })
      assert.is_nil(err)
      local decoded = vim.fn.json_decode(content)
      assert.are.equal("/my/path", decoded.scripts[1].root_dir)
    end)

    it("should reject unsupported formats", function()
      local content, err = sharing.export_config(sample_scripts, { format = "yaml" })
      assert.is_nil(content)
      assert.is_truthy(err:find("Unsupported"))
    end)

    it("should reject nil scripts", function()
      local content, err = sharing.export_config(nil, { format = "json" })
      assert.is_nil(content)
      assert.is_truthy(err:find("No scripts"))
    end)

    it("should reject empty scripts list", function()
      local content, err = sharing.export_config({}, { format = "json" })
      assert.is_nil(content)
      assert.is_truthy(err:find("No scripts"))
    end)

    it("should strip function values from scripts", function()
      local scripts = {
        {
          name = "build",
          filename = "build.sh",
          on_stdout = function() end,
        },
      }
      local content, err = sharing.export_config(scripts, { format = "json", exclude_sensitive = false })
      assert.is_nil(err)
      local decoded = vim.fn.json_decode(content)
      assert.is_nil(decoded.scripts[1].on_stdout)
    end)

    it("should preserve depends_on in exports", function()
      local content, err = sharing.export_config(sample_scripts, { format = "json" })
      assert.is_nil(err)
      local decoded = vim.fn.json_decode(content)
      assert.is_not_nil(decoded.scripts[2].depends_on)
      assert.are.equal("build", decoded.scripts[2].depends_on[1])
    end)

    it("should preserve description in exports", function()
      local content, err = sharing.export_config(sample_scripts, { format = "json" })
      assert.is_nil(err)
      local decoded = vim.fn.json_decode(content)
      assert.are.equal("Build the project", decoded.scripts[1].description)
    end)

    it("should use custom sensitive fields", function()
      local scripts = {
        {
          name = "build",
          filename = "build.sh",
          description = "secret desc",
          root_dir = "/path",
        },
      }
      local content, err = sharing.export_config(scripts, {
        format = "json",
        exclude_sensitive = true,
        sensitive_fields = { "description" },
      })
      assert.is_nil(err)
      local decoded = vim.fn.json_decode(content)
      assert.is_nil(decoded.scripts[1].description)
      assert.are.equal("/path", decoded.scripts[1].root_dir)
    end)
  end)

  -- =========================================================================
  -- Export to file
  -- =========================================================================

  describe("export_to_file", function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should export JSON to file", function()
      local scripts = { { name = "build", filename = "build.sh" } }
      local filepath = tmpdir .. "/config.json"
      local ok, err = sharing.export_to_file(scripts, filepath)
      assert.is_nil(err)
      assert.is_true(ok)
      assert.are.equal(1, vim.fn.filereadable(filepath))

      -- Read and verify content
      local f = io.open(filepath, "r")
      local content = f:read("*a")
      f:close()
      local decoded = vim.fn.json_decode(content)
      assert.are.equal("build", decoded.scripts[1].name)
    end)

    it("should export Lua to file", function()
      local scripts = { { name = "test", filename = "test.sh" } }
      local filepath = tmpdir .. "/config.lua"
      local ok, err = sharing.export_to_file(scripts, filepath)
      assert.is_nil(err)
      assert.is_true(ok)
      assert.are.equal(1, vim.fn.filereadable(filepath))

      -- Read and verify content
      local f = io.open(filepath, "r")
      local content = f:read("*a")
      f:close()
      assert.is_truthy(content:find("return"))
      assert.is_truthy(content:find("test"))
    end)

    it("should auto-detect format from extension", function()
      local scripts = { { name = "build", filename = "build.sh" } }

      -- JSON
      local json_path = tmpdir .. "/config.json"
      local ok1, err1 = sharing.export_to_file(scripts, json_path)
      assert.is_nil(err1)
      assert.is_true(ok1)

      -- Lua
      local lua_path = tmpdir .. "/config.lua"
      local ok2, err2 = sharing.export_to_file(scripts, lua_path)
      assert.is_nil(err2)
      assert.is_true(ok2)
    end)

    it("should default to JSON for unknown extensions", function()
      local scripts = { { name = "build", filename = "build.sh" } }
      local filepath = tmpdir .. "/config.txt"
      local ok, err = sharing.export_to_file(scripts, filepath)
      assert.is_nil(err)
      assert.is_true(ok)

      local f = io.open(filepath, "r")
      local content = f:read("*a")
      f:close()
      -- Should be valid JSON
      local decoded = vim.fn.json_decode(content)
      assert.is_not_nil(decoded)
    end)
  end)

  -- =========================================================================
  -- Parse config
  -- =========================================================================

  describe("parse_config", function()
    it("should parse valid JSON", function()
      local json = vim.fn.json_encode({
        version = 1,
        scripts = { { name = "build", filename = "build.sh" } },
      })
      local data, err = sharing.parse_config(json, "json")
      assert.is_nil(err)
      assert.is_not_nil(data)
      assert.are.equal(1, data.version)
      assert.are.equal("build", data.scripts[1].name)
    end)

    it("should parse valid Lua", function()
      local lua_content = [[return {
        version = 1,
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      }]]
      local data, err = sharing.parse_config(lua_content, "lua")
      assert.is_nil(err)
      assert.is_not_nil(data)
      assert.are.equal(1, data.version)
    end)

    it("should reject invalid JSON", function()
      local data, err = sharing.parse_config("{invalid json}", "json")
      assert.is_nil(data)
      assert.is_truthy(err:find("Invalid JSON"))
    end)

    it("should reject invalid Lua", function()
      local data, err = sharing.parse_config("invalid lua code $$$", "lua")
      assert.is_nil(data)
      assert.is_truthy(err:find("Invalid Lua"))
    end)

    it("should reject Lua that does not return a table", function()
      local data, err = sharing.parse_config('return "not a table"', "lua")
      assert.is_nil(data)
      assert.is_truthy(err:find("must return a table"))
    end)

    it("should reject empty content", function()
      local data, err = sharing.parse_config("", "json")
      assert.is_nil(data)
      assert.is_truthy(err:find("Empty"))
    end)

    it("should reject nil content", function()
      local data, err = sharing.parse_config(nil, "json")
      assert.is_nil(data)
      assert.is_truthy(err:find("Empty"))
    end)

    it("should reject unsupported format", function()
      local data, err = sharing.parse_config("content", "yaml")
      assert.is_nil(data)
      assert.is_truthy(err:find("Unsupported"))
    end)

    -- Sandbox security tests
    it("should sandbox Lua imports against os.execute", function()
      local malicious = 'os.execute("echo pwned") return { scripts = {} }'
      local data, err = sharing.parse_config(malicious, "lua")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should sandbox Lua imports against require", function()
      local malicious = 'local os = require("os") return { scripts = {} }'
      local data, err = sharing.parse_config(malicious, "lua")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should sandbox Lua imports against io.popen", function()
      local malicious = 'io.popen("whoami") return { scripts = {} }'
      local data, err = sharing.parse_config(malicious, "lua")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should sandbox Lua imports against io.open", function()
      local malicious = 'io.open("/etc/passwd", "r") return { scripts = {} }'
      local data, err = sharing.parse_config(malicious, "lua")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should sandbox Lua imports against loadstring", function()
      local malicious = 'loadstring("return 1")() return { scripts = {} }'
      local data, err = sharing.parse_config(malicious, "lua")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should sandbox Lua imports against dofile", function()
      local malicious = 'dofile("/etc/passwd") return { scripts = {} }'
      local data, err = sharing.parse_config(malicious, "lua")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should sandbox Lua imports against rawset on _G", function()
      local malicious = 'rawset(_G, "evil", true) return { scripts = {} }'
      local data, err = sharing.parse_config(malicious, "lua")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should reject Lua bytecode", function()
      -- Lua bytecode starts with \27Lua
      local bytecode = "\27Lua" .. string.rep("\0", 20)
      local data, err = sharing.parse_config(bytecode, "lua")
      assert.is_nil(data)
      assert.is_truthy(err:find("bytecode"))
    end)
  end)

  -- =========================================================================
  -- Validate config
  -- =========================================================================

  describe("validate_config", function()
    it("should accept valid config", function()
      local data = {
        version = 1,
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "test", filename = "test.sh" },
        },
      }
      local valid, err = sharing.validate_config(data)
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject non-table config", function()
      local valid, err = sharing.validate_config("not a table")
      assert.is_false(valid)
      assert.is_truthy(err:find("must be a table"))
    end)

    it("should reject config without scripts", function()
      local valid, err = sharing.validate_config({ version = 1 })
      assert.is_false(valid)
      assert.is_truthy(err:find("missing 'scripts'"))
    end)

    it("should reject non-table scripts", function()
      local valid, err = sharing.validate_config({ scripts = "not a table" })
      assert.is_false(valid)
      assert.is_truthy(err:find("must be a list"))
    end)

    it("should reject script without name", function()
      local valid, err = sharing.validate_config({
        scripts = { { filename = "build.sh" } },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("missing required 'name'"))
    end)

    it("should reject script with empty name", function()
      local valid, err = sharing.validate_config({
        scripts = { { name = "", filename = "build.sh" } },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("invalid 'name'"))
    end)

    it("should reject script without filename or dir_name", function()
      local valid, err = sharing.validate_config({
        scripts = { { name = "build" } },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("must specify"))
    end)

    it("should accept script with dir_name and relative_path", function()
      local valid, err = sharing.validate_config({
        scripts = { { name = "build", dir_name = "project", relative_path = "scripts/build.sh" } },
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject duplicate script names", function()
      local valid, err = sharing.validate_config({
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "build", filename = "build2.sh" },
        },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("Duplicate"))
    end)

    it("should accept scripts with depends_on", function()
      local valid, err = sharing.validate_config({
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "test", filename = "test.sh", depends_on = { "build" } },
        },
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject non-table depends_on", function()
      local valid, err = sharing.validate_config({
        scripts = {
          { name = "test", filename = "test.sh", depends_on = "build" },
        },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("invalid 'depends_on'"))
    end)

    it("should reject non-string dependency entries", function()
      local valid, err = sharing.validate_config({
        scripts = {
          { name = "test", filename = "test.sh", depends_on = { 123 } },
        },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("non%-string dependency"))
    end)

    it("should accept scripts with filters", function()
      local valid, err = sharing.validate_config({
        scripts = {
          {
            name = "build",
            filename = "build.sh",
            filters = { enabled = true, show_only = { "ERROR" } },
          },
        },
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject non-table filters", function()
      local valid, err = sharing.validate_config({
        scripts = {
          { name = "build", filename = "build.sh", filters = "invalid" },
        },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("invalid 'filters'"))
    end)

    it("should reject non-table script entries", function()
      local valid, err = sharing.validate_config({
        scripts = { "not a table" },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("must be a table"))
    end)

    it("should accept config with valid version", function()
      local valid, err = sharing.validate_config({
        version = 1,
        scripts = { { name = "build", filename = "build.sh" } },
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should accept config without version field", function()
      local valid, err = sharing.validate_config({
        scripts = { { name = "build", filename = "build.sh" } },
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject config with non-numeric version", function()
      local valid, err = sharing.validate_config({
        version = "one",
        scripts = { { name = "build", filename = "build.sh" } },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("must be a number"))
    end)

    it("should reject config with unsupported future version", function()
      local valid, err = sharing.validate_config({
        version = 999,
        scripts = { { name = "build", filename = "build.sh" } },
      })
      assert.is_false(valid)
      assert.is_truthy(err:find("not supported"))
    end)
  end)

  -- =========================================================================
  -- Preview import
  -- =========================================================================

  describe("preview_import", function()
    it("should detect new scripts to add", function()
      local existing = { { name = "build", filename = "build.sh" } }
      local imported = { { name = "test", filename = "test.sh" } }
      local preview = sharing.preview_import(existing, imported, "merge")
      assert.are.equal(1, #preview.added)
      assert.are.equal("test", preview.added[1])
      assert.are.equal(0, #preview.updated)
      assert.are.equal(0, #preview.removed)
    end)

    it("should detect updated scripts", function()
      local existing = { { name = "build", filename = "build.sh" } }
      local imported = { { name = "build", filename = "build_v2.sh" } }
      local preview = sharing.preview_import(existing, imported, "merge")
      assert.are.equal(0, #preview.added)
      assert.are.equal(1, #preview.updated)
      assert.are.equal("build", preview.updated[1])
    end)

    it("should detect unchanged scripts", function()
      local existing = { { name = "build", filename = "build.sh" } }
      local imported = { { name = "build", filename = "build.sh" } }
      local preview = sharing.preview_import(existing, imported, "merge")
      assert.are.equal(0, #preview.added)
      assert.are.equal(0, #preview.updated)
      assert.are.equal(1, #preview.unchanged)
    end)

    it("should detect removed scripts in replace mode", function()
      local existing = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh" },
      }
      local imported = { { name = "build", filename = "build.sh" } }
      local preview = sharing.preview_import(existing, imported, "replace")
      assert.are.equal(1, #preview.removed)
      assert.are.equal("test", preview.removed[1])
    end)

    it("should not show removed in merge mode", function()
      local existing = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh" },
      }
      local imported = { { name = "build", filename = "build.sh" } }
      local preview = sharing.preview_import(existing, imported, "merge")
      assert.are.equal(0, #preview.removed)
    end)

    it("should handle empty existing scripts", function()
      local imported = { { name = "build", filename = "build.sh" } }
      local preview = sharing.preview_import({}, imported, "merge")
      assert.are.equal(1, #preview.added)
    end)

    it("should handle nil existing scripts", function()
      local imported = { { name = "build", filename = "build.sh" } }
      local preview = sharing.preview_import(nil, imported, "merge")
      assert.are.equal(1, #preview.added)
    end)

    it("should handle empty import", function()
      local existing = { { name = "build", filename = "build.sh" } }
      local preview = sharing.preview_import(existing, {}, "merge")
      assert.are.equal(0, #preview.added)
      assert.are.equal(0, #preview.updated)
    end)

    it("should default to merge mode", function()
      local preview = sharing.preview_import({}, {})
      assert.are.equal("merge", preview.mode)
    end)
  end)

  -- =========================================================================
  -- Format preview
  -- =========================================================================

  describe("format_preview", function()
    it("should format preview with added scripts", function()
      local preview = {
        added = { "build", "test" },
        updated = {},
        unchanged = {},
        removed = {},
        mode = "merge",
      }
      local text = sharing.format_preview(preview)
      assert.is_truthy(text:find("New scripts to add"))
      assert.is_truthy(text:find("build"))
      assert.is_truthy(text:find("test"))
      assert.is_truthy(text:find("2 change"))
    end)

    it("should format preview with updates", function()
      local preview = {
        added = {},
        updated = { "build" },
        unchanged = {},
        removed = {},
        mode = "merge",
      }
      local text = sharing.format_preview(preview)
      assert.is_truthy(text:find("Scripts to update"))
      assert.is_truthy(text:find("build"))
    end)

    it("should format preview with removed scripts", function()
      local preview = {
        added = {},
        updated = {},
        unchanged = {},
        removed = { "old_script" },
        mode = "replace",
      }
      local text = sharing.format_preview(preview)
      assert.is_truthy(text:find("Scripts to remove"))
      assert.is_truthy(text:find("old_script"))
    end)

    it("should show no changes message", function()
      local preview = {
        added = {},
        updated = {},
        unchanged = { "build" },
        removed = {},
        mode = "merge",
      }
      local text = sharing.format_preview(preview)
      assert.is_truthy(text:find("No changes"))
    end)

    it("should include mode in header", function()
      local preview = {
        added = {},
        updated = {},
        unchanged = {},
        removed = {},
        mode = "replace",
      }
      local text = sharing.format_preview(preview)
      assert.is_truthy(text:find("replace"))
    end)
  end)

  -- =========================================================================
  -- Merge scripts
  -- =========================================================================

  describe("merge_scripts", function()
    it("should merge new scripts into existing", function()
      local existing = { { name = "build", filename = "build.sh" } }
      local imported = { { name = "test", filename = "test.sh" } }
      local result = sharing.merge_scripts(existing, imported, "merge")
      assert.are.equal(2, #result)
      assert.are.equal("build", result[1].name)
      assert.are.equal("test", result[2].name)
    end)

    it("should update existing scripts on merge", function()
      local existing = { { name = "build", filename = "old.sh" } }
      local imported = { { name = "build", filename = "new.sh" } }
      local result = sharing.merge_scripts(existing, imported, "merge")
      assert.are.equal(1, #result)
      assert.are.equal("build", result[1].name)
      assert.are.equal("new.sh", result[1].filename)
    end)

    it("should deep merge script fields on merge", function()
      local existing = {
        {
          name = "build",
          filename = "build.sh",
          root_dir = "/original",
          description = "Original description",
        },
      }
      local imported = {
        {
          name = "build",
          filename = "build_v2.sh",
          description = "Updated description",
        },
      }
      local result = sharing.merge_scripts(existing, imported, "merge")
      assert.are.equal(1, #result)
      assert.are.equal("build_v2.sh", result[1].filename)
      assert.are.equal("Updated description", result[1].description)
      assert.are.equal("/original", result[1].root_dir) -- Preserved from existing
    end)

    it("should replace all scripts in replace mode", function()
      local existing = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh" },
      }
      local imported = { { name = "deploy", filename = "deploy.sh" } }
      local result = sharing.merge_scripts(existing, imported, "replace")
      assert.are.equal(1, #result)
      assert.are.equal("deploy", result[1].name)
    end)

    it("should handle empty existing on merge", function()
      local imported = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh" },
      }
      local result = sharing.merge_scripts({}, imported, "merge")
      assert.are.equal(2, #result)
    end)

    it("should handle nil existing on merge", function()
      local imported = { { name = "build", filename = "build.sh" } }
      local result = sharing.merge_scripts(nil, imported, "merge")
      assert.are.equal(1, #result)
    end)

    it("should create deep copies to avoid reference sharing", function()
      local imported = { { name = "build", filename = "build.sh" } }
      local result = sharing.merge_scripts({}, imported, "merge")
      -- Modify the result and verify original is unchanged
      result[1].name = "modified"
      assert.are.equal("build", imported[1].name)
    end)

    it("should default to merge mode", function()
      local existing = { { name = "build", filename = "build.sh" } }
      local imported = { { name = "test", filename = "test.sh" } }
      local result = sharing.merge_scripts(existing, imported)
      assert.are.equal(2, #result)
    end)
  end)

  -- =========================================================================
  -- Import from file
  -- =========================================================================

  describe("import_from_file", function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should import from JSON file", function()
      local filepath = tmpdir .. "/config.json"
      local content = vim.fn.json_encode({
        version = 1,
        scripts = { { name = "build", filename = "build.sh" } },
      })
      local f = io.open(filepath, "w")
      f:write(content)
      f:close()

      local data, err = sharing.import_from_file(filepath)
      assert.is_nil(err)
      assert.is_not_nil(data)
      assert.are.equal(1, #data.scripts)
      assert.are.equal("build", data.scripts[1].name)
    end)

    it("should import from Lua file", function()
      local filepath = tmpdir .. "/config.lua"
      local content = [[return {
        version = 1,
        scripts = {
          { name = "test", filename = "test.sh" },
        },
      }]]
      local f = io.open(filepath, "w")
      f:write(content)
      f:close()

      local data, err = sharing.import_from_file(filepath)
      assert.is_nil(err)
      assert.is_not_nil(data)
      assert.are.equal("test", data.scripts[1].name)
    end)

    it("should reject non-existent file", function()
      local data, err = sharing.import_from_file("/nonexistent/path/config.json")
      assert.is_nil(data)
      assert.is_truthy(err:find("not found"))
    end)

    it("should reject file with invalid content", function()
      local filepath = tmpdir .. "/bad.json"
      local f = io.open(filepath, "w")
      f:write("{invalid json}")
      f:close()

      local data, err = sharing.import_from_file(filepath)
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should reject file with invalid config structure", function()
      local filepath = tmpdir .. "/invalid.json"
      local content = vim.fn.json_encode({ version = 1 }) -- Missing scripts
      local f = io.open(filepath, "w")
      f:write(content)
      f:close()

      local data, err = sharing.import_from_file(filepath)
      assert.is_nil(data)
      assert.is_truthy(err:find("missing 'scripts'"))
    end)

    it("should allow overriding format detection", function()
      -- Write JSON content but with .txt extension
      local filepath = tmpdir .. "/config.txt"
      local content = vim.fn.json_encode({
        version = 1,
        scripts = { { name = "build", filename = "build.sh" } },
      })
      local f = io.open(filepath, "w")
      f:write(content)
      f:close()

      local data, err = sharing.import_from_file(filepath, { format = "json" })
      assert.is_nil(err)
      assert.is_not_nil(data)
    end)
  end)

  -- =========================================================================
  -- Supported formats
  -- =========================================================================

  describe("get_supported_formats", function()
    it("should return list of supported formats", function()
      local formats = sharing.get_supported_formats()
      assert.is_true(#formats >= 2)
      -- Check both json and lua are present
      local has_json = false
      local has_lua = false
      for _, f in ipairs(formats) do
        if f == "json" then
          has_json = true
        end
        if f == "lua" then
          has_lua = true
        end
      end
      assert.is_true(has_json)
      assert.is_true(has_lua)
    end)
  end)

  describe("get_sensitive_fields", function()
    it("should return default sensitive fields", function()
      local fields = sharing.get_sensitive_fields()
      assert.is_true(#fields > 0)
    end)

    it("should return a copy (not a reference)", function()
      local fields1 = sharing.get_sensitive_fields()
      local fields2 = sharing.get_sensitive_fields()
      fields1[1] = "modified"
      assert.are_not.equal(fields1[1], fields2[1])
    end)
  end)

  -- =========================================================================
  -- Round-trip tests (export then import)
  -- =========================================================================

  describe("round-trip", function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should round-trip JSON export/import", function()
      local scripts = {
        {
          name = "build",
          filename = "build.sh",
          description = "Build project",
        },
        {
          name = "test",
          filename = "test.sh",
          description = "Run tests",
          depends_on = { "build" },
        },
      }

      local filepath = tmpdir .. "/config.json"
      local ok, export_err = sharing.export_to_file(scripts, filepath, { exclude_sensitive = false })
      assert.is_nil(export_err)
      assert.is_true(ok)

      local data, import_err = sharing.import_from_file(filepath)
      assert.is_nil(import_err)
      assert.is_not_nil(data)
      assert.are.equal(2, #data.scripts)
      assert.are.equal("build", data.scripts[1].name)
      assert.are.equal("test", data.scripts[2].name)
      assert.are.equal("Run tests", data.scripts[2].description)
      assert.are.equal("build", data.scripts[2].depends_on[1])
    end)

    it("should round-trip Lua export/import", function()
      local scripts = {
        {
          name = "deploy",
          filename = "deploy.sh",
          description = "Deploy to production",
        },
      }

      local filepath = tmpdir .. "/config.lua"
      local ok, export_err = sharing.export_to_file(scripts, filepath, { exclude_sensitive = false })
      assert.is_nil(export_err)
      assert.is_true(ok)

      local data, import_err = sharing.import_from_file(filepath)
      assert.is_nil(import_err)
      assert.is_not_nil(data)
      assert.are.equal(1, #data.scripts)
      assert.are.equal("deploy", data.scripts[1].name)
      assert.are.equal("Deploy to production", data.scripts[1].description)
    end)

    it("should round-trip scripts with filters", function()
      local scripts = {
        {
          name = "build",
          filename = "build.sh",
          filters = {
            enabled = true,
            show_only = { "ERROR", "WARN" },
            hide = { "DEBUG" },
          },
        },
      }

      local filepath = tmpdir .. "/config.json"
      local ok, export_err = sharing.export_to_file(scripts, filepath, { exclude_sensitive = false })
      assert.is_nil(export_err)
      assert.is_true(ok)

      local data, import_err = sharing.import_from_file(filepath)
      assert.is_nil(import_err)
      assert.is_not_nil(data)
      assert.is_true(data.scripts[1].filters.enabled)
      assert.are.equal(2, #data.scripts[1].filters.show_only)
    end)
  end)
end)

-- ===========================================================================
-- Integration tests with termlet main module
-- ===========================================================================

describe("termlet sharing integration", function()
  local termlet

  before_each(function()
    -- Clear cached modules for fresh state
    package.loaded["termlet"] = nil
    package.loaded["termlet.sharing"] = nil
    termlet = require("termlet")
  end)

  after_each(function()
    termlet.close_menu()
    termlet.close_all_terminals()
  end)

  describe("setup", function()
    it("should accept sharing configuration", function()
      termlet.setup({
        scripts = {},
        sharing = {
          default_format = "lua",
          exclude_sensitive = false,
        },
      })
      assert.is_not_nil(termlet)
    end)

    it("should initialize with default sharing config", function()
      termlet.setup({
        scripts = {},
      })
      assert.is_not_nil(termlet)
      assert.is_not_nil(termlet.sharing)
    end)
  end)

  describe("export_config", function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should return false when no scripts configured", function()
      termlet.setup({ scripts = {} })
      local ok, err = termlet.export_config(tmpdir .. "/config.json")
      assert.is_false(ok)
      assert.is_truthy(err:find("No scripts"))
    end)

    it("should export configured scripts", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "test", filename = "test.sh" },
        },
      })

      local filepath = tmpdir .. "/config.json"
      local ok, err = termlet.export_config(filepath)
      assert.is_nil(err)
      assert.is_true(ok)
      assert.are.equal(1, vim.fn.filereadable(filepath))
    end)

    it("should respect sharing config for sensitive fields", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh", root_dir = "/secret" },
        },
        sharing = { exclude_sensitive = true },
      })

      local filepath = tmpdir .. "/config.json"
      termlet.export_config(filepath)

      local f = io.open(filepath, "r")
      local content = f:read("*a")
      f:close()
      local decoded = vim.fn.json_decode(content)
      assert.is_nil(decoded.scripts[1].root_dir)
    end)
  end)

  describe("import_config", function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should import and merge scripts", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      -- Create import file
      local filepath = tmpdir .. "/import.json"
      local content = vim.fn.json_encode({
        version = 1,
        scripts = { { name = "test", filename = "test.sh" } },
      })
      local f = io.open(filepath, "w")
      f:write(content)
      f:close()

      local ok, err = termlet.import_config(filepath)
      assert.is_nil(err)
      assert.is_true(ok)

      -- Verify scripts were merged
      local scripts = termlet.get_scripts()
      assert.are.equal(2, #scripts)
    end)

    it("should import and replace scripts", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "old", filename = "old.sh" },
        },
      })

      local filepath = tmpdir .. "/import.json"
      local content = vim.fn.json_encode({
        version = 1,
        scripts = { { name = "new", filename = "new.sh" } },
      })
      local f = io.open(filepath, "w")
      f:write(content)
      f:close()

      local ok, err = termlet.import_config(filepath, { mode = "replace" })
      assert.is_nil(err)
      assert.is_true(ok)

      local scripts = termlet.get_scripts()
      assert.are.equal(1, #scripts)
      assert.are.equal("new", scripts[1].name)
    end)

    it("should preview without applying changes", function()
      termlet.setup({
        scripts = { { name = "build", filename = "build.sh" } },
      })

      local filepath = tmpdir .. "/import.json"
      local content = vim.fn.json_encode({
        version = 1,
        scripts = { { name = "test", filename = "test.sh" } },
      })
      local f = io.open(filepath, "w")
      f:write(content)
      f:close()

      local ok, preview_text = termlet.preview_import(filepath)
      assert.is_true(ok)
      assert.is_truthy(preview_text:find("test"))

      -- Verify scripts were NOT changed
      local scripts = termlet.get_scripts()
      assert.are.equal(1, #scripts)
      assert.are.equal("build", scripts[1].name)
    end)

    it("should report error for non-existent file", function()
      termlet.setup({ scripts = {} })
      local ok, err = termlet.import_config("/nonexistent/config.json")
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)

  describe("get_scripts", function()
    it("should return empty list when no scripts configured", function()
      termlet.setup({ scripts = {} })
      local scripts = termlet.get_scripts()
      assert.are.equal(0, #scripts)
    end)

    it("should return configured scripts", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "test", filename = "test.sh" },
        },
      })
      local scripts = termlet.get_scripts()
      assert.are.equal(2, #scripts)
    end)

    it("should return a deep copy that does not mutate internal state", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })
      local scripts = termlet.get_scripts()
      scripts[1].name = "mutated"
      table.insert(scripts, { name = "injected", filename = "evil.sh" })
      -- Internal state should be unchanged
      local scripts2 = termlet.get_scripts()
      assert.are.equal(1, #scripts2)
      assert.are.equal("build", scripts2[1].name)
    end)
  end)

  describe("TermLetExport command", function()
    it("should be registered after setup", function()
      termlet.setup({
        scripts = { { name = "build", filename = "build.sh" } },
      })
      -- Command should exist (will error if not registered)
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands["TermLetExport"])
    end)
  end)

  describe("TermLetImport command", function()
    it("should be registered after setup", function()
      termlet.setup({
        scripts = { { name = "build", filename = "build.sh" } },
      })
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands["TermLetImport"])
    end)
  end)
end)
