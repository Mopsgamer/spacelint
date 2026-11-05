// CLI argument parsing and configuration for spacelint.
import std;
import os;
import json;
import src.rules;

enum FormatOption {
    Default,
    Agent,
    Stylish
}

struct Config {
    help: bool,
    version: bool,
    rules: bool,
    fix: bool,
    interactive: bool,
    format: FormatOption,
    rules_cfg: RulesConfig,
    files: (const u8[:])[>..]
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
        help: false,
        version: false,
        rules: false,
        fix: false,
        interactive: false,
        format: FormatOption.Default,
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
        } else if arg_str == "--rules" {
            cfg.rules = true;
        } else if arg_str == "--fix" {
            cfg.fix = true;
        } else if arg_str == "-i" || arg_str == "--interactive" {
            cfg.interactive = true;
        } else if arg_str == "-f" || arg_str == "--format" {
            i++;
            if i < raw.len { cfg.format = parse_format_val(raw[i]); }
        } else if arg_str.len > 9 && arg_str[0..9] == "--format=" {
            cfg.format = parse_format_val(arg_str[9..]);
        } else if arg_str.len > 3 && arg_str[0..3] == "-f=" {
            cfg.format = parse_format_val(arg_str[3..]);
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
        } else if arg_str.len > 0 && arg_str[0] == '-' && arg_str != "-" {
            // ignore other options or plugin flags (e.g. --typescript-plugin)
        } else {
            cfg.files.push(arg_str);
        }
        i++;
    }
    return cfg;
}
