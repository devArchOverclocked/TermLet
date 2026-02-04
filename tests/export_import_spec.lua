-- Tests for TermLet Export/Import Module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.export_import", function()
  local export_import

  -- Sample scripts for testing
  local test_scripts = {
    {
      name = "build",
      filename = "build.sh",
      description = "Build project",
      cmd = "./build.sh",
    },
    {
      name = "test",
      filename = "test.sh",
      description = "Run tests",
      depends_on = { "build" },
    },
    {
      name = "deploy",
      filename = "deploy.sh",
      description = "Deploy to production",
      root_dir = "/home/user/project",
      env = { NODE_ENV = "production" },
      depends_on = { "build", "test" },
      run_after_deps = "all",
    },
  }

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.export_import"] = nil
    export_import = require("termlet.export_import")
  end)

  after_each(function()
    if export_import.is_preview_open() then
      export_import.close_preview()
    end
  end)

  describe("export_json", function()
    it("should export scripts to valid JSON", function()
      local json_str, err = export_import.export_json(test_scripts)
      assert.is_nil(err)
      assert.is_not_nil(json_str)
      assert.is_string(json_str)

      -- Parse it back
      local data = vim.fn.json_decode(json_str)
      assert.is_not_nil(data)
      assert.is_not_nil(data.scripts)
      assert.equals(3, #data.scripts)
    end)

    it("should include version field", function()
      local json_str, _err = export_import.export_json(test_scripts)
      local data = vim.fn.json_decode(json_str)
      assert.equals(1, data.version)
    end)

    it("should include metadata by default", function()
      local json_str, _err = export_import.export_json(test_scripts)
      local data = vim.fn.json_decode(json_str)
      assert.is_not_nil(data.metadata)
      assert.is_not_nil(data.metadata.exported_at)
      assert.equals(3, data.metadata.script_count)
    end)

    it("should strip sensitive fields by default", function()
      local json_str, _err = export_import.export_json(test_scripts)
      local data = vim.fn.json_decode(json_str)

      for _, script in ipairs(data.scripts) do
        assert.is_nil(script.env)
        assert.is_nil(script.root_dir)
        assert.is_nil(script.search_dirs)
      end
    end)

    it("should keep sensitive fields when strip_sensitive is false", function()
      local json_str, _err = export_import.export_json(test_scripts, { strip_sensitive = false })
      local data = vim.fn.json_decode(json_str)

      -- deploy script should have env and root_dir
      local deploy = nil
      for _, script in ipairs(data.scripts) do
        if script.name == "deploy" then
          deploy = script
          break
        end
      end
      assert.is_not_nil(deploy)
      assert.is_not_nil(deploy.env)
      assert.is_not_nil(deploy.root_dir)
    end)

    it("should preserve non-sensitive fields", function()
      local json_str, _err = export_import.export_json(test_scripts)
      local data = vim.fn.json_decode(json_str)

      local build = nil
      for _, script in ipairs(data.scripts) do
        if script.name == "build" then
          build = script
          break
        end
      end
      assert.is_not_nil(build)
      assert.equals("build", build.name)
      assert.equals("build.sh", build.filename)
      assert.equals("Build project", build.description)
      assert.equals("./build.sh", build.cmd)
    end)

    it("should preserve depends_on", function()
      local json_str, _err = export_import.export_json(test_scripts)
      local data = vim.fn.json_decode(json_str)

      local test_script = nil
      for _, script in ipairs(data.scripts) do
        if script.name == "test" then
          test_script = script
          break
        end
      end
      assert.is_not_nil(test_script)
      assert.is_not_nil(test_script.depends_on)
      assert.equals(1, #test_script.depends_on)
      assert.equals("build", test_script.depends_on[1])
    end)

    it("should return error for empty scripts", function()
      local json_str, err = export_import.export_json({})
      assert.is_nil(json_str)
      assert.is_not_nil(err)
    end)

    it("should return error for nil scripts", function()
      local json_str, err = export_import.export_json(nil)
      assert.is_nil(json_str)
      assert.is_not_nil(err)
    end)

    it("should exclude metadata when include_metadata is false", function()
      local json_str, _err = export_import.export_json(test_scripts, { include_metadata = false })
      local data = vim.fn.json_decode(json_str)
      assert.is_nil(data.metadata)
    end)

    it("should use strip_fields to customize which fields are stripped", function()
      local scripts = {
        {
          name = "build",
          filename = "build.sh",
          description = "Build project",
          cmd = "./build.sh",
          env = { VAR = "val" },
        },
      }

      -- strip_fields should strip the specified fields instead of the defaults
      local json_str, _err = export_import.export_json(scripts, {
        strip_fields = { "description", "cmd" },
      })
      local data = vim.fn.json_decode(json_str)
      local build = data.scripts[1]

      -- description and cmd should be stripped
      assert.is_nil(build.description)
      assert.is_nil(build.cmd)
      -- env should NOT be stripped (it's in defaults, but strip_fields overrides)
      assert.is_not_nil(build.env)
    end)

    it("should filter to include_fields when specified", function()
      local json_str, _err = export_import.export_json(test_scripts, {
        include_fields = { "name", "filename", "description" },
      })
      local data = vim.fn.json_decode(json_str)

      local build = nil
      for _, script in ipairs(data.scripts) do
        if script.name == "build" then
          build = script
          break
        end
      end
      assert.is_not_nil(build)
      assert.equals("build", build.name)
      assert.equals("build.sh", build.filename)
      assert.equals("Build project", build.description)
      -- cmd should not be included since it's not in include_fields
      assert.is_nil(build.cmd)
    end)
  end)

  describe("export_to_file", function()
    it("should write JSON to file", function()
      local tmpfile = vim.fn.tempname() .. ".json"
      local ok, err = export_import.export_to_file(test_scripts, tmpfile)
      assert.is_true(ok)
      assert.is_nil(err)

      -- Verify file exists and contains valid JSON
      assert.equals(1, vim.fn.filereadable(tmpfile))
      local file = io.open(tmpfile, "r")
      local content = file:read("*a")
      file:close()

      local data = vim.fn.json_decode(content)
      assert.is_not_nil(data)
      assert.equals(3, #data.scripts)

      -- Cleanup
      os.remove(tmpfile)
    end)

    it("should return error for invalid directory", function()
      local ok, err = export_import.export_to_file(test_scripts, "/nonexistent/dir/file.json")
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)

    it("should return error for empty scripts", function()
      local tmpfile = vim.fn.tempname() .. ".json"
      local ok, err = export_import.export_to_file({}, tmpfile)
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)

    it("should write atomically (no temp file left on success)", function()
      local tmpfile = vim.fn.tempname() .. ".json"
      local ok, err = export_import.export_to_file(test_scripts, tmpfile)
      assert.is_true(ok)
      assert.is_nil(err)

      -- The target file should exist
      assert.equals(1, vim.fn.filereadable(tmpfile))

      -- No temp file should remain (temp file pattern: filepath.tmp.<timestamp>)
      local tmpdir = vim.fn.fnamemodify(tmpfile, ":h")
      local basename = vim.fn.fnamemodify(tmpfile, ":t")
      local handle = vim.loop.fs_scandir(tmpdir)
      if handle then
        while true do
          local name = vim.loop.fs_scandir_next(handle)
          if not name then
            break
          end
          assert.is_falsy(name:match("^" .. vim.pesc(basename) .. "%.tmp%."), "Temp file should not remain: " .. name)
        end
      end

      os.remove(tmpfile)
    end)
  end)

  describe("parse_json", function()
    it("should parse valid JSON", function()
      local json_str = vim.fn.json_encode({
        version = 1,
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      local data, err = export_import.parse_json(json_str)
      assert.is_nil(err)
      assert.is_not_nil(data)
      assert.equals(1, data.version)
      assert.equals(1, #data.scripts)
    end)

    it("should return error for invalid JSON", function()
      local data, err = export_import.parse_json("not json{{{")
      assert.is_nil(data)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("Invalid JSON"))
    end)

    it("should return error for empty string", function()
      local data, err = export_import.parse_json("")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)

    it("should return error for nil", function()
      local data, err = export_import.parse_json(nil)
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)
  end)

  describe("validate_import_data", function()
    it("should accept valid import data", function()
      local data = {
        version = 1,
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "test", filename = "test.sh" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject non-table input", function()
      local valid, err = export_import.validate_import_data("not a table")
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject missing scripts field", function()
      local valid, err = export_import.validate_import_data({ version = 1 })
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject empty scripts list", function()
      local valid, err = export_import.validate_import_data({ scripts = {} })
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject script without name", function()
      local data = {
        scripts = {
          { filename = "build.sh" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject script with empty name", function()
      local data = {
        scripts = {
          { name = "", filename = "build.sh" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject script without filename or dir_name+relative_path", function()
      local data = {
        scripts = {
          { name = "build" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should accept script with dir_name and relative_path", function()
      local data = {
        scripts = {
          { name = "build", dir_name = "scripts", relative_path = "build.sh" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject duplicate script names", function()
      local data = {
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "build", filename = "build2.sh" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("Duplicate"))
    end)

    it("should reject invalid depends_on entries", function()
      local data = {
        scripts = {
          { name = "build", filename = "build.sh", depends_on = { 123 } },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject invalid run_after_deps value", function()
      local data = {
        scripts = {
          { name = "build", filename = "build.sh", run_after_deps = "invalid" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should accept valid run_after_deps values", function()
      for _, mode in ipairs({ "all", "any", "none" }) do
        local data = {
          scripts = {
            { name = "build", filename = "build.sh", run_after_deps = mode },
          },
        }
        local valid, err = export_import.validate_import_data(data)
        assert.is_true(valid, "Should accept run_after_deps='" .. mode .. "': " .. tostring(err))
        assert.is_nil(err)
      end
    end)

    it("should reject scripts with path traversal in filename", function()
      local data = {
        scripts = {
          { name = "malicious", filename = "../../.bashrc" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("path traversal"))
    end)

    it("should reject scripts with path traversal in relative_path", function()
      local data = {
        scripts = {
          { name = "malicious", dir_name = "scripts", relative_path = "../../../etc/passwd" },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("path traversal"))
    end)

    it("should accept scripts with optional fields", function()
      local data = {
        scripts = {
          {
            name = "build",
            filename = "build.sh",
            description = "Build project",
            cmd = "./build.sh",
            depends_on = { "install" },
            run_after_deps = "all",
          },
          {
            name = "install",
            filename = "install.sh",
          },
        },
      }
      local valid, err = export_import.validate_import_data(data)
      assert.is_true(valid)
      assert.is_nil(err)
    end)
  end)

  describe("import_from_file", function()
    it("should import valid JSON file", function()
      -- Create temp file with valid data
      local tmpfile = vim.fn.tempname() .. ".json"
      local data = {
        version = 1,
        scripts = {
          { name = "build", filename = "build.sh" },
          { name = "test", filename = "test.sh", depends_on = { "build" } },
        },
      }
      local file = io.open(tmpfile, "w")
      file:write(vim.fn.json_encode(data))
      file:close()

      local imported, err = export_import.import_from_file(tmpfile)
      assert.is_nil(err)
      assert.is_not_nil(imported)
      assert.equals(2, #imported.scripts)
      assert.equals("build", imported.scripts[1].name)

      os.remove(tmpfile)
    end)

    it("should return error for nonexistent file", function()
      local data, err = export_import.import_from_file("/nonexistent/file.json")
      assert.is_nil(data)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("not found"))
    end)

    it("should return error for invalid JSON file", function()
      local tmpfile = vim.fn.tempname() .. ".json"
      local file = io.open(tmpfile, "w")
      file:write("not valid json{{{")
      file:close()

      local data, err = export_import.import_from_file(tmpfile)
      assert.is_nil(data)
      assert.is_not_nil(err)

      os.remove(tmpfile)
    end)

    it("should return error for empty file", function()
      local tmpfile = vim.fn.tempname() .. ".json"
      local file = io.open(tmpfile, "w")
      file:write("")
      file:close()

      local data, err = export_import.import_from_file(tmpfile)
      assert.is_nil(data)
      assert.is_not_nil(err)

      os.remove(tmpfile)
    end)

    it("should validate imported data", function()
      -- Create file with invalid data (no scripts field)
      local tmpfile = vim.fn.tempname() .. ".json"
      local file = io.open(tmpfile, "w")
      file:write(vim.fn.json_encode({ version = 1 }))
      file:close()

      local data, err = export_import.import_from_file(tmpfile)
      assert.is_nil(data)
      assert.is_not_nil(err)

      os.remove(tmpfile)
    end)
  end)

  describe("merge_scripts", function()
    it("should add new scripts", function()
      local existing = {
        { name = "build", filename = "build.sh" },
      }
      local imported = {
        { name = "test", filename = "test.sh" },
        { name = "deploy", filename = "deploy.sh" },
      }

      local merged, changes = export_import.merge_scripts(existing, imported)
      assert.equals(3, #merged)
      assert.equals(2, #changes.added)
      assert.equals(0, #changes.updated)
      assert.equals(1, #changes.unchanged)
    end)

    it("should update existing scripts", function()
      local existing = {
        { name = "build", filename = "build.sh", description = "Old description" },
      }
      local imported = {
        { name = "build", filename = "build.sh", description = "New description" },
      }

      local merged, changes = export_import.merge_scripts(existing, imported)
      assert.equals(1, #merged)
      assert.equals(0, #changes.added)
      assert.equals(1, #changes.updated)
      assert.equals("New description", merged[1].description)
    end)

    it("should merge fields from imported into existing", function()
      local existing = {
        { name = "build", filename = "build.sh", root_dir = "/project" },
      }
      local imported = {
        { name = "build", filename = "build.sh", description = "Build project" },
      }

      local merged, _changes = export_import.merge_scripts(existing, imported)
      -- Should have both root_dir (from existing) and description (from imported)
      assert.equals("/project", merged[1].root_dir)
      assert.equals("Build project", merged[1].description)
    end)

    it("should handle empty existing list", function()
      local existing = {}
      local imported = {
        { name = "build", filename = "build.sh" },
      }

      local merged, changes = export_import.merge_scripts(existing, imported)
      assert.equals(1, #merged)
      assert.equals(1, #changes.added)
    end)

    it("should handle empty imported list", function()
      local existing = {
        { name = "build", filename = "build.sh" },
      }
      local imported = {}

      local merged, changes = export_import.merge_scripts(existing, imported)
      assert.equals(1, #merged)
      assert.equals(0, #changes.added)
      assert.equals(0, #changes.updated)
      assert.equals(1, #changes.unchanged)
    end)

    it("should not modify original tables", function()
      local existing = {
        { name = "build", filename = "build.sh", description = "Old" },
      }
      local imported = {
        { name = "build", filename = "build.sh", description = "New" },
      }

      local _merged, _changes = export_import.merge_scripts(existing, imported)
      assert.equals("Old", existing[1].description)
    end)

    it("should handle mixed add and update", function()
      local existing = {
        { name = "build", filename = "build.sh" },
        { name = "lint", filename = "lint.sh" },
      }
      local imported = {
        { name = "build", filename = "build.sh", description = "Updated" },
        { name = "test", filename = "test.sh" },
      }

      local merged, changes = export_import.merge_scripts(existing, imported)
      assert.equals(3, #merged)
      assert.equals(1, #changes.added)
      assert.equals(1, #changes.updated)
      assert.equals(1, #changes.unchanged)
      assert.equals("test", changes.added[1])
      assert.equals("build", changes.updated[1])
      assert.equals("lint", changes.unchanged[1])
    end)
  end)

  describe("_strip_sensitive", function()
    it("should strip default sensitive fields", function()
      local script = {
        name = "deploy",
        filename = "deploy.sh",
        env = { NODE_ENV = "production" },
        root_dir = "/home/user/project",
        search_dirs = { "scripts" },
        description = "Deploy",
      }

      local cleaned = export_import._strip_sensitive(script)
      assert.is_nil(cleaned.env)
      assert.is_nil(cleaned.root_dir)
      assert.is_nil(cleaned.search_dirs)
      assert.equals("deploy", cleaned.name)
      assert.equals("deploy.sh", cleaned.filename)
      assert.equals("Deploy", cleaned.description)
    end)

    it("should strip custom fields via strip_fields", function()
      local script = {
        name = "build",
        filename = "build.sh",
        description = "Build",
        cmd = "./build.sh",
      }

      local cleaned = export_import._strip_sensitive(script, { "description", "cmd" })
      assert.is_nil(cleaned.description)
      assert.is_nil(cleaned.cmd)
      assert.equals("build", cleaned.name)
      assert.equals("build.sh", cleaned.filename)
    end)

    it("should not modify original table", function()
      local script = {
        name = "deploy",
        env = { NODE_ENV = "production" },
      }

      local _cleaned = export_import._strip_sensitive(script)
      assert.is_not_nil(script.env)
    end)

    it("should deep copy table values", function()
      local script = {
        name = "build",
        filename = "build.sh",
        depends_on = { "install" },
      }

      local cleaned = export_import._strip_sensitive(script)
      assert.is_not_nil(cleaned.depends_on)
      -- Modifying the copy should not affect the original
      table.insert(cleaned.depends_on, "lint")
      assert.equals(1, #script.depends_on)
    end)
  end)

  describe("_validate_script", function()
    it("should accept valid script with filename", function()
      local valid, err = export_import._validate_script({
        name = "build",
        filename = "build.sh",
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should accept valid script with dir_name and relative_path", function()
      local valid, err = export_import._validate_script({
        name = "build",
        dir_name = "scripts",
        relative_path = "build.sh",
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject non-table", function()
      local valid, err = export_import._validate_script("not a table")
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject missing name", function()
      local valid, err = export_import._validate_script({ filename = "build.sh" })
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject empty name", function()
      local valid, err = export_import._validate_script({ name = "", filename = "build.sh" })
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject missing filename and dir_name", function()
      local valid, err = export_import._validate_script({ name = "build" })
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should reject filename with path traversal", function()
      local valid, err = export_import._validate_script({
        name = "build",
        filename = "../../.bashrc",
      })
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("path traversal"))
    end)

    it("should reject relative_path with path traversal", function()
      local valid, err = export_import._validate_script({
        name = "build",
        dir_name = "scripts",
        relative_path = "../../../etc/passwd",
      })
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("path traversal"))
    end)

    it("should accept filename with subdirectory path", function()
      local valid, err = export_import._validate_script({
        name = "build",
        filename = "scripts/build.sh",
      })
      assert.is_true(valid)
      assert.is_nil(err)
    end)
  end)

  describe("_has_path_traversal", function()
    it("should detect bare ..", function()
      assert.is_true(export_import._has_path_traversal(".."))
    end)

    it("should detect .. at start of path", function()
      assert.is_true(export_import._has_path_traversal("../etc/passwd"))
    end)

    it("should detect .. at end of path", function()
      assert.is_true(export_import._has_path_traversal("scripts/.."))
    end)

    it("should not flag normal paths", function()
      assert.is_false(export_import._has_path_traversal("build.sh"))
      assert.is_false(export_import._has_path_traversal("scripts/build.sh"))
      assert.is_false(export_import._has_path_traversal("./build.sh"))
    end)

    it("should not flag filenames containing dots", function()
      assert.is_false(export_import._has_path_traversal("my..file.sh"))
      assert.is_false(export_import._has_path_traversal("file...sh"))
    end)
  end)

  describe("roundtrip", function()
    it("should roundtrip export/import through JSON", function()
      local scripts = {
        { name = "build", filename = "build.sh", description = "Build project" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }

      -- Export
      local json_str, export_err = export_import.export_json(scripts, { strip_sensitive = false })
      assert.is_nil(export_err)

      -- Parse
      local data, parse_err = export_import.parse_json(json_str)
      assert.is_nil(parse_err)

      -- Validate
      local valid, validate_err = export_import.validate_import_data(data)
      assert.is_true(valid)
      assert.is_nil(validate_err)

      -- Compare
      assert.equals(2, #data.scripts)
      assert.equals("build", data.scripts[1].name)
      assert.equals("test", data.scripts[2].name)
      assert.equals(1, #data.scripts[2].depends_on)
    end)

    it("should roundtrip through file", function()
      local scripts = {
        { name = "build", filename = "build.sh", description = "Build project" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }

      local tmpfile = vim.fn.tempname() .. ".json"

      -- Export to file
      local ok, export_err = export_import.export_to_file(scripts, tmpfile, { strip_sensitive = false })
      assert.is_true(ok)
      assert.is_nil(export_err)

      -- Import from file
      local data, import_err = export_import.import_from_file(tmpfile)
      assert.is_nil(import_err)
      assert.is_not_nil(data)
      assert.equals(2, #data.scripts)

      os.remove(tmpfile)
    end)
  end)

  describe("preview UI", function()
    it("should open preview with valid data", function()
      local data = {
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      }

      local result = export_import.open_preview(data, {}, function() end)
      assert.is_true(result)
      assert.is_true(export_import.is_preview_open())
    end)

    it("should return false for empty data", function()
      local data = { scripts = {} }
      local result = export_import.open_preview(data, {}, function() end)
      assert.is_false(result)
    end)

    it("should return false for nil data", function()
      local result = export_import.open_preview(nil, {}, function() end)
      assert.is_false(result)
    end)

    it("should close preview", function()
      local data = {
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      }

      export_import.open_preview(data, {}, function() end)
      assert.is_true(export_import.is_preview_open())

      export_import.close_preview()
      assert.is_false(export_import.is_preview_open())
    end)

    it("should not error when closing with no preview open", function()
      export_import.close_preview()
      assert.is_false(export_import.is_preview_open())
    end)

    it("should close existing preview when opening new one", function()
      local data = {
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      }

      export_import.open_preview(data, {}, function() end)
      assert.is_true(export_import.is_preview_open())

      -- Opening another should close the first
      local data2 = {
        scripts = {
          { name = "test", filename = "test.sh" },
        },
      }
      export_import.open_preview(data2, {}, function() end)
      assert.is_true(export_import.is_preview_open())
    end)
  end)

  describe("get_state", function()
    it("should return initial state", function()
      local state = export_import.get_state()
      assert.equals("merge", state.preview_mode)
      assert.is_false(state.is_open)
      assert.is_false(state.has_data)
    end)

    it("should reflect open state", function()
      local data = {
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      }

      export_import.open_preview(data, {}, function() end)
      local state = export_import.get_state()
      assert.is_true(state.is_open)
      assert.is_true(state.has_data)
    end)
  end)
end)

describe("termlet export/import integration", function()
  local termlet

  before_each(function()
    -- Clear cached modules
    package.loaded["termlet"] = nil
    package.loaded["termlet.export_import"] = nil
    termlet = require("termlet")
  end)

  after_each(function()
    if termlet.close_import_preview then
      termlet.close_import_preview()
    end
    termlet.close_all_terminals()
  end)

  describe("setup", function()
    it("should expose export_import module", function()
      termlet.setup({ scripts = {} })
      assert.is_not_nil(termlet.get_export_import())
    end)

    it("should expose export/import functions", function()
      termlet.setup({ scripts = {} })
      assert.is_function(termlet.export_scripts)
      assert.is_function(termlet.export_to_file)
      assert.is_function(termlet.import_from_file)
      assert.is_function(termlet.close_import_preview)
      assert.is_function(termlet.is_import_preview_open)
    end)
  end)

  describe("export_scripts", function()
    it("should export configured scripts", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh", description = "Build" },
          { name = "test", filename = "test.sh" },
        },
      })

      local json_str, err = termlet.export_scripts()
      assert.is_nil(err)
      assert.is_not_nil(json_str)

      local data = vim.fn.json_decode(json_str)
      assert.equals(2, #data.scripts)
    end)

    it("should return nil when no scripts configured", function()
      termlet.setup({ scripts = {} })
      local json_str, err = termlet.export_scripts()
      assert.is_nil(json_str)
      assert.is_not_nil(err)
    end)

    it("should pass options through", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh", env = { VAR = "value" } },
        },
      })

      -- With strip_sensitive=false
      local json_str, _err = termlet.export_scripts({ strip_sensitive = false })
      local data = vim.fn.json_decode(json_str)
      assert.is_not_nil(data.scripts[1].env)

      -- With default (strip_sensitive=true)
      json_str, _err = termlet.export_scripts()
      data = vim.fn.json_decode(json_str)
      assert.is_nil(data.scripts[1].env)
    end)
  end)

  describe("export_to_file", function()
    it("should export to specified file", function()
      termlet.setup({
        scripts = {
          { name = "build", filename = "build.sh" },
        },
      })

      local tmpfile = vim.fn.tempname() .. ".json"
      termlet.export_to_file(tmpfile)

      assert.equals(1, vim.fn.filereadable(tmpfile))

      local file = io.open(tmpfile, "r")
      local content = file:read("*a")
      file:close()

      local data = vim.fn.json_decode(content)
      assert.equals(1, #data.scripts)

      os.remove(tmpfile)
    end)
  end)

  describe("is_import_preview_open", function()
    it("should return false initially", function()
      termlet.setup({ scripts = {} })
      assert.is_false(termlet.is_import_preview_open())
    end)
  end)

  describe("_do_import", function()
    it("should report error for nonexistent file", function()
      termlet.setup({ scripts = {} })
      -- Should not error, just notify
      termlet._do_import("/nonexistent/file.json")
    end)
  end)
end)
