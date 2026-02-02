# Script Dependencies and Chaining

TermLet supports automatic dependency management and script chaining, allowing you to define relationships between scripts and execute complex workflows with ease.

## Features

- **Automatic Dependency Resolution**: Define dependencies between scripts and TermLet will execute them in the correct order
- **Circular Dependency Detection**: Prevents infinite loops by detecting circular dependencies at validation time
- **Flexible Execution Policies**: Control when scripts run based on dependency outcomes
- **Menu Integration**: Visual indicators show which scripts have dependencies
- **Parallel Execution Support**: Configure scripts to run dependencies in parallel (infrastructure in place)
- **Failure Handling**: Control whether to stop or continue when dependencies fail

## Configuration

### Basic Dependency Example

```lua
require('termlet').setup({
  scripts = {
    {
      name = "install",
      filename = "install.sh",
      description = "Install dependencies",
    },
    {
      name = "build",
      filename = "build.sh",
      description = "Build project",
      depends_on = { "install" },  -- Run install first
    },
    {
      name = "test",
      filename = "test.sh",
      description = "Run tests",
      depends_on = { "build" },
      run_after_deps = "all",  -- Only run if all deps succeed (default)
    },
  },
})
```

### Dependency Configuration Options

Each script can have the following dependency-related fields:

#### `depends_on` (array of strings)
List of script names that must run before this script.

```lua
{
  name = "deploy",
  filename = "deploy.sh",
  depends_on = { "build", "test" },
}
```

#### `run_after_deps` (string)
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

#### `parallel_deps` (boolean)
Whether to run dependencies in parallel (infrastructure in place for future implementation).

```lua
{
  name = "deploy",
  filename = "deploy.sh",
  depends_on = { "test", "lint" },
  parallel_deps = true,  -- Run test and lint concurrently
}
```

#### `continue_on_failure` (boolean)
Whether to continue the execution chain if this script fails.

```lua
{
  name = "lint",
  filename = "lint.sh",
  continue_on_failure = true,  -- Don't stop the chain if linting fails
}
```

## Usage

### Running Scripts with Dependencies

Use the `run_with_deps` function to execute a script and all its dependencies:

```lua
-- Run deploy and all its dependencies (install → build → test → deploy)
require('termlet').run_with_deps('deploy')

-- Run just test and its dependencies (install → build → test)
require('termlet').run_with_deps('test')
```

### Viewing Dependency Chains

Get a formatted view of the execution order:

```lua
local chain = require('termlet').get_dependency_chain('deploy')
-- Returns: "install → build → test → deploy"
print(chain)
```

### Validating Dependencies

Check for errors in your dependency configuration:

```lua
local valid, error = require('termlet').validate_dependencies()
if not valid then
  print("Dependency error: " .. error)
end
```

### Menu Integration

When you open the TermLet menu (`require('termlet').open_menu()`), scripts with dependencies show an indicator:

```
> build [→1]       Build project
  test [→1]        Run tests
  deploy [→2]      Deploy to production
```

The `[→N]` indicator shows how many direct dependencies the script has.

## Complex Dependency Graphs

TermLet supports complex dependency graphs including diamond dependencies:

```lua
require('termlet').setup({
  scripts = {
    {
      name = "setup",
      filename = "setup.sh",
    },
    {
      name = "build_frontend",
      filename = "build_frontend.sh",
      depends_on = { "setup" },
    },
    {
      name = "build_backend",
      filename = "build_backend.sh",
      depends_on = { "setup" },
    },
    {
      name = "deploy",
      filename = "deploy.sh",
      depends_on = { "build_frontend", "build_backend" },
    },
  },
})
```

In this example:
- `setup` runs first
- `build_frontend` and `build_backend` run after `setup` completes
- `deploy` runs after both builds complete

## Error Handling

### Circular Dependencies

TermLet detects circular dependencies and prevents them:

```lua
-- This configuration will fail validation:
{
  scripts = {
    { name = "a", filename = "a.sh", depends_on = { "b" } },
    { name = "b", filename = "b.sh", depends_on = { "a" } },  -- Circular!
  }
}
```

### Non-existent Dependencies

If a script depends on a non-existent script, validation will fail:

```lua
{
  name = "test",
  depends_on = { "nonexistent" },  -- Error: script not found
}
```

### Execution Failures

By default, if a dependency fails, the entire chain stops. You can customize this behavior:

```lua
{
  name = "lint",
  filename = "lint.sh",
  continue_on_failure = true,  -- Continue even if lint fails
}
```

## Advanced Usage

### Accessing the Dependency Module

For advanced use cases, you can access the dependency module directly:

```lua
local deps = require('termlet').deps

-- Reset execution state
deps.reset_state()

-- Get execution status
local status = deps.get_status("build")
if status then
  print("Status: " .. status.status)  -- "pending", "running", "success", or "failed"
  print("Exit code: " .. tostring(status.exit_code))
end

-- Build dependency graph
local graph = deps.build_dependency_graph(scripts)

-- Resolve execution order
local order, err = deps.resolve_execution_order("deploy", scripts)
```

## Configuration Options

### Global Dependency Settings

```lua
require('termlet').setup({
  dependencies = {
    enabled = true,        -- Enable/disable dependency system
    show_in_menu = true,   -- Show dependency indicators in menu
  },
  -- ... scripts configuration
})
```

## Examples

### Simple Build Pipeline

```lua
require('termlet').setup({
  scripts = {
    { name = "install", filename = "npm-install.sh" },
    { name = "build", filename = "build.sh", depends_on = { "install" } },
    { name = "test", filename = "test.sh", depends_on = { "build" } },
  },
})

-- Run the entire pipeline
require('termlet').run_with_deps('test')
```

### Multi-Environment Deploy

```lua
require('termlet').setup({
  scripts = {
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
  },
})
```

### Conditional Execution

```lua
require('termlet').setup({
  scripts = {
    { name = "build", filename = "build.sh" },
    {
      name = "optional_lint",
      filename = "lint.sh",
      continue_on_failure = true,  -- Don't block the chain if this fails
    },
    {
      name = "deploy",
      filename = "deploy.sh",
      depends_on = { "build", "optional_lint" },
      run_after_deps = "any",  -- Deploy if at least build succeeds
    },
  },
})
```

## Troubleshooting

### Dependency validation fails

Run validation to see the specific error:

```lua
local valid, err = require('termlet').validate_dependencies()
if not valid then
  vim.notify("Dependency error: " .. err, vim.log.levels.ERROR)
end
```

### Execution stops unexpectedly

Check if a dependency failed. By default, failures stop the chain. Add `continue_on_failure = true` to scripts that should not block execution.

### Circular dependency detected

Review your dependency graph to find the cycle. Each script should only depend on scripts that don't transitively depend on it.

## API Reference

### Main Functions

- `require('termlet').run_with_deps(script_name)`: Execute a script with all its dependencies
- `require('termlet').get_dependency_chain(script_name)`: Get formatted dependency chain string
- `require('termlet').validate_dependencies()`: Validate all script dependencies

### Dependency Module Functions

- `deps.validate_dependencies(scripts)`: Check for circular deps and missing scripts
- `deps.resolve_execution_order(script_name, scripts)`: Get topologically sorted execution order
- `deps.build_dependency_graph(scripts)`: Build adjacency list representation
- `deps.can_execute(script)`: Check if a script can run based on dependency status
- `deps.set_status(script_name, status, exit_code)`: Update execution state
- `deps.get_status(script_name)`: Get execution state
- `deps.reset_state()`: Clear all execution state

## Future Enhancements

The dependency system is designed to be extensible. Future enhancements may include:

- True parallel execution of independent dependencies
- Dependency visualization in the menu UI
- Conditional dependencies based on environment or configuration
- Retry logic for failed dependencies
- Dependency caching and incremental execution
