# spacelint

A fast, language-aware whitespace linter and fixer CLI written in the [Goose programming language](https://github.com/aardappel/goose).

## Features
- **Language Aware**: Understands file extensions and rules for TypeScript, JavaScript, JSON, YAML, XML, PROPS, INI, TOML, C++, C, Rust, Zig, Markdown, MDX, Goose, Vlang, D, Lua, Assembly, AssemblyScript, Kotlin, Java, Dart, Odin, Python, Go, Ruby, Shell, PHP, Swift, C#, Scala, CSS, SQL, R, Julia, Perl, Elixir, Erlang, Haskell, Elm, PureScript, GraphQL, Dockerfile, Makefile, Nix, Terraform, Vue, Svelte, Astro, Fortran, Ada, Pascal, OCaml, Clojure, F#, Groovy, PowerShell, Solidity, Nim, Crystal, CMake, Protobuf, Shaders, GameDev, CSV, TSV, and more.
- **Rich Diagnostics Output**: Diagnostics and summaries formatted with line numbers, code snippets, caret underlines, and timing stats.
- **Multiple Output Formats**:
  - `-f default` / `--format default`: Full visual diagnostics with code snippets and caret underlines.
  - `-f agent` / `--format agent`: Compact, uncolored single-line format (`<file>:<line>:<col>: warning spacelint(<rule>): <message>`).
  - `-f stylish` / `--format stylish`: ESLint-compatible stylish format with underlined file headers, aligned columns, and summary.
- **Rules & Categories**:
  - `correctness`: `no-trailing-spaces`, `no-carriage-return`, `no-mixed-spaces-and-tabs`.
  - `style`: `indent`.
- **Rule Configuration**:
  - Turn off rules/categories: `-A` / `--allow` (e.g. `-A no-unused-vars`, `-A correctness`, `-A all`).
  - Enable rules/categories as warnings: `-W` / `--warn` (e.g. `-W no-debugger`).
  - Enable rules/categories as errors: `-D` / `--deny` (e.g. `-D no-console`, `-D correctness`).
  - Configure rule severity and options via `-C` (e.g. `-C indent=2`, `-C 'indent=["error", 2]'`, `-C 'indent=["warn", "auto"]'`).
  - Configuration file via `-c` / `--config` (e.g. `spacelint -c .spacelintrc.json`).
- **Comment and Multiline String Awareness**:
  - Multiline comments across syntax styles (`/* ... */`, `<!-- ... -->`, `#`, `;`).
  - JSDoc / TSDoc support: lines inside block comments starting with `*` can use spaces to align the `*` characters without triggering mixed-indentation warnings.
  - Multiline strings / raw literals preserve interior whitespace and embedded comment-like characters verbatim.
- **Piping Support**: Full support for stdin/stdout streams (e.g. `spacelint --fix > file.txt`).

## Installation

`spacelint` is distributed as signed, bare standalone executables across Linux, macOS, Windows, and Termux/Android.

If you have [packslip](https://packslip.dev) or [mise](https://mise.jdx.dev) installed:

```bash
packslip install github.com/Mopsgamer/spacelint
# or (recommended)
mise use -g packslip:github.com/Mopsgamer/spacelint
```

Packslip verifies the cryptographic sigstore attestation (`packslip.sigstore.json`), downloads the appropriate binary for your OS and architecture, and links it into `~/.local/bin/`.

### In Termux (Android)

Termux runs Linux on ARM64. You can install and use mise for this or download the binary directly:

```bash
# Direct download into Termux bin
curl -fsSL -o $PREFIX/bin/spacelint https://github.com/Mopsgamer/spacelint/releases/latest/download/spacelint-linux-arm64
chmod +x $PREFIX/bin/spacelint
```

### Direct Download (Prebuilt Binaries)

Download the bare executable matching your operating system and architecture from the [Releases page](https://github.com/Mopsgamer/spacelint/releases):

| Platform | Target Architecture | Binary Asset |
|---|---|---|
| **Linux** | x86_64 | `spacelint-linux-x64` |
| **Linux / Android (Termux)** | ARM64 (aarch64) | `spacelint-linux-arm64` |
| **macOS** | Intel (x86_64) | `spacelint-darwin-x64` |
| **macOS** | Apple Silicon (arm64) | `spacelint-darwin-arm64` |
| **Windows** | x86_64 | `spacelint-windows-x64.exe` |

On Linux / macOS:
```bash
curl -fsSL -o /usr/local/bin/spacelint https://github.com/Mopsgamer/spacelint/releases/latest/download/spacelint-linux-x64
chmod +x /usr/local/bin/spacelint
```

### Building From Source

Ensure `goose` is in your `PATH`:
```bash
git clone https://github.com/Mopsgamer/spacelint.git
cd spacelint
goose build spacelint.goose
./spacelint --help
```

To run tests:

```bash
python3 tests/run_tests.py
```

## Configuration Guide

`spacelint` supports configuration via `.spacelintrc.json` with full JSON Schema validation for editor autocomplete and documentation.

### Initializing Configuration

To set up a new configuration file in your project, run:

```bash
spacelint --init
```

This creates a `.spacelintrc.json` configuration file:

```json
{
  "$schema": "https://raw.githubusercontent.com/Mopsgamer/spacelint/main/configuration_schema.json",
  "categories": {
    "correctness": "warn",
    "style": "warn"
  },
  "rules": {
    "no-trailing-spaces": "warn",
    "no-carriage-return": "warn",
    "no-mixed-spaces-and-tabs": "warn",
    "indent": "warn"
  },
  "overrides": []
}
```

### JSON Schema Integration

`configuration_schema.json` provides a complete draft-07 JSON Schema for spacelint configurations. By referencing the schema URL in your `.spacelintrc.json` file:

```json
{
  "$schema": "https://raw.githubusercontent.com/Mopsgamer/spacelint/main/configuration_schema.json"
}
```

Modern IDEs and code editors (such as VS Code, Neovim with YAML/JSON Language Server, and JetBrains IDEs) automatically validate your configuration and offer auto-completion and documentation hovers for available rules, severities, and options. Alternatively, you can download `configuration_schema.json` into your repository and reference it relatively (e.g. `"$schema": "./configuration_schema.json"`).

### Categories and Rules

Spacelint classifies rules into categories:
- **`correctness`**: Catches whitespace errors and syntax anomalies:
  - `no-trailing-spaces`: Disallows trailing whitespace at line endings.
  - `no-carriage-return`: Disallows carriage return (`\r`) characters.
  - `no-mixed-spaces-and-tabs`: Disallows mixing tabs and spaces in indentation.
- **`style`**: Formatting and indentation style preferences:
  - `indent`: Enforces consistent space or tab indentation.
- **`all`**: Targets all rules at once.

### Severity Levels

Categories and rules support the following severity values:
- `"off"` / `"allow"` / `0`: Turn off the rule or category.
- `"warn"` / `1`: Report issues as warnings without failing the exit code.
- `"error"` / `"deny"` / `2`: Report issues as errors (returns exit code `1` on violation).

### Indentation Configuration

The `indent` rule can be configured to enforce specific indentation:
- **Spaces**: `["warn", 2]`, `["error", 4]`, or simply `2` / `4`.
- **Tabs**: `["warn", "tabs"]` or `"tabs"`.
- **Auto-detection**: `["warn", "auto"]` or `"auto"`.
- **Off**: `"off"`.

### Overrides

Projects often have files with different conventions (e.g. 2 spaces in Markdown/YAML and 4 spaces in source code), or directories containing fixture files or third-party assets that should not be linted.

Use the `overrides` array to target files or directories using glob patterns:

```json
{
  "$schema": "https://raw.githubusercontent.com/Mopsgamer/spacelint/main/configuration_schema.json",
  "categories": {
    "correctness": "warn"
  },
  "rules": {
    "indent": ["warn", 4]
  },
  "overrides": [
    {
      "files": ["*.json", "*.md", "*.yml", "*.yaml"],
      "rules": {
        "indent": ["warn", 2]
      }
    },
    {
      "files": ["vendor/**", "fixtures/**"],
      "categories": {
        "all": "off"
      }
    }
  ]
}
```

### Using Your Configuration

Point spacelint to your configuration file with `-c` or `--config`:

```bash
# Lint current directory with configuration
spacelint -c .spacelintrc.json .

# Automatically fix issues according to configuration
spacelint -c .spacelintrc.json --fix .

# Override specific rules from CLI
spacelint -c .spacelintrc.json -D no-trailing-spaces .
```
