-- Dependency Resolution Module for TermLet
-- Handles script dependencies, execution order, and dependency graph building

local M = {}

-- Execution state tracking
local execution_state = {}

--- Reset execution state
function M.reset_state()
  execution_state = {}
end

--- Set execution status for a script
---@param script_name string
---@param status string "pending"|"running"|"success"|"failed"
---@param exit_code number|nil Exit code if finished
function M.set_status(script_name, status, exit_code)
  execution_state[script_name] = {
    status = status,
    exit_code = exit_code,
    timestamp = os.time(),
  }
end

--- Get execution status for a script
---@param script_name string
---@return table|nil Status info
function M.get_status(script_name)
  return execution_state[script_name]
end

--- Validate script dependencies
---@param scripts table List of all scripts
---@return boolean success
---@return string|nil error_message
function M.validate_dependencies(scripts)
  -- Build script name lookup
  local script_map = {}
  for _, script in ipairs(scripts) do
    script_map[script.name] = script
  end

  -- Check all dependencies exist
  for _, script in ipairs(scripts) do
    if script.depends_on then
      for _, dep_name in ipairs(script.depends_on) do
        if not script_map[dep_name] then
          return false, "Script '" .. script.name .. "' depends on non-existent script '" .. dep_name .. "'"
        end
      end
    end
  end

  -- Check for circular dependencies using DFS
  local visited = {}
  local rec_stack = {}

  local function has_cycle(script_name)
    if rec_stack[script_name] then
      return true -- Found a cycle
    end
    if visited[script_name] then
      return false
    end

    visited[script_name] = true
    rec_stack[script_name] = true

    local script = script_map[script_name]
    if script and script.depends_on then
      for _, dep_name in ipairs(script.depends_on) do
        if has_cycle(dep_name) then
          return true
        end
      end
    end

    rec_stack[script_name] = false
    return false
  end

  for _, script in ipairs(scripts) do
    if has_cycle(script.name) then
      return false, "Circular dependency detected involving script '" .. script.name .. "'"
    end
  end

  return true, nil
end

--- Build dependency graph for visualization
---@param scripts table List of all scripts
---@return table Dependency graph as adjacency list
function M.build_dependency_graph(scripts)
  local graph = {}

  for _, script in ipairs(scripts) do
    graph[script.name] = {
      script = script,
      dependencies = script.depends_on or {},
      dependents = {},
    }
  end

  -- Build reverse dependencies (what depends on this script)
  for _, script in ipairs(scripts) do
    if script.depends_on then
      for _, dep_name in ipairs(script.depends_on) do
        if graph[dep_name] then
          table.insert(graph[dep_name].dependents, script.name)
        end
      end
    end
  end

  return graph
end

--- Resolve execution order using topological sort
---@param script_name string Target script to execute
---@param scripts table List of all scripts
---@return table|nil Ordered list of script names to execute
---@return string|nil Error message if resolution fails
function M.resolve_execution_order(script_name, scripts)
  -- Build script lookup
  local script_map = {}
  for _, script in ipairs(scripts) do
    script_map[script.name] = script
  end

  if not script_map[script_name] then
    return nil, "Script '" .. script_name .. "' not found"
  end

  -- Validate dependencies first
  local valid, err = M.validate_dependencies(scripts)
  if not valid then
    return nil, err
  end

  -- Build execution order using DFS
  local visited = {}
  local order = {}

  local function visit(name)
    if visited[name] then
      return
    end

    visited[name] = true

    local script = script_map[name]
    if script and script.depends_on then
      for _, dep_name in ipairs(script.depends_on) do
        visit(dep_name)
      end
    end

    table.insert(order, name)
  end

  visit(script_name)

  return order, nil
end

--- Get dependency chain as a formatted string
---@param script_name string
---@param scripts table List of all scripts
---@return string Formatted dependency chain (e.g., "install → build → test")
function M.get_dependency_chain(script_name, scripts)
  local order, _err = M.resolve_execution_order(script_name, scripts)
  if not order then
    return script_name
  end

  if #order == 1 then
    return script_name
  end

  return table.concat(order, " → ")
end

--- Check if dependencies should be executed
---@param script table Script configuration
---@return boolean Should execute dependencies
function M.should_execute_dependencies(script)
  if not script.depends_on or #script.depends_on == 0 then
    return false
  end

  local run_after = script.run_after_deps or "all"
  if run_after == "none" then
    return false
  end

  return true
end

--- Check if a script can execute based on dependency status
---@param script table Script configuration
---@return boolean Can execute
---@return string|nil Error message if cannot execute
function M.can_execute(script)
  if not script.depends_on or #script.depends_on == 0 then
    return true, nil
  end

  local run_after = script.run_after_deps or "all"

  if run_after == "none" then
    return true, nil
  end

  local success_count = 0
  local failed_deps = {}

  for _, dep_name in ipairs(script.depends_on) do
    local status = M.get_status(dep_name)
    if status then
      if status.status == "success" then
        success_count = success_count + 1
      elseif status.status == "failed" then
        table.insert(failed_deps, dep_name)
      end
    end
  end

  if run_after == "all" then
    if #failed_deps > 0 then
      return false, "Dependencies failed: " .. table.concat(failed_deps, ", ")
    end
    if success_count < #script.depends_on then
      return false, "Not all dependencies completed successfully"
    end
  elseif run_after == "any" then
    if success_count == 0 then
      return false, "No dependencies completed successfully"
    end
  end

  return true, nil
end

--- Format dependency info for display
---@param script table Script configuration
---@param scripts table All scripts
---@return string Formatted info
function M.format_dependency_info(script, _scripts)
  if not script.depends_on or #script.depends_on == 0 then
    return ""
  end

  local parts = {}
  table.insert(parts, "Dependencies: " .. table.concat(script.depends_on, ", "))

  local run_after = script.run_after_deps or "all"
  if run_after ~= "all" then
    table.insert(parts, "Run after: " .. run_after)
  end

  if script.parallel_deps then
    table.insert(parts, "Parallel execution")
  end

  return table.concat(parts, " | ")
end

--- Get all dependencies that need to be executed
---@param script_name string
---@param scripts table All scripts
---@return table List of script names (excluding the target script itself)
function M.get_dependencies_to_execute(script_name, scripts)
  local order, _err = M.resolve_execution_order(script_name, scripts)
  if not order then
    return {}
  end

  -- Remove the target script from the list (it's always last)
  local deps = {}
  for i = 1, #order - 1 do
    table.insert(deps, order[i])
  end

  return deps
end

return M
