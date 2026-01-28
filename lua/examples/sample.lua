return {
	{
		"devArchOevrclocked/termlet",
		event = "VeryLazy",
		opts = {
			root_dir = "~/Path/To/Files/", -- Global root for all scripts
			scripts = {
				{
					name = "build",
					filename = "build", -- Just the filename!
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
		},
	},
}
