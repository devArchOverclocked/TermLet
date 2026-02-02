-- Tests for Dependency Resolution Module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("termlet.deps", function()
  local deps

  before_each(function()
    -- Clear cached module to get fresh state
    package.loaded["termlet.deps"] = nil
    deps = require("termlet.deps")
    deps.reset_state()
  end)

  describe("execution state", function()
    it("should track script execution status", function()
      deps.set_status("build", "running", nil)
      local status = deps.get_status("build")
      assert.is_not_nil(status)
      assert.equals("running", status.status)
      assert.is_nil(status.exit_code)
    end)

    it("should update status on completion", function()
      deps.set_status("build", "running", nil)
      deps.set_status("build", "success", 0)
      local status = deps.get_status("build")
      assert.equals("success", status.status)
      assert.equals(0, status.exit_code)
    end)

    it("should track failure status", function()
      deps.set_status("build", "failed", 1)
      local status = deps.get_status("build")
      assert.equals("failed", status.status)
      assert.equals(1, status.exit_code)
    end)

    it("should return nil for unknown script", function()
      local status = deps.get_status("nonexistent")
      assert.is_nil(status)
    end)

    it("should reset state", function()
      deps.set_status("build", "success", 0)
      deps.reset_state()
      local status = deps.get_status("build")
      assert.is_nil(status)
    end)
  end)

  describe("dependency validation", function()
    it("should validate scripts with no dependencies", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh" },
      }
      local valid, err = deps.validate_dependencies(scripts)
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should validate simple dependency chain", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local valid, err = deps.validate_dependencies(scripts)
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should detect non-existent dependency", function()
      local scripts = {
        { name = "test", filename = "test.sh", depends_on = { "nonexistent" } },
      }
      local valid, err = deps.validate_dependencies(scripts)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("non%-existent"))
    end)

    it("should detect circular dependency", function()
      local scripts = {
        { name = "a", filename = "a.sh", depends_on = { "b" } },
        { name = "b", filename = "b.sh", depends_on = { "a" } },
      }
      local valid, err = deps.validate_dependencies(scripts)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:find("Circular"))
    end)

    it("should detect circular dependency in longer chain", function()
      local scripts = {
        { name = "a", filename = "a.sh", depends_on = { "b" } },
        { name = "b", filename = "b.sh", depends_on = { "c" } },
        { name = "c", filename = "c.sh", depends_on = { "a" } },
      }
      local valid, err = deps.validate_dependencies(scripts)
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)

    it("should allow multiple dependencies", function()
      local scripts = {
        { name = "install", filename = "install.sh" },
        { name = "build", filename = "build.sh", depends_on = { "install" } },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
        { name = "deploy", filename = "deploy.sh", depends_on = { "build", "test" } },
      }
      local valid, err = deps.validate_dependencies(scripts)
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should handle complex dependency graph", function()
      local scripts = {
        { name = "a", filename = "a.sh" },
        { name = "b", filename = "b.sh", depends_on = { "a" } },
        { name = "c", filename = "c.sh", depends_on = { "a" } },
        { name = "d", filename = "d.sh", depends_on = { "b", "c" } },
      }
      local valid, err = deps.validate_dependencies(scripts)
      assert.is_true(valid)
      assert.is_nil(err)
    end)
  end)

  describe("dependency graph building", function()
    it("should build graph for independent scripts", function()
      local scripts = {
        { name = "a", filename = "a.sh" },
        { name = "b", filename = "b.sh" },
      }
      local graph = deps.build_dependency_graph(scripts)
      assert.is_not_nil(graph["a"])
      assert.is_not_nil(graph["b"])
      assert.equals(0, #graph["a"].dependencies)
      assert.equals(0, #graph["b"].dependencies)
    end)

    it("should track dependencies", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local graph = deps.build_dependency_graph(scripts)
      assert.equals(1, #graph["test"].dependencies)
      assert.equals("build", graph["test"].dependencies[1])
    end)

    it("should track reverse dependencies (dependents)", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local graph = deps.build_dependency_graph(scripts)
      assert.equals(1, #graph["build"].dependents)
      assert.equals("test", graph["build"].dependents[1])
    end)

    it("should handle multiple dependents", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
        { name = "deploy", filename = "deploy.sh", depends_on = { "build" } },
      }
      local graph = deps.build_dependency_graph(scripts)
      assert.equals(2, #graph["build"].dependents)
    end)
  end)

  describe("execution order resolution", function()
    it("should resolve single script with no dependencies", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
      }
      local order, err = deps.resolve_execution_order("build", scripts)
      assert.is_nil(err)
      assert.is_not_nil(order)
      assert.equals(1, #order)
      assert.equals("build", order[1])
    end)

    it("should resolve simple dependency chain", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local order, err = deps.resolve_execution_order("test", scripts)
      assert.is_nil(err)
      assert.is_not_nil(order)
      assert.equals(2, #order)
      assert.equals("build", order[1])
      assert.equals("test", order[2])
    end)

    it("should resolve longer dependency chain", function()
      local scripts = {
        { name = "install", filename = "install.sh" },
        { name = "build", filename = "build.sh", depends_on = { "install" } },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local order, err = deps.resolve_execution_order("test", scripts)
      assert.is_nil(err)
      assert.equals(3, #order)
      assert.equals("install", order[1])
      assert.equals("build", order[2])
      assert.equals("test", order[3])
    end)

    it("should resolve multiple dependencies", function()
      local scripts = {
        { name = "lint", filename = "lint.sh" },
        { name = "build", filename = "build.sh" },
        { name = "deploy", filename = "deploy.sh", depends_on = { "lint", "build" } },
      }
      local order, err = deps.resolve_execution_order("deploy", scripts)
      assert.is_nil(err)
      assert.equals(3, #order)
      -- Both lint and build should come before deploy
      assert.is_truthy(order[3] == "deploy")
    end)

    it("should handle diamond dependency", function()
      local scripts = {
        { name = "a", filename = "a.sh" },
        { name = "b", filename = "b.sh", depends_on = { "a" } },
        { name = "c", filename = "c.sh", depends_on = { "a" } },
        { name = "d", filename = "d.sh", depends_on = { "b", "c" } },
      }
      local order, err = deps.resolve_execution_order("d", scripts)
      assert.is_nil(err)
      assert.equals(4, #order)
      assert.equals("a", order[1])
      assert.equals("d", order[4])
    end)

    it("should return error for nonexistent script", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
      }
      local order, err = deps.resolve_execution_order("nonexistent", scripts)
      assert.is_nil(order)
      assert.is_not_nil(err)
    end)

    it("should detect circular dependencies", function()
      local scripts = {
        { name = "a", filename = "a.sh", depends_on = { "b" } },
        { name = "b", filename = "b.sh", depends_on = { "a" } },
      }
      local order, err = deps.resolve_execution_order("a", scripts)
      assert.is_nil(order)
      assert.is_not_nil(err)
    end)
  end)

  describe("dependency chain formatting", function()
    it("should format single script", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
      }
      local chain = deps.get_dependency_chain("build", scripts)
      assert.equals("build", chain)
    end)

    it("should format simple chain", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local chain = deps.get_dependency_chain("test", scripts)
      assert.is_truthy(chain:find("build"))
      assert.is_truthy(chain:find("test"))
      assert.is_truthy(chain:find("→"))
    end)

    it("should format longer chain", function()
      local scripts = {
        { name = "install", filename = "install.sh" },
        { name = "build", filename = "build.sh", depends_on = { "install" } },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local chain = deps.get_dependency_chain("test", scripts)
      assert.is_truthy(chain:find("install"))
      assert.is_truthy(chain:find("build"))
      assert.is_truthy(chain:find("test"))
    end)
  end)

  describe("execution policy checks", function()
    it("should allow execution when no dependencies", function()
      local script = { name = "build", filename = "build.sh" }
      local can_exec, err = deps.can_execute(script)
      assert.is_true(can_exec)
      assert.is_nil(err)
    end)

    it("should allow execution with run_after_deps='none'", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "none",
      }
      local can_exec, err = deps.can_execute(script)
      assert.is_true(can_exec)
      assert.is_nil(err)
    end)

    it("should block execution when dependencies not complete (run_after='all')", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "all",
      }
      local can_exec, err = deps.can_execute(script)
      assert.is_false(can_exec)
      assert.is_not_nil(err)
    end)

    it("should allow execution when all dependencies succeed (run_after='all')", function()
      deps.set_status("build", "success", 0)
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "all",
      }
      local can_exec, err = deps.can_execute(script)
      assert.is_true(can_exec)
      assert.is_nil(err)
    end)

    it("should block execution when any dependency fails (run_after='all')", function()
      deps.set_status("build", "failed", 1)
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "all",
      }
      local can_exec, err = deps.can_execute(script)
      assert.is_false(can_exec)
      assert.is_not_nil(err)
    end)

    it("should allow execution when at least one dependency succeeds (run_after='any')", function()
      deps.set_status("lint", "success", 0)
      deps.set_status("build", "failed", 1)
      local script = {
        name = "deploy",
        filename = "deploy.sh",
        depends_on = { "lint", "build" },
        run_after_deps = "any",
      }
      local can_exec, err = deps.can_execute(script)
      assert.is_true(can_exec)
      assert.is_nil(err)
    end)

    it("should block execution when no dependencies succeed (run_after='any')", function()
      deps.set_status("lint", "failed", 1)
      deps.set_status("build", "failed", 1)
      local script = {
        name = "deploy",
        filename = "deploy.sh",
        depends_on = { "lint", "build" },
        run_after_deps = "any",
      }
      local can_exec, err = deps.can_execute(script)
      assert.is_false(can_exec)
      assert.is_not_nil(err)
    end)

    it("should use 'all' as default run_after_deps", function()
      deps.set_status("build", "success", 0)
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        -- run_after_deps not specified, should default to "all"
      }
      local can_exec, _err = deps.can_execute(script)
      assert.is_true(can_exec)
    end)
  end)

  describe("dependency info formatting", function()
    it("should return empty for no dependencies", function()
      local script = { name = "build", filename = "build.sh" }
      local info = deps.format_dependency_info(script, {})
      assert.equals("", info)
    end)

    it("should format simple dependencies", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
      }
      local info = deps.format_dependency_info(script, {})
      assert.is_truthy(info:find("build"))
    end)

    it("should include run_after_deps when not 'all'", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "any",
      }
      local info = deps.format_dependency_info(script, {})
      assert.is_truthy(info:find("any"))
    end)

    it("should indicate parallel execution", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        parallel_deps = true,
      }
      local info = deps.format_dependency_info(script, {})
      assert.is_truthy(info:find("Parallel"))
    end)
  end)

  describe("get_dependencies_to_execute", function()
    it("should return empty list for script with no dependencies", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
      }
      local deps_to_run = deps.get_dependencies_to_execute("build", scripts)
      assert.equals(0, #deps_to_run)
    end)

    it("should return dependencies excluding target", function()
      local scripts = {
        { name = "build", filename = "build.sh" },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local deps_to_run = deps.get_dependencies_to_execute("test", scripts)
      assert.equals(1, #deps_to_run)
      assert.equals("build", deps_to_run[1])
    end)

    it("should return all transitive dependencies", function()
      local scripts = {
        { name = "install", filename = "install.sh" },
        { name = "build", filename = "build.sh", depends_on = { "install" } },
        { name = "test", filename = "test.sh", depends_on = { "build" } },
      }
      local deps_to_run = deps.get_dependencies_to_execute("test", scripts)
      assert.equals(2, #deps_to_run)
      assert.is_truthy(deps_to_run[1] == "install")
      assert.is_truthy(deps_to_run[2] == "build")
    end)
  end)

  describe("should_execute_dependencies", function()
    it("should return false for no dependencies", function()
      local script = { name = "build", filename = "build.sh" }
      assert.is_false(deps.should_execute_dependencies(script))
    end)

    it("should return false for run_after_deps='none'", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "none",
      }
      assert.is_false(deps.should_execute_dependencies(script))
    end)

    it("should return true for dependencies with run_after_deps='all'", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "all",
      }
      assert.is_true(deps.should_execute_dependencies(script))
    end)

    it("should return true for dependencies with run_after_deps='any'", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
        run_after_deps = "any",
      }
      assert.is_true(deps.should_execute_dependencies(script))
    end)

    it("should default to true when run_after_deps not specified", function()
      local script = {
        name = "test",
        filename = "test.sh",
        depends_on = { "build" },
      }
      assert.is_true(deps.should_execute_dependencies(script))
    end)
  end)
end)
