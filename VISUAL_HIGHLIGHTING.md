# Visual Highlighting of Stack Trace File Paths

This document describes the visual highlighting feature for detected file paths in stack traces.

## Overview

TermLet can now visually highlight file paths detected in stack traces, making them easier to identify and distinguish from regular terminal output. This works similar to how IDEs like IntelliJ highlight hyperlinks in their terminal output.

## Features

- **Automatic highlighting** of detected file paths in terminal output
- **Configurable styles**: underline, color, both, or none
- **Customizable highlight group** for integration with your colorscheme
- **Real-time highlighting** as output is generated
- **Works with all supported languages** (Python, C#, JavaScript, Java, etc.)

## Configuration

### Basic Setup

```lua
require('termlet').setup({
  stacktrace = {
    enabled = true,
    highlight = {
      enabled = true,              -- Enable visual highlighting (default: true)
      style = "underline",         -- Highlight style (default: "underline")
      hl_group = "TermLetStackTracePath", -- Highlight group (default: "TermLetStackTracePath")
    },
  },
})
```

### Highlight Styles

The `style` option supports the following values:

- **`"underline"`** - Underline file paths (default)
- **`"color"`** - Apply color highlighting only (no underline)
- **`"both"`** - Apply both color and underline
- **`"none"`** - Disable visual highlighting (detection still works)

### Custom Colorscheme Integration

You can customize the highlight colors to match your colorscheme:

```lua
-- For dark colorschemes
vim.api.nvim_set_hl(0, 'TermLetStackTracePath', {
  underline = true,
  fg = '#ff6b6b',  -- Red for errors
  bold = true,
})

-- For light colorschemes
vim.api.nvim_set_hl(0, 'TermLetStackTracePath', {
  underline = true,
  fg = '#0066cc',  -- Dark blue
})
```

## Runtime Control

You can enable/disable highlighting at runtime:

```lua
-- Disable highlighting
require('termlet').highlight.disable()

-- Enable highlighting
require('termlet').highlight.enable()

-- Check if enabled
local enabled = require('termlet').highlight.is_enabled()

-- Change style at runtime
require('termlet').highlight.setup({ style = 'both' })
```

## How It Works

1. When a terminal process outputs text, TermLet detects file paths using registered parsers
2. Detected file paths are visually highlighted using Neovim's extmark API
3. Highlights persist during terminal scroll and window resize
4. Highlights are automatically cleared when starting a new process

## Examples

### Python Stack Trace

```python
Traceback (most recent call last):
  File "/path/to/file.py", line 42, in main
    result = process(data)
TypeError: something went wrong
```

The file path `/path/to/file.py` will be visually highlighted.

### C# Stack Trace

```csharp
at MyClass.Method() in /path/to/File.cs:line 42
```

The file path `/path/to/File.cs` will be visually highlighted.

### JavaScript Stack Trace

```javascript
at functionName (/path/to/file.js:42:15)
```

The file path `/path/to/file.js` will be visually highlighted.

## Accessibility

- The default style uses **underline** rather than color-only to support colorblind users
- Users can configure high-contrast colors for better visibility
- The highlighting doesn't interfere with screen readers or terminal navigation

## Performance

- Highlighting uses Neovim's efficient extmark API
- Only detected file paths are highlighted (minimal overhead)
- Highlights are applied incrementally as output is generated

## Testing

To test the visual highlighting feature:

1. Run the test suite:
   ```bash
   nvim --headless -u tests/minimal_init.lua -c "lua require('plenary.test_harness').test_directory('tests/highlight_spec.lua', {minimal_init = 'tests/minimal_init.lua'})"
   ```

2. Manual testing with Python:
   ```bash
   cd tests
   python3 test_python_error.py
   ```
   Observe the highlighted file paths in the terminal output.

## Troubleshooting

### Highlights not appearing

1. Check if highlighting is enabled:
   ```lua
   :lua print(require('termlet').highlight.is_enabled())
   ```

2. Verify the style is not set to "none":
   ```lua
   :lua print(require('termlet').highlight.get_config().style)
   ```

3. Check if stack trace detection is enabled:
   ```lua
   :lua print(require('termlet').stacktrace.is_enabled())
   ```

### Custom highlight group not working

Make sure you define the highlight group **after** calling `setup()`:

```lua
require('termlet').setup({ ... })

-- Define custom highlight after setup
vim.api.nvim_set_hl(0, 'TermLetStackTracePath', {
  underline = true,
  fg = '#your_color',
})
```

## Related Features

- **Stack Trace Detection**: Automatically detects file references in stack traces
- **Jump to File**: Press `<CR>` on a highlighted path to jump to the file
- **Multiple Languages**: Supports Python, C#, JavaScript, Java, and many more
