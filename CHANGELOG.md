# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-11-07

### Added

- Support for Windows ARM64 build target (`spacelint-windows-arm64.exe`).
- Terminal TTY detection to automatically enable color output only when connected to a terminal.
- Support for `NO_COLOR` environment variable and `--no-color` command-line flag to disable colored output.

## [0.2.0] - 2026-11-06

### Added

- Support for `-f` and `--format` output option with `agent`, `stylish`, and `default` modes.
- Command-line `--rules` option to list registered whitespace rules with categories, defaults, and fixability statuses in Markdown table format.
- Support for rule configuration options via `-C`, `-W`/`--warn`, `-A`/`--allow`, `-D`/`--deny`, and `-c`/`--config`.
- Support for `.spacelintrc.json`: rules and overrides.
- Comprehensive test fixtures and automated regression tests across all supported file formats.
