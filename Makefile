.PHONY: build clean-build run test help

help:
	@echo "MasterOfDrums build targets:"
	@echo "  make build        - Build the project"
	@echo "  make clean-build  - Clean build (remove .build and rebuild)"
	@echo "  make run          - Run the app"
	@echo "  make test         - Run all tests"
	@echo "  make clean        - Remove .build directory"

build:
	swift build

clean-build:
	swift package clean && swift build

run:
	swift run MasterOfDrums

test:
	swift test

clean:
	swift package clean
