return {
	{
		"devArchOevrclocked/termlet",
		event = "VeryLazy",
		opts = {
			root_dir = "~/Path/To/Files/", -- Global root for all scripts
			scripts = {
				-- Plain filename: TermLet searches recursively from root_dir
				{
					name = "build",
					filename = "build.sh",
					-- Optional: specify custom search directories
					search_dirs = { ".", "Path", "To", "Files" },
				},
				{
					name = "precommit",
					filename = "precommit",
				},
				{
					name = "test",
					filename = "test",
				},
				-- Absolute path: runs a script outside of root_dir
				{
					name = "deploy",
					filename = "~/scripts/deploy.sh",
				},
				-- Relative path with subdirectory: resolved from root_dir,
				-- falls back to recursive basename search if not found
				{
					name = "lint",
					filename = "ci/lint.sh",
					root_dir = "~/my-project",
				},
			},
			terminal = {
				position = "bottom",
				height_ratio = 0.2,
				border = "rounded", -- or custom: { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
				highlights = {
					border = "FloatBorder",
					title = "Title",
					background = "NormalFloat",
				},
				title_format = " {icon} {name} {status} ",
				title_icon = "",
				title_pos = "center", -- "left", "center", "right"
				show_status = true,
				status_icons = {
					running = "●",
					success = "✓",
					error = "✗",
				},
			},
		},
		keys = {
			{
				"<leader>b",
				function()
					require("termlet").run_build()
				end,
				desc = "TermLet: Build project",
			},
			{
				"<leader>tt",
				function()
					require("termlet").run_test()
				end,
				desc = "TermLet: Test project",
			},
			{
				"<leader>P",
				function()
					require("termlet").run_precommit()
				end,
				desc = "TermLet: Precommit",
			},
			{
				"<leader>bl",
				function()
					require("termlet").list_scripts()
				end,
				desc = "TermLet: List scripts",
			},
			{
				"<leader>bc",
				function()
					require("termlet").close_terminal()
				end,
				desc = "TermLet: Close terminal",
			},
			{
				"<leader>ts",
				function()
					require("termlet").open_menu()
				end,
				desc = "Open TermLet Script Menu",
			},
			-- Keybinding configuration UI
			-- Opens a visual interface to set/change keybindings for scripts.
			-- Two modes are available:
			--   [c] Capture mode: Press keys in real-time to record a sequence
			--   [i] Input mode:   Type vim notation directly (e.g. <leader>b)
			-- Keybindings persist across Neovim sessions automatically.
			{
				"<leader>tk",
				function()
					require("termlet").toggle_keybindings()
				end,
				desc = "TermLet: Toggle Keybinding Config",
			},
		},
	},
}
