// Language detection and comment/string context tracking for spacelint.
import std;
import os;

enum Lang {
    TypeScript,
    JavaScript,
    JSON,
    YAML,
    XML,
    PROPS,
    INI,
    TOML,
    CPP,
    C,
    Rust,
    Zig,
    Markdown,
    MDX,
    Goose,
    Vlang,
    D,
    Lua,
    Assembly,
    AssemblyScript,
    Kotlin,
    Java,
    Dart,
    Odin,
    Python,
    Go,
    Ruby,
    Shell,
    PHP,
    Swift,
    CSharp,
    Scala,
    CSS,
    SQL,
    R,
    Julia,
    Perl,
    Elixir,
    Erlang,
    Haskell,
    Elm,
    PureScript,
    GraphQL,
    Dockerfile,
    Makefile,
    Nix,
    Terraform,
    Vue,
    Svelte,
    Astro,
    Fortran,
    Ada,
    Pascal,
    OCaml,
    Clojure,
    FSharp,
    Groovy,
    PowerShell,
    Solidity,
    Nim,
    Crystal,
    CMake,
    Protobuf,
    Shader,
    Tcl,
    Awk,
    Cobol,
    Smalltalk,
    Verilog,
    VHDL,
    CoffeeScript,
    Haxe,
    Mojo,
    Jsonnet,
    Dhall,
    Typst,
    KDL,
    CUE,
    Rego,
    GoTemplate,
    Apex,
    Ballerina,
    Ceylon,
    Chapel,
    GDScript,
    Hack,
    MoonScript,
    QML,
    Raku,
    ReasonML,
    Rescript,
    Starlark,
    Vala,
    Wolfram,
    Xtend,
    GameDev,
    Papyrus,
    CSV,
    TSV,
    Unknown
}

fn equals_ignore_case(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    var i = 0;
    while i < a.len {
        let ca = if a[i] >= 'A' && a[i] <= 'Z' { (a[i] + 32) } else { a[i] };
        let cb = if b[i] >= 'A' && b[i] <= 'Z' { (b[i] + 32) } else { b[i] };
        if ca != cb { return false; }
        i++;
    }
    return true;
}

fn get_filename_slice(path: const u8[:]) -> const u8[:] {
    var i = path.len - 1;
    while i >= 0 && path[i] != '/' && path[i] != '\\' {
        i--;
    }
    return path[i + 1..];
}

fn get_extension(path: const u8[:]) -> u8[..16] {
    var out: u8[..16] = [];
    var i = path.len - 1;
    while i >= 0 && path[i] != '/' && path[i] != '\\' {
        if path[i] != '.' { i--; continue; }
        let ext = path[i + 1..];
        for b in ext {
            let c = if b >= 'A' && b <= 'Z' { (b + 32) } else { b };
            if out.len < 16 {
                out.push(c);
            }
        }
        return out;
    }
    return out;
}

fn detect_lang(path: const u8[:]) -> Lang {
    let fname = get_filename_slice(path);
    if equals_ignore_case(fname, "dockerfile") {
        return Lang.Dockerfile;
    } else if equals_ignore_case(fname, "makefile") || equals_ignore_case(fname, "gnumakefile") {
        return Lang.Makefile;
    } else if equals_ignore_case(fname, "cmakelists.txt") {
        return Lang.CMake;
    } else if equals_ignore_case(fname, "build") || equals_ignore_case(fname, "workspace") {
        return Lang.Starlark;
    }

    let ext = get_extension(path);
    if ext == "ts" || ext == "tsx" || ext == "mts" || ext == "cts" {
        return Lang.TypeScript;
    } else if ext == "js" || ext == "jsx" || ext == "mjs" || ext == "cjs" {
        return Lang.JavaScript;
    } else if ext == "json" || ext == "jsonc" {
        return Lang.JSON;
    } else if ext == "yaml" || ext == "yml" {
        return Lang.YAML;
    } else if ext == "xml" || ext == "svg" || ext == "html" || ext == "htm" {
        return Lang.XML;
    } else if ext == "properties" || ext == "props" {
        return Lang.PROPS;
    } else if ext == "ini" || ext == "conf" {
        return Lang.INI;
    } else if ext == "toml" {
        return Lang.TOML;
    } else if ext == "cpp" || ext == "cc" || ext == "cxx" || ext == "hpp" || ext == "hh" {
        return Lang.CPP;
    } else if ext == "c" || ext == "h" {
        return Lang.C;
    } else if ext == "rs" {
        return Lang.Rust;
    } else if ext == "zig" {
        return Lang.Zig;
    } else if ext == "md" || ext == "markdown" {
        return Lang.Markdown;
    } else if ext == "mdx" {
        return Lang.MDX;
    } else if ext == "goose" {
        return Lang.Goose;
    } else if ext == "v" || ext == "vsh" {
        return Lang.Vlang;
    } else if ext == "d" || ext == "di" {
        return Lang.D;
    } else if ext == "lua" {
        return Lang.Lua;
    } else if ext == "s" || ext == "asm" {
        return Lang.Assembly;
    } else if ext == "as" {
        return Lang.AssemblyScript;
    } else if ext == "kt" || ext == "kts" {
        return Lang.Kotlin;
    } else if ext == "java" {
        return Lang.Java;
    } else if ext == "dart" {
        return Lang.Dart;
    } else if ext == "odin" {
        return Lang.Odin;
    } else if ext == "py" || ext == "pyw" || ext == "pyi" {
        return Lang.Python;
    } else if ext == "go" {
        return Lang.Go;
    } else if ext == "rb" {
        return Lang.Ruby;
    } else if ext == "sh" || ext == "bash" || ext == "zsh" {
        return Lang.Shell;
    } else if ext == "php" {
        return Lang.PHP;
    } else if ext == "swift" {
        return Lang.Swift;
    } else if ext == "cs" {
        return Lang.CSharp;
    } else if ext == "scala" || ext == "sc" {
        return Lang.Scala;
    } else if ext == "css" || ext == "scss" || ext == "sass" || ext == "less" || ext == "pcss" || ext == "postcss" || ext == "sss" || ext == "styl" || ext == "stylus" {
        return Lang.CSS;
    } else if ext == "gotmpl" || ext == "gohtml" || ext == "tmpl" || ext == "tpl" {
        return Lang.GoTemplate;
    } else if ext == "sql" {
        return Lang.SQL;
    } else if ext == "r" || ext == "rmd" {
        return Lang.R;
    } else if ext == "jl" {
        return Lang.Julia;
    } else if ext == "pl" || ext == "pm" {
        return Lang.Perl;
    } else if ext == "ex" || ext == "exs" {
        return Lang.Elixir;
    } else if ext == "erl" || ext == "hrl" {
        return Lang.Erlang;
    } else if ext == "hs" || ext == "lhs" {
        return Lang.Haskell;
    } else if ext == "elm" {
        return Lang.Elm;
    } else if ext == "purs" {
        return Lang.PureScript;
    } else if ext == "graphql" || ext == "gql" {
        return Lang.GraphQL;
    } else if ext == "dockerfile" {
        return Lang.Dockerfile;
    } else if ext == "mk" {
        return Lang.Makefile;
    } else if ext == "nix" {
        return Lang.Nix;
    } else if ext == "tf" || ext == "hcl" {
        return Lang.Terraform;
    } else if ext == "vue" {
        return Lang.Vue;
    } else if ext == "svelte" {
        return Lang.Svelte;
    } else if ext == "astro" {
        return Lang.Astro;
    } else if ext == "f" || ext == "f90" || ext == "f95" || ext == "for" {
        return Lang.Fortran;
    } else if ext == "adb" || ext == "ads" {
        return Lang.Ada;
    } else if ext == "pas" || ext == "pp" {
        return Lang.Pascal;
    } else if ext == "ml" || ext == "mli" {
        return Lang.OCaml;
    } else if ext == "clj" || ext == "cljs" || ext == "cljc" || ext == "edn" || ext == "lisp" || ext == "lsp" || ext == "scm" || ext == "rkt" {
        return Lang.Clojure;
    } else if ext == "fs" || ext == "fsx" || ext == "fsi" {
        return Lang.FSharp;
    } else if ext == "groovy" || ext == "gvy" || ext == "gradle" {
        return Lang.Groovy;
    } else if ext == "ps1" || ext == "psm1" || ext == "psd1" {
        return Lang.PowerShell;
    } else if ext == "sol" {
        return Lang.Solidity;
    } else if ext == "nim" || ext == "nims" {
        return Lang.Nim;
    } else if ext == "cr" {
        return Lang.Crystal;
    } else if ext == "cmake" {
        return Lang.CMake;
    } else if ext == "proto" {
        return Lang.Protobuf;
    } else if ext == "glsl" || ext == "wgsl" || ext == "vert" || ext == "frag" || ext == "comp" || ext == "geom" || ext == "tesc" || ext == "tese" || ext == "hlsl" || ext == "hlsli" || ext == "fx" || ext == "fxh" || ext == "metal" || ext == "cg" || ext == "cginc" || ext == "cl" || ext == "gdshader" {
        return Lang.Shader;
    } else if ext == "tcl" {
        return Lang.Tcl;
    } else if ext == "awk" {
        return Lang.Awk;
    } else if ext == "cbl" || ext == "cob" || ext == "cpy" {
        return Lang.Cobol;
    } else if ext == "st" {
        return Lang.Smalltalk;
    } else if ext == "sv" || ext == "svh" {
        return Lang.Verilog;
    } else if ext == "vhd" || ext == "vhdl" {
        return Lang.VHDL;
    } else if ext == "coffee" || ext == "cson" {
        return Lang.CoffeeScript;
    } else if ext == "hx" {
        return Lang.Haxe;
    } else if ext == "mojo" || ext == "🔥" {
        return Lang.Mojo;
    } else if ext == "jsonnet" || ext == "libsonnet" {
        return Lang.Jsonnet;
    } else if ext == "dhall" {
        return Lang.Dhall;
    } else if ext == "typ" {
        return Lang.Typst;
    } else if ext == "kdl" {
        return Lang.KDL;
    } else if ext == "cue" {
        return Lang.CUE;
    } else if ext == "rego" {
        return Lang.Rego;
    } else if ext == "cls" || ext == "trigger" {
        return Lang.Apex;
    } else if ext == "bal" {
        return Lang.Ballerina;
    } else if ext == "ceylon" {
        return Lang.Ceylon;
    } else if ext == "chpl" {
        return Lang.Chapel;
    } else if ext == "gd" {
        return Lang.GDScript;
    } else if ext == "hack" || ext == "hhi" {
        return Lang.Hack;
    } else if ext == "moon" {
        return Lang.MoonScript;
    } else if ext == "qml" {
        return Lang.QML;
    } else if ext == "raku" || ext == "rakumod" || ext == "p6" {
        return Lang.Raku;
    } else if ext == "re" || ext == "rei" {
        return Lang.ReasonML;
    } else if ext == "res" || ext == "resi" {
        return Lang.Rescript;
    } else if ext == "bzl" || ext == "star" {
        return Lang.Starlark;
    } else if ext == "vala" || ext == "vapi" {
        return Lang.Vala;
    } else if ext == "wl" || ext == "wls" {
        return Lang.Wolfram;
    } else if ext == "xtend" {
        return Lang.Xtend;
    } else if ext == "gml" || ext == "wren" || ext == "nut" || ext == "uc" || ext == "uci" || ext == "qc" {
        return Lang.GameDev;
    } else if ext == "psc" {
        return Lang.Papyrus;
    } else if ext == "csv" {
        return Lang.CSV;
    } else if ext == "tsv" || ext == "tab" {
        return Lang.TSV;
    }
    return Lang.Unknown;
}
