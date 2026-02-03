# Script Dependencies and Chaining

> **Note:** The `termlet.deps` module is a standalone dependency resolution library. It is **not yet integrated** into `termlet.setup()` or the plugin's script execution flow. To use it today, require it directly via `require('termlet.deps')` and call its functions with your script tables.

## Features

- **Automatic Dependency Resolution**: Define dependencies between scripts and resolve execution order automatically
- **Circular Dependency Detection**: Prevents infinite loops by detecting circular dependencies at validation time
- **Flexible Execution Policies**: Control when scripts run based on dependency outcomes (`all`, `any`, or `none`)
- **Topological Sort**: Resolves correct execution order for complex dependency graphs
- **Execution State Tracking**: Track script status (pending, running, success, failed) and exit codes

## Module API

Access the module directly:

```lua
local deps = require('termlet.deps')
```

### Core Functions

#### `deps.validate_dependencies(scripts)`

Validates that all dependencies exist and there are no circular references.

```lua
local scripts = {
  { name = "install", filename = "install.sh" },
  { name = "build", filename = "build.sh", depends_on = { "install" } },
  { name = "test", filename = "test.sh", depends_on = { "build" } },
}

local valid, err = deps.validate_dependencies(scripts)
if not valid then
  print("Error: " .. err)
end
```

#### `deps.resolve_execution_order(script_name, scripts)`

Returns a topologically sorted list of script names that need to run (including the target).

```lua
local order, err = deps.resolve_execution_order("test", scripts)
-- order = { "install", "build", "test" }
```

#### `deps.build_dependency_graph(scripts)`

Builds an adjacency list representation of the dependency graph with forward and reverse edges.

```lua
local graph = deps.build_dependency_graph(scripts)
-- graph["build"].dependencies = { "install" }
-- graph["install"].dependents = { "build" }
```

#### `deps.get_dependency_chain(script_name, scripts)`

Returns a formatted string showing the execution order.

```lua
local chain = deps.get_dependency_chain("test", scripts)
-- chain = "install → build → test"
```

#### `deps.can_execute(script)`

Checks whether a script can execute based on the current execution state of its dependencies and its `run_after_deps` policy.

```lua
deps.set_status("install", "success", 0)
deps.set_status("build", "success", 0)

local can_run, err = deps.can_execute({
  name = "test",
  depends_on = { "install", "build" },
  run_after_deps = "all",
})
```

#### `deps.should_execute_dependencies(script)`

Returns whether a script has dependencies that need to be executed.

#### `deps.get_dependencies_to_execute(script_name, scripts)`

Returns the list of dependency script names (excluding the target script itself).

#### `deps.format_dependency_info(script, scripts)`

Returns a formatted string summarizing a script's dependency configuration.

### State Management

#### `deps.set_status(script_name, status, exit_code)`

Updates the execution status of a script.

```lua
deps.set_status("build", "running", nil)
deps.set_status("build", "success", 0)
deps.set_status("build", "failed", 1)
```

#### `deps.get_status(script_name)`

Returns the current execution state for a script, or `nil` if not tracked.

```lua
local status = deps.get_status("build")
if status then
  print(status.status)    -- "pending", "running", "success", or "failed"
  print(status.exit_code) -- number or nil
  print(status.timestamp) -- os.time() value
end
```

#### `deps.reset_state()`

Clears all execution state.

## Script Configuration Fields

Each script table can include these dependency-related fields:

### `depends_on` (array of strings)

List of script names that must run before this script.

```lua
{
  name = "deploy",
  filename = "deploy.sh",
  depends_on = { "build", "test" },
}
```

### `run_after_deps` (string)

Controls when the script should execute based on dependency status:
- `"all"` (default): Execute only if all dependencies succeed
- `"any"`: Execute if at least one dependency succeeds
- `"none"`: Ignore dependency results, always execute

```lua
{
  name = "deploy",
  filename = "deploy.sh",
  depends_on = { "test", "lint" },
  run_after_deps = "any",  -- Deploy if either test or lint succeeds
}
```

## Error Handling

### Circular Dependencies

The module detects circular dependencies during validation:

```lua
local scripts = {
  { name = "a", filename = "a.sh", depends_on = { "b" } },
  { name = "b", filename = "b.sh", depends_on = { "a" } },  -- Circular!
}

local valid, err = deps.validate_dependencies(scripts)
-- valid = false
-- err = "Circular dependency detected involving script 'a'"
```

### Non-existent Dependencies

If a script depends on a script that doesn't exist, validation fails:

```lua
local scripts = {
  { name = "test", filename = "test.sh", depends_on = { "nonexistent" } },
}

local valid, err = deps.validate_dependencies(scripts)
-- valid = false
-- err = "Script 'test' depends on non-existent script 'nonexistent'"
```

## Examples

### Simple Build Pipeline

```lua
local deps = require('termlet.deps')

local scripts = {
  { name = "install", filename = "npm-install.sh" },
  { name = "build", filename = "build.sh", depends_on = { "install" } },
  { name = "test", filename = "test.sh", depends_on = { "build" } },
}

-- Validate
local valid, err = deps.validate_dependencies(scripts)
assert(valid, err)

-- Get execution order for "test"
local order = deps.resolve_execution_order("test", scripts)
-- order = { "install", "build", "test" }
```

### Diamond Dependencies

```lua
local deps = require('termlet.deps')

local scripts = {
  { name = "setup", filename = "setup.sh" },
  { name = "build_frontend", filename = "build_frontend.sh", depends_on = { "setup" } },
  { name = "build_backend", filename = "build_backend.sh", depends_on = { "setup" } },
  { name = "deploy", filename = "deploy.sh", depends_on = { "build_frontend", "build_backend" } },
}

local order = deps.resolve_execution_order("deploy", scripts)
-- order = { "setup", "build_frontend", "build_backend", "deploy" }
```

### Execution Policy Example

```lua
local deps = require('termlet.deps')

local scripts = {
  { name = "build", filename = "build.sh" },
  { name = "test", filename = "test.sh", depends_on = { "build" } },
  { name = "lint", filename = "lint.sh" },
  {
    name = "deploy_staging",
    filename = "deploy_staging.sh",
    depends_on = { "test", "lint" },
    run_after_deps = "any",  -- Deploy if either test or lint passes
  },
  {
    name = "deploy_prod",
    filename = "deploy_prod.sh",
    depends_on = { "test", "lint" },
    run_after_deps = "all",  -- Only deploy to prod if both pass
  },
}

-- Simulate execution results
deps.set_status("build", "success", 0)
deps.set_status("test", "success", 0)
deps.set_status("lint", "failed", 1)

-- Check execution eligibility
local can_stage, _ = deps.can_execute(scripts[4])  -- true (any policy, test passed)
local can_prod, err = deps.can_execute(scripts[5])  -- false (all policy, lint failed)
```

## Future Enhancements

The dependency system is designed to be extensible. Planned enhancements include:

- Integration into `termlet.setup()` so dependencies are resolved automatically when running scripts
- Menu integration with visual dependency indicators
- Parallel execution of independent dependencies
- Dependency visualization
- Retry logic for failed dependencies
