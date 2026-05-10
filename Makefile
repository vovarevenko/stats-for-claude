.PHONY: gen test lint format clean

# Regenerates StatsForClaude.xcodeproj from project.yml and patches in the
# Localizable.xcstrings reference. Run after Claude (or anyone) adds new
# Swift files; normal Cmd+R from Xcode does NOT need this.
gen:
	xcodegen generate
	python3 scripts/add_xcstrings.py

# Run the SPM test suite for both kit modules. App-level UI lives outside
# this scope and has to be exercised through Xcode.
test:
	cd StatsForClaudeKit && swift test

# Static analysis. Requires `brew install swiftlint`.
lint:
	swiftlint --strict

# Auto-format the codebase. Requires `brew install swiftformat`.
format:
	swiftformat .

# Lint check for CI: format-only diff, no writes.
format-check:
	swiftformat --lint .

clean:
	rm -rf .build DerivedData StatsForClaudeKit/.build StatsForClaudeKit/.swiftpm/configuration
