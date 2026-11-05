// CLI argument parsing for spacelint.
import std;
import os;

enum IndentKind {
    Tabs,
    Spaces { n: i32 },
    Auto,
    AutoExt { ext: u8[..16] },
    SpacesExt { n: i32, ext: u8[..16] },
    TabsExt { ext: u8[..16] },
    Off,
    OffExt { ext: u8[..16] }
}

struct Config {
    help: bool,
    version: bool,
    rules: bool,
    fix: bool,
    interactive: bool,
    indents: IndentKind[..32],
    files: (const u8[:])[>..]
}

fn parse_indent_val(val: const u8[:]) -> IndentKind {
    if val == "tabs" {
        return IndentKind.Tabs;
    } else if val == "auto" {
        return IndentKind.Auto;
    } else if val == "off" {
        return IndentKind.Off;
    } else if val.len > 5 && val[0..5] == "auto." {
        var ext_buf: u8[..16] = [];
        for b in val[5..] { ext_buf.push(b); }
        return IndentKind.AutoExt { ext: ext_buf };
    } else if val.len > 5 && val[0..5] == "tabs." {
        var ext_buf: u8[..16] = [];
        for b in val[5..] { ext_buf.push(b); }
        return IndentKind.TabsExt { ext: ext_buf };
    } else if val.len > 4 && val[0..4] == "off." {
        var ext_buf: u8[..16] = [];
        for b in val[4..] { ext_buf.push(b); }
        return IndentKind.OffExt { ext: ext_buf };
    } else {
        // Check for <N>.<ext>
        var dot_idx = -1;
        var i = 0;
        while i < val.len {
            if val[i] == '.' { dot_idx = i; break; }
            i++;
        }

        if dot_idx > 0 {
            let num_slice = val[0..dot_idx];
            let ext_slice = val[dot_idx + 1..];
            let n, ok = parse_int(num_slice);
            if ok && n > 0 {
                var ext_buf: u8[..16] = [];
                for b in ext_slice { ext_buf.push(b); }
                return IndentKind.SpacesExt { n: n as! i32, ext: ext_buf };
            }
        }

        let n, ok = parse_int(val);
        if ok && n > 0 { return IndentKind.Spaces { n: n as! i32 }; }
        return IndentKind.Tabs;
    }
}

fn parse_cli_args() -> Config {
    let raw = args();
    var cfg = Config {
        help: false,
        version: false,
        rules: false,
        fix: false,
        interactive: false,
        indents: [],
        files: []
    };

    var i = 1; // 0 is executable name
    while i < raw.len {
        let arg_str = raw[i];
        if arg_str == "-h" || arg_str == "--help" {
            cfg.help = true;
        } else if arg_str == "-v" || arg_str == "-V" || arg_str == "--version" {
            cfg.version = true;
        } else if arg_str == "--rules" {
            cfg.rules = true;
        } else if arg_str == "--fix" {
            cfg.fix = true;
        } else if arg_str == "-i" || arg_str == "--interactive" {
            cfg.interactive = true;
        } else if arg_str == "--indent" {
            i++;
            if i < raw.len { cfg.indents.push(parse_indent_val(raw[i])); }
        } else if arg_str.len > 9 && arg_str[0..9] == "--indent=" {
            cfg.indents.push(parse_indent_val(arg_str[9..]));
        } else if arg_str.len > 0 && arg_str[0] == '-' && arg_str != "-" {
            // ignore unknown option or flag
        } else { cfg.files.push(arg_str); }
        i++;
    }
    return cfg;
}
