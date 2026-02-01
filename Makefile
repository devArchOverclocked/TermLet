.PHONY: test test-file clean help

# Default target
help:
	@echo "Available targets:"
	@echo "  make test       - Run all tests"
	@echo "  make test-file  - Run a specific test file (usage: make test-file FILE=tests/termlet_spec.lua)"
	@echo "  make clean      - Clean up test artifacts"
	@echo "  make help       - Show this help message"

# Run all tests
test:
	@echo "Running all tests..."
	nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Run a specific test file
# Usage: make test-file FILE=tests/termlet_spec.lua
test-file:
ifndef FILE
	@echo "Error: FILE parameter required"
	@echo "Usage: make test-file FILE=tests/termlet_spec.lua"
	@exit 1
endif
	@echo "Running tests in $(FILE)..."
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile $(FILE)"

# Clean up any test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@find tests -name "*.swp" -delete 2>/dev/null || true
	@find tests -name "*~" -delete 2>/dev/null || true
	@echo "Clean complete"
