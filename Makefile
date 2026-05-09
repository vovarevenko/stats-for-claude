.PHONY: gen

# Run after Claude adds new Swift files to the project.
# Normal Xcode development (Cmd+R) does NOT require this.
gen:
	xcodegen generate
	python3 scripts/add_xcstrings.py
