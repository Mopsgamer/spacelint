// CLI argument parsing and configuration for spacelint.
import std;
import os;
import json;
import src.glob;
import src.rules;

enum FormatOption {
    Default,
    Agent,
    Stylish
}

enum SubCommand {
    Lint,
    Files,
    Timings
}

struct Config {
    cmd: SubCommand,
    help: bool,
    version: bool,
    init: bool,
    rules: bool,
    fix: bool,
    interactive: bool,
    no_color: bool,
    use_color: bool,
    format: FormatOption,
    max_warnings: i32,
    max_problems: i32,
    rules_cfg: RulesConfig,
    files: (const u8[:])[>..]
}

extern fn isatty(fd: i32) -> i32;

fn detect_color_support(no_color_flag: bool) -> bool {
    if no_color_flag {
        return false;
    }
    var env_buf: u8[>..] = [];
    if env("NO_COLOR", env_buf) {
        if env_buf.len > 0 {
            return false;
        }
    }
    var term_buf: u8[>..] = [];
    if env("TERM", term_buf) {
        if term_buf == "dumb" {
            return false;
        }
    }
    var wt_buf: u8[>..] = [];
    let has_wt = env("WT_SESSION", wt_buf) && wt_buf.len > 0;
    var ansicon_buf: u8[>..] = [];
    let has_ansicon = env("ANSICON", ansicon_buf) && ansicon_buf.len > 0;
    var conemu_buf: u8[>..] = [];
    let has_conemu = env("ConEmuANSI", conemu_buf) && conemu_buf == "ON";

    // On Windows, if OS is Windows (e.g. OS env variable is Windows_NT or Windir is set),
    // legacy console host without VT processing does not support ANSI colors unless running inside
    // Windows Terminal (WT_SESSION), ConEmu (ConEmuANSI=ON), ANSICON, or a known unixy terminal like Mintty/Git Bash (TERM).
    var os_buf: u8[>..] = [];
    let is_windows = env("OS", os_buf) && os_buf == "Windows_NT";
    if is_windows {
        if !has_wt && !has_ansicon && !has_conemu && term_buf.len == 0 {
            return false;
        }
    }

    let tty_fd: i32 = 1; // stdout
    return isatty(tty_fd) != 0;
}

fn parse_severity_str(s: const u8[:]) -> RuleSeverity, bool {
    if s == "off" || s == "allow" {
        return RuleSeverity.Off, true;
    } else if s == "warn" {
        return RuleSeverity.Warn, true;
    } else if s == "error" || s == "deny" {
        return RuleSeverity.Error, true;
    }
    return RuleSeverity.Warn, false;
}

fn parse_format_val(val: const u8[:]) -> FormatOption {
    if val == "agent" {
        return FormatOption.Agent;
    } else if val == "stylish" {
        return FormatOption.Stylish;
    } else {
        return FormatOption.Default;
    }
}

fn find_char(s: const u8[:], c: u8) -> i64 {
    var i = 0;
    while i < s.len {
        if s[i] == c { return i; }
        i++;
    }
    return -1;
}

// Parse indent kind from value string or int
fn parse_indent_value_str(val: const u8[:]) -> IndentRuleKind {
    if val == "tabs" || val == "tab" {
        return IndentRuleKind.Tabs;
    } else if val == "auto" {
        return IndentRuleKind.Auto;
    } else if val == "off" {
        return IndentRuleKind.Off;
    }
    let n, ok = parse_int(val);
    if ok && n > 0 {
        return IndentRuleKind.Spaces { n: n as! i32 };
    }
    return IndentRuleKind.Tabs;
}

fn handle_indent_rule_option(rc: RulesConfig&, sev: RuleSeverity, option_node: json::Node?) {
    rc.indent_sev = sev;
    if !option_node {
        return;
    }
    match option_node.val {
        Int iv => {
            if iv.v > 0 {
                rc.indent_global = IndentRuleKind.Spaces { n: iv.v as! i32 };
            }
        },
        Num nv => {
            if nv.v > 0.0 {
                rc.indent_global = IndentRuleKind.Spaces { n: nv.v as! i32 };
            }
        },
        Str sv => {
            rc.indent_global = parse_indent_value_str(sv.s);
        },
        _ => {}
    }
}

fn set_override_rule_severity(ov: RuleOverride&, raw_name: const u8[:], sev: RuleSeverity) {
    let name = normalize_rule_name(raw_name);
    if name == "no-trailing-spaces" {
        ov.has_trailing_spaces = true;
        ov.trailing_spaces_sev = sev;
    } else if name == "no-carriage-return" {
        ov.has_carriage_return = true;
        ov.carriage_return_sev = sev;
    } else if name == "no-mixed-spaces-and-tabs" {
        ov.has_mixed_spaces_tabs = true;
        ov.mixed_spaces_tabs_sev = sev;
    } else if name == "indent" {
        ov.has_indent = true;
        ov.indent_sev = sev;
    } else if name == "all" {
        ov.has_trailing_spaces = true;
        ov.trailing_spaces_sev = sev;
        ov.has_carriage_return = true;
        ov.carriage_return_sev = sev;
        ov.has_mixed_spaces_tabs = true;
        ov.mixed_spaces_tabs_sev = sev;
        ov.has_indent = true;
        ov.indent_sev = sev;
    } else if name == "correctness" {
        ov.has_trailing_spaces = true;
        ov.trailing_spaces_sev = sev;
        ov.has_carriage_return = true;
        ov.carriage_return_sev = sev;
        ov.has_mixed_spaces_tabs = true;
        ov.mixed_spaces_tabs_sev = sev;
    } else if name == "style" {
        ov.has_indent = true;
        ov.indent_sev = sev;
    }
}

fn parse_rules_node_for_override(ov: RuleOverride&, rules_node: json::Node?) {
    if !rules_node { return; }
    json::each(rules_node) { child =>
        let r_name = normalize_rule_name(child.key);
        match child.val {
            Str sv => {
                let s, ok = parse_severity_str(sv.s);
                if ok {
                    set_override_rule_severity(ov, r_name, s);
                } else if r_name == "indent" {
                    ov.has_indent_kind = true;
                    ov.indent_kind = parse_indent_value_str(sv.s);
                }
            },
            Int iv => {
                if r_name == "indent" && iv.v > 0 {
                    ov.has_indent_kind = true;
                    ov.indent_kind = IndentRuleKind.Spaces { n: iv.v as! i32 };
                } else if iv.v == 0 {
                    set_override_rule_severity(ov, r_name, RuleSeverity.Off);
                } else if iv.v == 1 {
                    set_override_rule_severity(ov, r_name, RuleSeverity.Warn);
                } else if iv.v == 2 {
                    set_override_rule_severity(ov, r_name, RuleSeverity.Error);
                }
            },
            Arr _ => {
                var first_elem = child.first;
                if first_elem {
                    var sev = RuleSeverity.Warn;
                    match first_elem.val {
                        Str sv => {
                            let s, ok = parse_severity_str(sv.s);
                            if ok { sev = s; }
                        },
                        Int iv => {
                            if iv.v == 0 { sev = RuleSeverity.Off; }
                            else if iv.v == 1 { sev = RuleSeverity.Warn; }
                            else if iv.v == 2 { sev = RuleSeverity.Error; }
                        },
                        _ => {}
                    }
                    set_override_rule_severity(ov, r_name, sev);
                    if r_name == "indent" {
                        let opt_node = first_elem.next;
                        if opt_node {
                            match opt_node.val {
                                Int iv => {
                                    if iv.v > 0 {
                                        ov.has_indent_kind = true;
                                        ov.indent_kind = IndentRuleKind.Spaces { n: iv.v as! i32 };
                                    }
                                },
                                Num nv => {
                                    if nv.v > 0.0 {
                                        ov.has_indent_kind = true;
                                        ov.indent_kind = IndentRuleKind.Spaces { n: nv.v as! i32 };
                                    }
                                },
                                Str sv => {
                                    ov.has_indent_kind = true;
                                    ov.indent_kind = parse_indent_value_str(sv.s);
                                },
                                _ => {}
                            }
                        }
                    }
                }
            },
            _ => {}
        }
    };
}

// Parses -C argument, which can be rule=severity or rule=JSON_VALUE
fn parse_c_flag(rc: RulesConfig&, arg: const u8[:]) {
    let eq = find_char(arg, '=');
    if eq < 0 {
        return;
    }
    let raw_rule = arg[0..eq];
    let val_str = arg[eq + 1..];
    let rule_name = normalize_rule_name(raw_rule);

    // Try parsing val_str as JSON
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = json::parse(val_str, doc, decoded);

    if root {
        match root.val {
            Arr _ => {
                var first_node: json::Node? = root.first;
                if first_node {
                    var sev = RuleSeverity.Warn;
                    match first_node.val {
                        Str sv => {
                            let s, ok = parse_severity_str(sv.s);
                            if ok { sev = s; }
                        },
                        Int iv => {
                            if iv.v == 0 { sev = RuleSeverity.Off; }
                            else if iv.v == 1 { sev = RuleSeverity.Warn; }
                            else if iv.v == 2 { sev = RuleSeverity.Error; }
                        },
                        _ => {}
                    }

                    if rule_name == "indent" {
                        handle_indent_rule_option(rc, sev, first_node.next);
                    } else {
                        set_rule_severity(rc, rule_name, sev);
                    }
                }
            },
            Str sv => {
                let sev, ok = parse_severity_str(sv.s);
                if ok {
                    set_rule_severity(rc, rule_name, sev);
                } else if rule_name == "indent" {
                    rc.indent_global = parse_indent_value_str(sv.s);
                }
            },
            Int iv => {
                if rule_name == "indent" && iv.v > 0 {
                    rc.indent_global = IndentRuleKind.Spaces { n: iv.v as! i32 };
                } else if iv.v == 0 {
                    set_rule_severity(rc, rule_name, RuleSeverity.Off);
                } else if iv.v == 1 {
                    set_rule_severity(rc, rule_name, RuleSeverity.Warn);
                } else if iv.v == 2 {
                    set_rule_severity(rc, rule_name, RuleSeverity.Error);
                }
            },
            _ => {}
        }
        return;
    }

    // Not JSON, parse simple string
    if rule_name == "indent" {
        let dot = find_char(val_str, '.');
        if dot > 0 {
            let left = val_str[0..dot];
            let ext = val_str[dot + 1..];
            let kind = parse_indent_value_str(left);
            rc.indent_exts.push(IndentExtOverride { ext: ext, kind: kind });
        } else {
            let sev, ok = parse_severity_str(val_str);
            if ok {
                rc.indent_sev = sev;
            } else {
                rc.indent_global = parse_indent_value_str(val_str);
            }
        }
    } else {
        let sev, ok = parse_severity_str(val_str);
        if ok {
            set_rule_severity(rc, rule_name, sev);
        }
    }
}

// Parses a configuration JSON file
fn load_config_file(rc: RulesConfig&, path: const u8[:]) -> bool {
    var file_bytes: u8[>..] = [];
    if !read_file(path, file_bytes) {
        return false;
    }

    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = json::parse(file_bytes, doc, decoded);
    if !root {
        return false;
    }

    // Look for "categories"
    let cats = json::member(root, "categories");
    if cats {
        json::each(cats) { child =>
            var sev = RuleSeverity.Warn;
            var has_sev = false;
            match child.val {
                Str sv => {
                    let s, ok = parse_severity_str(sv.s);
                    if ok { sev = s; has_sev = true; }
                },
                Int iv => {
                    if iv.v == 0 { sev = RuleSeverity.Off; has_sev = true; }
                    else if iv.v == 1 { sev = RuleSeverity.Warn; has_sev = true; }
                    else if iv.v == 2 { sev = RuleSeverity.Error; has_sev = true; }
                },
                _ => {}
            }
            if has_sev {
                set_category_severity(rc, child.key, sev);
            }
        };
    }

    // Look for "overrides"
    let overrides_node = json::member(root, "overrides");
    if overrides_node {
        json::each(overrides_node) { item_node =>
            var ov = default_rule_override();

            // Parse "files" and pre-parse into inline stack structures
            let files_node = json::member(item_node, "files");
            if files_node {
                match files_node.val {
                    Str sv => {
                        parse_pattern_into_globs(sv.s, ov.globs);
                    },
                    Arr _ => {
                        json::each(files_node) { file_child =>
                            match file_child.val {
                                Str sv => {
                                    parse_pattern_into_globs(sv.s, ov.globs);
                                },
                                _ => {}
                            }
                        };
                    },
                    _ => {}
                }
            }

            // Parse categories if present in override
            let cat_node = json::member(item_node, "categories");
            if cat_node {
                json::each(cat_node) { cat_child =>
                    var sev = RuleSeverity.Warn;
                    var has_sev = false;
                    match cat_child.val {
                        Str sv => {
                            let s, ok = parse_severity_str(sv.s);
                            if ok { sev = s; has_sev = true; }
                        },
                        Int iv => {
                            if iv.v == 0 { sev = RuleSeverity.Off; has_sev = true; }
                            else if iv.v == 1 { sev = RuleSeverity.Warn; has_sev = true; }
                            else if iv.v == 2 { sev = RuleSeverity.Error; has_sev = true; }
                        },
                        _ => {}
                    }
                    if has_sev {
                        set_override_rule_severity(ov, cat_child.key, sev);
                    }
                };
            }

            // Parse rules in override
            let r_node = json::member(item_node, "rules");
            if r_node {
                parse_rules_node_for_override(ov, r_node);
            }

            if ov.globs.len > 0 {
                rc.overrides.push(ov);
            }
        };
    }

    // Look for "rules"
    let rules_node = json::member(root, "rules");
    if rules_node {
        json::each(rules_node) { child =>
            let r_name = normalize_rule_name(child.key);
            match child.val {
                Str sv => {
                    let s, ok = parse_severity_str(sv.s);
                    if ok {
                        set_rule_severity(rc, r_name, s);
                    } else if r_name == "indent" {
                        rc.indent_global = parse_indent_value_str(sv.s);
                    }
                },
                Int iv => {
                    if r_name == "indent" && iv.v > 0 {
                        rc.indent_global = IndentRuleKind.Spaces { n: iv.v as! i32 };
                    } else if iv.v == 0 {
                        set_rule_severity(rc, r_name, RuleSeverity.Off);
                    } else if iv.v == 1 {
                        set_rule_severity(rc, r_name, RuleSeverity.Warn);
                    } else if iv.v == 2 {
                        set_rule_severity(rc, r_name, RuleSeverity.Error);
                    }
                },
                Arr _ => {
                    var first_elem = child.first;
                    if first_elem {
                        var sev = RuleSeverity.Warn;
                        match first_elem.val {
                            Str sv => {
                                let s, ok = parse_severity_str(sv.s);
                                if ok { sev = s; }
                            },
                            Int iv => {
                                if iv.v == 0 { sev = RuleSeverity.Off; }
                                else if iv.v == 1 { sev = RuleSeverity.Warn; }
                                else if iv.v == 2 { sev = RuleSeverity.Error; }
                            },
                            _ => {}
                        }
                        if r_name == "indent" {
                            handle_indent_rule_option(rc, sev, first_elem.next);
                        } else {
                            set_rule_severity(rc, r_name, sev);
                        }
                    }
                },
                _ => {}
            }
        };
    }

    return true;
}

fn parse_cli_args() -> Config {
    let raw = args();
    var cfg = Config {
        cmd: SubCommand.Lint,
        help: false,
        version: false,
        init: false,
        rules: false,
        fix: false,
        interactive: false,
        no_color: false,
        use_color: true,
        format: FormatOption.Default,
        max_warnings: -1,
        max_problems: -1,
        rules_cfg: default_rules_config(),
        files: []
    };

    var i = 1; // 0 is executable name
    while i < raw.len {
        let arg_str = raw[i];
        if arg_str == "-h" || arg_str == "--help" {
            cfg.help = true;
        } else if arg_str == "-v" || arg_str == "-V" || arg_str == "--version" {
            cfg.version = true;
        } else if arg_str == "--init" {
            cfg.init = true;
        } else if arg_str == "--rules" {
            cfg.rules = true;
        } else if arg_str == "--fix" {
            cfg.fix = true;
        } else if arg_str == "-i" || arg_str == "--interactive" {
            cfg.interactive = true;
        } else if arg_str == "--no-color" {
            cfg.no_color = true;
        } else if arg_str == "-f" || arg_str == "--format" {
            i++;
            if i < raw.len { cfg.format = parse_format_val(raw[i]); }
        } else if arg_str.len > 9 && arg_str[0..9] == "--format=" {
            cfg.format = parse_format_val(arg_str[9..]);
        } else if arg_str.len > 3 && arg_str[0..3] == "-f=" {
            cfg.format = parse_format_val(arg_str[3..]);
        } else if arg_str == "--max-warnings" {
            i++;
            if i < raw.len {
                let n, ok = parse_int(raw[i]);
                if ok { cfg.max_warnings = n as! i32; }
            }
        } else if arg_str.len > 15 && arg_str[0..15] == "--max-warnings=" {
            let n, ok = parse_int(arg_str[15..]);
            if ok { cfg.max_warnings = n as! i32; }
        } else if arg_str == "--max-problems" {
            i++;
            if i < raw.len {
                let n, ok = parse_int(raw[i]);
                if ok { cfg.max_problems = n as! i32; }
            }
        } else if arg_str.len > 15 && arg_str[0..15] == "--max-problems=" {
            let n, ok = parse_int(arg_str[15..]);
            if ok { cfg.max_problems = n as! i32; }
        } else if arg_str == "-c" || arg_str == "--config" {
            i++;
            if i < raw.len {
                load_config_file(cfg.rules_cfg, raw[i]);
            }
        } else if arg_str.len > 9 && arg_str[0..9] == "--config=" {
            load_config_file(cfg.rules_cfg, arg_str[9..]);
        } else if arg_str.len > 3 && arg_str[0..3] == "-c=" {
            load_config_file(cfg.rules_cfg, arg_str[3..]);
        } else if arg_str == "-A" || arg_str == "--allow" {
            i++;
            if i < raw.len {
                set_rule_severity(cfg.rules_cfg, raw[i], RuleSeverity.Off);
            }
        } else if arg_str.len > 8 && arg_str[0..8] == "--allow=" {
            set_rule_severity(cfg.rules_cfg, arg_str[8..], RuleSeverity.Off);
        } else if arg_str.len > 3 && arg_str[0..3] == "-A=" {
            set_rule_severity(cfg.rules_cfg, arg_str[3..], RuleSeverity.Off);
        } else if arg_str == "-W" || arg_str == "--warn" {
            i++;
            if i < raw.len {
                set_rule_severity(cfg.rules_cfg, raw[i], RuleSeverity.Warn);
            }
        } else if arg_str.len > 7 && arg_str[0..7] == "--warn=" {
            set_rule_severity(cfg.rules_cfg, arg_str[7..], RuleSeverity.Warn);
        } else if arg_str.len > 3 && arg_str[0..3] == "-W=" {
            set_rule_severity(cfg.rules_cfg, arg_str[3..], RuleSeverity.Warn);
        } else if arg_str == "-D" || arg_str == "--deny" {
            i++;
            if i < raw.len {
                set_rule_severity(cfg.rules_cfg, raw[i], RuleSeverity.Error);
            }
        } else if arg_str.len > 7 && arg_str[0..7] == "--deny=" {
            set_rule_severity(cfg.rules_cfg, arg_str[7..], RuleSeverity.Error);
        } else if arg_str.len > 3 && arg_str[0..3] == "-D=" {
            set_rule_severity(cfg.rules_cfg, arg_str[3..], RuleSeverity.Error);
        } else if arg_str == "-C" {
            i++;
            if i < raw.len {
                parse_c_flag(cfg.rules_cfg, raw[i]);
            }
        } else if arg_str.len > 3 && arg_str[0..3] == "-C=" {
            parse_c_flag(cfg.rules_cfg, arg_str[3..]);
        } else if arg_str == "files" && cfg.cmd == SubCommand.Lint && cfg.files.len == 0 {
            cfg.cmd = SubCommand.Files;
        } else if arg_str == "timings" && cfg.cmd == SubCommand.Lint && cfg.files.len == 0 {
            cfg.cmd = SubCommand.Timings;
        } else if arg_str.len > 0 && arg_str[0] == '-' && arg_str != "-" {
            // ignore other options or plugin flags (e.g. --typescript-plugin)
        } else {
            cfg.files.push(arg_str);
        }
        i++;
    }

    cfg.use_color = detect_color_support(cfg.no_color);
    return cfg;
}
