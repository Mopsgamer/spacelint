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
    Unknown
}

fn get_extension(path: const u8[:]) -> u8[..16] {
    var out: u8[..16] = [];
    var i = path.len - 1;
    while i >= 0 && path[i] != '/' && path[i] != '\\' {
        if path[i] == '.' {
            let ext = path[i + 1..];
            for b in ext {
                let c = if b >= 'A' && b <= 'Z' { (b + 32) } else { b };
                out.push(c);
            }
            return out;
        }
        i--;
    }
    return out;
}

fn detect_lang(path: const u8[:]) -> Lang {
    let ext = get_extension(path);
    if ext == "ts" || ext == "tsx" || ext == "mts" || ext == "cts" {
        return Lang.TypeScript;
    } else if ext == "js" || ext == "jsx" || ext == "mjs" || ext == "cjs" {
        return Lang.JavaScript;
    } else if ext == "json" || ext == "jsonc" {
        return Lang.JSON;
    } else if ext == "yaml" || ext == "yml" {
        return Lang.YAML;
    } else if ext == "xml" || ext == "svg" || ext == "html" {
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
    }
    return Lang.Unknown;
}
