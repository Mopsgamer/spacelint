// Core whitespace checking and fixing rules for spacelint.
import std;
import os;
import src.glob;

enum RuleSeverity {
    Off,
    Warn,
    Error
}

enum IndentRuleKind {
    Tabs,
    Spaces { n: i32 },
    Auto,
    Off
}

struct IndentExtOverride {
    ext: const u8[:],
    kind: IndentRuleKind
}

struct RuleOverride {
    has_trailing_spaces: bool,
    trailing_spaces_sev: RuleSeverity,
    has_carriage_return: bool,
    carriage_return_sev: RuleSeverity,
    has_mixed_spaces_tabs: bool,
    mixed_spaces_tabs_sev: RuleSeverity,
    has_indent: bool,
    indent_sev: RuleSeverity,
    has_indent_kind: bool,
    indent_kind: IndentRuleKind,
    globs: ParsedGlob[..16]
}

struct RulesConfig {
    trailing_spaces_sev: RuleSeverity,
    carriage_return_sev: RuleSeverity,
    mixed_spaces_tabs_sev: RuleSeverity,
    indent_sev: RuleSeverity,
    indent_global: IndentRuleKind,
    indent_exts: IndentExtOverride[..64],
    overrides: RuleOverride[..32]
}

struct Diagnostic {
    line: i32,
    col: i32,
    end_col: i32,
    rule: const u8[:],
    message: const u8[:],
    severity: RuleSeverity
}

fn default_rules_config() -> RulesConfig {
    return RulesConfig {
        trailing_spaces_sev: RuleSeverity.Warn,
        carriage_return_sev: RuleSeverity.Warn,
        mixed_spaces_tabs_sev: RuleSeverity.Warn,
        indent_sev: RuleSeverity.Warn,
        indent_global: IndentRuleKind.Tabs,
        indent_exts: [],
        overrides: []
    };
}

fn default_rule_override() -> RuleOverride {
    return RuleOverride {
        has_trailing_spaces: false,
        trailing_spaces_sev: RuleSeverity.Warn,
        has_carriage_return: false,
        carriage_return_sev: RuleSeverity.Warn,
        has_mixed_spaces_tabs: false,
        mixed_spaces_tabs_sev: RuleSeverity.Warn,
        has_indent: false,
        indent_sev: RuleSeverity.Warn,
        has_indent_kind: false,
        indent_kind: IndentRuleKind.Tabs,
        globs: []
    };
}

// Normalizes rule name by stripping prefix like "eslint/", "oxc/", "typescript/", etc.
fn normalize_rule_name(name: const u8[:]) -> const u8[:] {
    var slash_idx = -1;
    var i = 0;
    while i < name.len {
        if name[i] == '/' {
            slash_idx = i;
            break;
        }
        i++;
    }
    if slash_idx >= 0 && slash_idx + 1 < name.len {
        return name[slash_idx + 1..];
    }
    return name;
}

fn set_category_severity(rc: RulesConfig&, cat: const u8[:], sev: RuleSeverity) -> bool {
    if cat == "all" {
        rc.trailing_spaces_sev = sev;
        rc.carriage_return_sev = sev;
        rc.mixed_spaces_tabs_sev = sev;
        rc.indent_sev = sev;
        return true;
    } else if cat == "correctness" {
        rc.trailing_spaces_sev = sev;
        rc.carriage_return_sev = sev;
        rc.mixed_spaces_tabs_sev = sev;
        return true;
    } else if cat == "style" {
        rc.indent_sev = sev;
        return true;
    }
    return false;
}

fn set_rule_severity(rc: RulesConfig&, raw_name: const u8[:], sev: RuleSeverity) -> bool {
    let name = normalize_rule_name(raw_name);
    if name == "no-trailing-spaces" {
        rc.trailing_spaces_sev = sev;
        return true;
    } else if name == "no-carriage-return" {
        rc.carriage_return_sev = sev;
        return true;
    } else if name == "no-mixed-spaces-and-tabs" {
        rc.mixed_spaces_tabs_sev = sev;
        return true;
    } else if name == "indent" {
        rc.indent_sev = sev;
        return true;
    }
    // Check if category
    if set_category_severity(rc, name, sev) {
        return true;
    }
    // Other rules (e.g. plugin rules like no-console, eqeqeq, no-unused-vars, etc.)
    // are accepted gracefully to support compatibility with linter rule flags.
    return true;
}

// Returns the trailing whitespace length (including carriage return).
fn get_trailing_ws_len(line: const u8[:]) -> i32 {
    if line.len == 0 { return 0; }
    var trailing_count = 0;
    var i = line.len - 1;
    while i >= 0 && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r') {
        trailing_count++;
        i--;
    }
    return trailing_count as! i32;
}


fn get_rules_for_file(base_cfg: RulesConfig, file_path: const u8[:]) -> RulesConfig {
    if base_cfg.overrides.len == 0 {
        return base_cfg;
    }

    var norm_f: u8[>..] = [];
    normalize_path_for_match(file_path, norm_f);

    var effective_cfg = base_cfg;
    for ov in base_cfg.overrides {
        var is_match = false;
        for g in ov.globs {
            if match_parsed_glob(g, norm_f) {
                is_match = true;
                break;
            }
        }

        if is_match {
            if ov.has_trailing_spaces {
                effective_cfg.trailing_spaces_sev = ov.trailing_spaces_sev;
            }
            if ov.has_carriage_return {
                effective_cfg.carriage_return_sev = ov.carriage_return_sev;
            }
            if ov.has_mixed_spaces_tabs {
                effective_cfg.mixed_spaces_tabs_sev = ov.mixed_spaces_tabs_sev;
            }
            if ov.has_indent {
                effective_cfg.indent_sev = ov.indent_sev;
            }
            if ov.has_indent_kind {
                effective_cfg.indent_global = ov.indent_kind;
            }
        }
    }

    return effective_cfg;
}

// Autodetects if spaces or tabs predominate for indentation across the text.
// Returns true for spaces, false for tabs. Also computes estimated space step (default 4 or 2).
fn autodetect_spaces(text: const u8[:]) -> bool, i32 {
    var space_indent_count = 0;
    var tab_indent_count = 0;
    var spaces_2 = 0;
    var spaces_4 = 0;
    var i = 0;
    var at_bol = true;

    while i < text.len {
        let c = text[i];
        if c == '\n' {
            at_bol = true;
            i++;
            continue;
        }
        if !at_bol { i++; continue; }
        if c == ' ' {
            space_indent_count++;
            var sp_count = 0;
            while i < text.len && text[i] == ' ' {
                sp_count++;
                i++;
            }
            if sp_count == 2 || sp_count == 6 {
                spaces_2++;
            } else if sp_count == 4 || sp_count == 8 {
                spaces_4++;
            }
            at_bol = false;
            continue;
        } else if c == '\t' {
            tab_indent_count++;
            at_bol = false;
        } else if c != '\r' {
            at_bol = false;
        }
        i++;
    }

    let is_spaces = space_indent_count > tab_indent_count;
    let step: i32 = if spaces_2 > spaces_4 { 2 } else { 4 };
    return is_spaces, step;
}
