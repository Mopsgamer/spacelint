# spacelint

A fast, language-aware whitespace linter and fixer CLI written in the [Goose programming language](https://github.com/aardappel/goose).

## Features
- **Language Aware**: Understands file extensions and rules for TypeScript, JavaScript, JSON, YAML, XML, PROPS, INI, TOML, C++, C, Rust, Zig, and more.
- **Oxlint Compatible Output**: Diagnostics and summaries formatted with line numbers, code snippets, caret underlines, and timing stats.
- **Rules**:
  - Trailing whitespace detection and fixing (`no-trailing-spaces`).
  - Carriage return normalization (`no-carriage-return`).
  - Mixed tabs and spaces detection (`no-mixed-spaces-and-tabs`).
  - Indentation enforcement (`indent`).
- **Comment and Multiline String Awareness**:
  - Multiline comments across syntax styles (`/* ... */`, `<!-- ... -->`, `#`, `;`).
  - JSDoc / TSDoc support: lines inside block comments starting with `*` can use spaces to align the `*` characters without triggering mixed-indentation warnings.
  - Multiline strings / raw literals preserve interior whitespace and embedded comment-like characters verbatim.
- **Piping Support**: Full support for stdin/stdout streams (e.g. `spacelint --fix > file.txt`).
- **Flexible Indentation Options**:
  - `--indent tabs` (default)
  - `--indent <N>` (e.g. `--indent 2`, `--indent 4`)
  - `--indent auto` (autodetects tabs vs spaces per file)
  - `--indent auto.<ext>` (autodetects for files with `<ext>`, tabs for all others)

## Building & Running

Ensure `goose` is in your `PATH`:
```bash
goose build spacelint.goose
./spacelint --help
```

To run tests:
```bash
python3 tests/run_tests.py
```
