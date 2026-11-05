# spacelint

A fast, language-aware whitespace linter and fixer CLI written in the [Goose programming language](https://github.com/aardappel/goose).

## Features
- **Language Aware**: Understands file extensions and rules for TypeScript, JavaScript, JSON, YAML, XML, PROPS, INI, TOML, C++, C, Rust, Zig, Markdown, MDX, Goose, Vlang, D, Lua, Assembly, AssemblyScript, Kotlin, Java, Dart, Odin, Python, Go, Ruby, Shell, PHP, Swift, C#, Scala, CSS, SQL, R, Julia, Perl, Elixir, Erlang, Haskell, Elm, PureScript, GraphQL, Dockerfile, Makefile, Nix, Terraform, Vue, Svelte, Astro, Fortran, Ada, Pascal, OCaml, Clojure, F#, Groovy, PowerShell, Solidity, Nim, Crystal, CMake, Protobuf, Shaders, GameDev, CSV, TSV, and more.
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

## Installation

`spacelint` is distributed as signed, bare standalone executables across Linux, macOS, Windows, and Termux/Android.

### Using Packslip (Recommended)

If you have [packslip](https://packslip.dev) or [mise](https://mise.jdx.dev) installed:
```bash
packslip install github.com/Mopsgamer/spacelint
```
Packslip verifies the cryptographic sigstore attestation (`packslip.sigstore.json`), downloads the appropriate binary for your OS and architecture, and links it into `~/.local/bin/`.

### In Termux (Android)

Termux runs Linux on ARM64. You can install via packslip or download the binary directly:
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
