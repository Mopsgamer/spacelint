// spacelint: fast, language-aware whitespace linter and fixer CLI in Goose
import std;
import os;
import src.options;
import src.lang;
import src.rules;
import src.formatter;

// Process a single text buffer, either linting or fixing.
// Returns:
//   was_modified: bool
fn process_buffer(
    text: const u8[:],
    file_path: const u8[:],
    cfg: Config&,
    out_fixed: u8[>..]&,
    out_diags: Diagnostic[>..]&
) -> bool {
    let language = detect_lang(file_path);
    let file_ext = get_extension(file_path);

    let active_rules = get_rules_for_file(cfg.rules_cfg, file_path);

    // Determine target indentation for this file
    var target_indent_spaces = false;
    var indent_step: i32 = 4;
    var indent_disabled = (active_rules.indent_sev == RuleSeverity.Off);

    // First check for extension-specific matches
    var matched_rule = false;
    for rule in active_rules.indent_exts {
        if file_ext == rule.ext {
            match rule.kind {
                Tabs => {
                    target_indent_spaces = false;
                    indent_step = 4;
                    indent_disabled = false;
                    matched_rule = true;
                    break;
                },
                Spaces s => {
                    target_indent_spaces = true;
                    indent_step = s.n;
                    indent_disabled = false;
                    matched_rule = true;
                    break;
                },
                Auto => {
                    let sp, st = autodetect_spaces(text);
                    target_indent_spaces = sp;
                    indent_step = st;
                    indent_disabled = false;
                    matched_rule = true;
                    break;
                },
                Off => {
                    indent_disabled = true;
                    matched_rule = true;
                    break;
                }
            }
        }
    }

    // If no extension-specific match, check for global defaults
    if !matched_rule {
        match active_rules.indent_global {
            Tabs => {
                target_indent_spaces = false;
                indent_step = 4;
            },
            Spaces s => {
                target_indent_spaces = true;
                indent_step = s.n;
            },
            Auto => {
                let sp, st = autodetect_spaces(text);
                target_indent_spaces = sp;
                indent_step = st;
            },
            Off => {
                indent_disabled = true;
            }
        }
    }

    if active_rules.indent_sev == RuleSeverity.Off {
        indent_disabled = true;
    }

    // State for tracking multiline block comments and multiline strings
    var in_block_comment = false;
    var in_multiline_str = false;
    var str_delimiter: u8 = 0; // '`', '"', '\'', ']'
    var str_delimiter_len: i32 = 1; // 1 for `, 2 for ]], 3 for """ or '''
    var was_modified = false;

    // Scan lines
    var pos = 0;
    var line_num: i32 = 1;

    while pos < text.len {
        let line_start = pos;
        while pos < text.len && text[pos] != '\n' {
            pos++;
        }
        let line_end = pos; // pos points to '\n' or EOF
        if pos < text.len && text[pos] == '\n' {
            pos++; // advance past newline for next line
        }

        let raw_line = text[line_start..line_end];

        // 1. Check for carriage return or trailing whitespace
        let trailing_len = get_trailing_ws_len(raw_line);
        var has_cr = false;
        for b in raw_line {
            if b == '\r' {
                has_cr = true;
                break;
            }
        }

        let content_len = raw_line.len - trailing_len;
        let trimmed_line = raw_line[0..content_len];

        // 2. Multiline string / comment state tracking before line processing
        var line_is_in_multiline_str = in_multiline_str;
        var line_is_in_block_comment = in_block_comment;

        // Inspect trimmed_line characters to update multiline state
        var idx = 0;
        while idx < trimmed_line.len {
            let c = trimmed_line[idx];
            if in_multiline_str {
                // Look for ending delimiter
                if str_delimiter_len == 3 {
                    if idx + 2 < trimmed_line.len && trimmed_line[idx] == str_delimiter && trimmed_line[idx + 1] == str_delimiter && trimmed_line[idx + 2] == str_delimiter {
                        if idx == 0 || trimmed_line[idx - 1] != '\\' {
                            in_multiline_str = false;
                            idx += 2;
                        }
                    }
                } else if str_delimiter_len == 2 {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == ']' && trimmed_line[idx + 1] == ']' {
                        in_multiline_str = false;
                        idx += 1;
                    }
                } else {
                    if c == str_delimiter {
                        // Check for escape
                        if idx == 0 || trimmed_line[idx - 1] != '\\' {
                            in_multiline_str = false;
                        }
                    }
                }
            } else if in_block_comment {
                if language == Lang.XML || language == Lang.Markdown || language == Lang.MDX || language == Lang.Vue || language == Lang.Svelte || language == Lang.Astro || language == Lang.GoTemplate {
                    if idx + 2 < trimmed_line.len && trimmed_line[idx] == '-' && trimmed_line[idx + 1] == '-' && trimmed_line[idx + 2] == '>' {
                        in_block_comment = false;
                        idx += 2;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '*' && trimmed_line[idx + 1] == '/' {
                        in_block_comment = false;
                        idx += 1;
                    } else if idx + 2 < trimmed_line.len && trimmed_line[idx] == '*' && trimmed_line[idx + 1] == '/' && trimmed_line[idx + 2] == '}' {
                        in_block_comment = false;
                        idx += 2;
                    }
                } else if language == Lang.Haskell || language == Lang.Elm || language == Lang.PureScript {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '-' && trimmed_line[idx + 1] == '}' {
                        in_block_comment = false;
                        idx += 1;
                    }
                } else if language == Lang.OCaml || language == Lang.FSharp || language == Lang.Pascal || language == Lang.Wolfram {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '*' && trimmed_line[idx + 1] == ')' {
                        in_block_comment = false;
                        idx += 1;
                    }
                } else if language == Lang.Nim {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == ']' && trimmed_line[idx + 1] == '#' {
                        in_block_comment = false;
                        idx += 1;
                    }
                } else if language == Lang.PowerShell {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '#' && trimmed_line[idx + 1] == '>' {
                        in_block_comment = false;
                        idx += 1;
                    }
                } else if language == Lang.Lua {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == ']' && trimmed_line[idx + 1] == ']' {
                        in_block_comment = false;
                        idx += 1;
                    }
                } else {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '*' && trimmed_line[idx + 1] == '/' {
                        in_block_comment = false;
                        idx += 1;
                    }
                }
            } else {
                // Not in multiline string or comment
                // Check for block comment start
                if language == Lang.XML || language == Lang.Markdown || language == Lang.MDX || language == Lang.Vue || language == Lang.Svelte || language == Lang.Astro || language == Lang.GoTemplate {
                    if idx + 3 < trimmed_line.len && trimmed_line[idx] == '<' && trimmed_line[idx + 1] == '!' && trimmed_line[idx + 2] == '-' && trimmed_line[idx + 3] == '-' {
                        in_block_comment = true;
                        idx += 3;
                    } else if idx + 3 < trimmed_line.len && trimmed_line[idx] == '{' && trimmed_line[idx + 1] == '{' && trimmed_line[idx + 2] == '/' && trimmed_line[idx + 3] == '*' {
                        in_block_comment = true;
                        idx += 3;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '*' {
                        in_block_comment = true;
                        idx += 1;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '/' {
                        break;
                    }
                } else if language == Lang.Haskell || language == Lang.Elm || language == Lang.PureScript {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '{' && trimmed_line[idx + 1] == '-' {
                        in_block_comment = true;
                        idx += 1;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '-' && trimmed_line[idx + 1] == '-' {
                        break;
                    }
                } else if language == Lang.OCaml || language == Lang.FSharp || language == Lang.Pascal || language == Lang.Wolfram {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '(' && trimmed_line[idx + 1] == '*' {
                        in_block_comment = true;
                        idx += 1;
                    } else if idx + 1 < trimmed_line.len && (language == Lang.FSharp || language == Lang.Pascal) && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '/' {
                        break;
                    }
                } else if language == Lang.Nim {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '#' && trimmed_line[idx + 1] == '[' {
                        in_block_comment = true;
                        idx += 1;
                    } else if c == '#' {
                        break;
                    }
                } else if language == Lang.PowerShell {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '<' && trimmed_line[idx + 1] == '#' {
                        in_block_comment = true;
                        idx += 1;
                    } else if c == '#' {
                        break;
                    }
                } else if language == Lang.Lua {
                    if idx + 3 < trimmed_line.len && trimmed_line[idx] == '-' && trimmed_line[idx + 1] == '-' && trimmed_line[idx + 2] == '[' && trimmed_line[idx + 3] == '[' {
                        in_block_comment = true;
                        idx += 3;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '-' && trimmed_line[idx + 1] == '-' {
                        // Lua line comment to end of line
                        break;
                    }
                } else if language == Lang.SQL || language == Lang.Ada || language == Lang.VHDL || language == Lang.Dhall {
                    if idx + 1 < trimmed_line.len && (language == Lang.SQL || language == Lang.Dhall) && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '*' {
                        in_block_comment = true;
                        idx += 1;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '-' && trimmed_line[idx + 1] == '-' {
                        break;
                    }
                } else if language == Lang.TypeScript || language == Lang.JavaScript || language == Lang.CPP || language == Lang.C || language == Lang.Rust || language == Lang.Zig || language == Lang.JSON || language == Lang.Goose || language == Lang.Vlang || language == Lang.D || language == Lang.AssemblyScript || language == Lang.Kotlin || language == Lang.Java || language == Lang.Dart || language == Lang.Odin || language == Lang.Go || language == Lang.Swift || language == Lang.CSharp || language == Lang.Scala || language == Lang.CSS || language == Lang.PHP || language == Lang.Solidity || language == Lang.Protobuf || language == Lang.Shader || language == Lang.Groovy || language == Lang.Haxe || language == Lang.Typst || language == Lang.KDL || language == Lang.CUE || language == Lang.Verilog || language == Lang.Apex || language == Lang.Ballerina || language == Lang.Ceylon || language == Lang.Chapel || language == Lang.Hack || language == Lang.QML || language == Lang.ReasonML || language == Lang.Rescript || language == Lang.Vala || language == Lang.Xtend || language == Lang.GameDev {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '*' {
                        in_block_comment = true;
                        idx += 1;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '/' {
                        // Line comment to end of line
                        break;
                    } else if (language == Lang.PHP || language == Lang.Hack) && c == '#' {
                        break;
                    }
                } else if language == Lang.Papyrus {
                    if c == ';' {
                        break;
                    }
                } else if language == Lang.YAML || language == Lang.INI || language == Lang.TOML || language == Lang.PROPS || language == Lang.Python || language == Lang.Ruby || language == Lang.Shell || language == Lang.R || language == Lang.Julia || language == Lang.Perl || language == Lang.Elixir || language == Lang.GraphQL || language == Lang.Dockerfile || language == Lang.Makefile || language == Lang.Nix || language == Lang.Terraform || language == Lang.Crystal || language == Lang.CMake || language == Lang.Tcl || language == Lang.Awk || language == Lang.CoffeeScript || language == Lang.Mojo || language == Lang.Jsonnet || language == Lang.Rego || language == Lang.GDScript || language == Lang.MoonScript || language == Lang.Raku || language == Lang.Starlark {
                    if idx + 1 < trimmed_line.len && (language == Lang.Terraform || language == Lang.Jsonnet) && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '*' {
                        in_block_comment = true;
                        idx += 1;
                    } else if idx + 1 < trimmed_line.len && (language == Lang.Terraform || language == Lang.Jsonnet) && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '/' {
                        break;
                    } else if c == '#' || (language == Lang.INI && c == ';') {
                        // Line comment to end of line
                        break;
                    }
                } else if language == Lang.Cobol {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '*' && trimmed_line[idx + 1] == '>' {
                        break;
                    }
                } else if language == Lang.Smalltalk {
                    if c == '"' {
                        break;
                    }
                } else if language == Lang.Erlang {
                    if c == '%' {
                        break;
                    }
                } else if language == Lang.Fortran {
                    if c == '!' {
                        break;
                    }
                } else if language == Lang.Assembly || language == Lang.Clojure {
                    if c == ';' || (language == Lang.Assembly && c == '#') {
                        // Line comment to end of line
                        break;
                    }
                }

                // Check for multiline string start
                if !in_block_comment {
                    if (language == Lang.TypeScript || language == Lang.JavaScript || language == Lang.Goose || language == Lang.Go || language == Lang.Markdown || language == Lang.MDX || language == Lang.AssemblyScript || language == Lang.Vue || language == Lang.Svelte || language == Lang.Astro || language == Lang.Nix) && c == '`' {
                        in_multiline_str = true;
                        str_delimiter = '`';
                        str_delimiter_len = 1;
                    } else if (language == Lang.CSV || language == Lang.TSV) && c == '"' {
                        in_multiline_str = true;
                        str_delimiter = '"';
                        str_delimiter_len = 1;
                    } else if (language == Lang.TOML || language == Lang.Kotlin || language == Lang.Python || language == Lang.Elixir || language == Lang.Julia || language == Lang.GraphQL) && idx + 2 < trimmed_line.len && trimmed_line[idx] == '"' && trimmed_line[idx + 1] == '"' && trimmed_line[idx + 2] == '"' {
                        in_multiline_str = true;
                        str_delimiter = '"';
                        str_delimiter_len = 3;
                        idx += 2;
                    } else if (language == Lang.Python || language == Lang.Elixir) && idx + 2 < trimmed_line.len && trimmed_line[idx] == '\'' && trimmed_line[idx + 1] == '\'' && trimmed_line[idx + 2] == '\'' {
                        in_multiline_str = true;
                        str_delimiter = '\'';
                        str_delimiter_len = 3;
                        idx += 2;
                    } else if language == Lang.Rust && idx + 2 < trimmed_line.len && trimmed_line[idx] == 'r' && trimmed_line[idx + 1] == '#' && trimmed_line[idx + 2] == '"' {
                        in_multiline_str = true;
                        str_delimiter = '"';
                        str_delimiter_len = 1;
                        idx += 2;
                    } else if language == Lang.Lua && idx + 1 < trimmed_line.len && trimmed_line[idx] == '[' && trimmed_line[idx + 1] == '[' {
                        in_multiline_str = true;
                        str_delimiter = ']';
                        str_delimiter_len = 2;
                        idx += 1;
                    }
                }
            }
            idx++;
        }

        // Report trailing whitespace / carriage return if not in multiline string
        if !line_is_in_multiline_str {
            if trailing_len > 0 {
                let is_cr_only = has_cr && content_len == raw_line.len - 1 && raw_line[raw_line.len - 1] == '\r';
                let rule_sev = if is_cr_only { active_rules.carriage_return_sev } else { active_rules.trailing_spaces_sev };

                if rule_sev != RuleSeverity.Off {
                    let d = Diagnostic {
                        line: line_num,
                        col: (content_len + 1) as! i32,
                        end_col: (raw_line.len + 1) as! i32,
                        rule: if is_cr_only { "no-carriage-return" } else { "no-trailing-spaces" },
                        message: if is_cr_only { "Unexpected carriage return found at end of line" } else { "Trailing whitespace found" },
                        severity: rule_sev
                    };
                    out_diags.push(d);
                }
            }
        }

        // 3. Indentation analysis & fixing
        // Examine leading whitespace
        var leading_spaces: i32 = 0;
        var leading_tabs: i32 = 0;
        var lead_idx = 0;
        while lead_idx < trimmed_line.len && (trimmed_line[lead_idx] == ' ' || trimmed_line[lead_idx] == '\t') {
            if trimmed_line[lead_idx] == ' ' {
                leading_spaces++;
            } else {
                leading_tabs++;
            }
            lead_idx++;
        }

        let is_empty_line = trimmed_line.len == 0;
        let is_mixed = leading_spaces > 0 && leading_tabs > 0;

        // Check for JSDoc / TSDoc exception:
        // Inside a block comment, a line starting with tabs and spaces aligning '*' (e.g. `\t * ...`)
        var is_jsdoc_star_line = false;
        if line_is_in_block_comment && lead_idx < trimmed_line.len && trimmed_line[lead_idx] == '*' {
            is_jsdoc_star_line = true;
        }

        // Check indentation mismatch if not inside multiline string and not an empty line
        if !line_is_in_multiline_str && !is_empty_line {
            if is_mixed && !is_jsdoc_star_line && active_rules.mixed_spaces_tabs_sev != RuleSeverity.Off {
                let d = Diagnostic {
                    line: line_num,
                    col: 1,
                    end_col: (lead_idx + 1) as! i32,
                    rule: "no-mixed-spaces-and-tabs",
                    message: "Mixed spaces and tabs found in indentation",
                    severity: active_rules.mixed_spaces_tabs_sev
                };
                out_diags.push(d);
            } else if !indent_disabled && active_rules.indent_sev != RuleSeverity.Off {
                if target_indent_spaces && leading_tabs > 0 {
                    let d = Diagnostic {
                        line: line_num,
                        col: 1,
                        end_col: (lead_idx + 1) as! i32,
                        rule: "indent",
                        message: "Expected space indentation but found tabs",
                        severity: active_rules.indent_sev
                    };
                    out_diags.push(d);
                } else if !target_indent_spaces && leading_spaces > 0 && !is_jsdoc_star_line {
                    let d = Diagnostic {
                        line: line_num,
                        col: 1,
                        end_col: (lead_idx + 1) as! i32,
                        rule: "indent",
                        message: "Expected tab indentation but found spaces",
                        severity: active_rules.indent_sev
                    };
                    out_diags.push(d);
                }
            }
        }

        // 4. Construct fixed line
        if cfg.fix {
            if is_empty_line {
                if raw_line.len > 0 {
                    was_modified = true;
                }
            } else if line_is_in_multiline_str {
                // Preserve multiline strings verbatim, only strip \r at end if carriage-return rule not off
                if has_cr && raw_line[raw_line.len - 1] == '\r' && active_rules.carriage_return_sev != RuleSeverity.Off {
                    out_fixed.append(raw_line[0..raw_line.len - 1]);
                    was_modified = true;
                } else {
                    out_fixed.append(raw_line);
                }
            } else {
                let rest_of_line = trimmed_line[lead_idx..];
                if indent_disabled || active_rules.indent_sev == RuleSeverity.Off {
                    out_fixed.append(trimmed_line);
                } else {
                    // Indentation conversion
                    if is_jsdoc_star_line {
                        if !target_indent_spaces {
                            for t in leading_tabs { out_fixed.push('\t'); }
                            out_fixed.push(' ');
                            out_fixed.append(rest_of_line);
                        } else {
                            let total_spaces = leading_tabs * indent_step + leading_spaces;
                            for s in total_spaces { out_fixed.push(' '); }
                            out_fixed.append(rest_of_line);
                        }
                    } else if target_indent_spaces {
                        let total_spaces = leading_tabs * indent_step + leading_spaces;
                        for s in total_spaces { out_fixed.push(' '); }
                        out_fixed.append(rest_of_line);
                    } else {
                        let tabs_from_spaces = (leading_spaces + indent_step - 1) / indent_step;
                        let total_tabs = leading_tabs + tabs_from_spaces;
                        for t in total_tabs { out_fixed.push('\t'); }
                        out_fixed.append(rest_of_line);
                    }
                }

                if raw_line.len != (out_fixed.len - line_start) {
                    was_modified = true;
                }
            }

            // Always add standard LF newline
            out_fixed.push('\n');
        }

        line_num++;
    }

    return was_modified;
}

fn is_binary(buf: const u8[:]) -> bool {
    let check_len = if buf.len < 1024 { buf.len } else { 1024 };
    var i = 0;
    while i < check_len {
        if buf[i] == 0 {
            return true;
        }
        i++;
    }
    return false;
}

fn is_git_path(path: const u8[:]) -> bool {
    var i = 0;
    while i < path.len {
        if (i == 0 || path[i - 1] == '/' || path[i - 1] == '\\') && i + 4 <= path.len {
            if path[i] == '.' && path[i + 1] == 'g' && path[i + 2] == 'i' && path[i + 3] == 't' {
                if i + 4 == path.len || path[i + 4] == '/' || path[i + 4] == '\\' {
                    return true;
                }
            }
        }
        i++;
    }
    return false;
}

struct PathBuf {
    bytes: u8[..512]
}

fn collect_dir(dir_path: const u8[:], out: PathBuf[>..]&) {
    if is_git_path(dir_path) {
        return;
    }

    var dir_queue: PathBuf[>..] = [];
    var initial_dir = PathBuf { bytes: [] };
    for b in dir_path { initial_dir.bytes.push(b); }
    dir_queue.push(initial_dir);

    var q_idx = 0;
    while q_idx < dir_queue.len {
        let cur_dir = dir_queue[q_idx].bytes;
        q_idx++;

        if is_git_path(cur_dir) {
            continue;
        }

        var dir_entries: u8[>..] = [];
        if list_dir(cur_dir, dir_entries) {
            var p = 0;
            while p < dir_entries.len {
                let start = p;
                while p < dir_entries.len && dir_entries[p] != '\n' && dir_entries[p] != '\r' {
                    p++;
                }

                if p > start {
                    let entry_name = dir_entries[start..p];
                    if entry_name != ".git" {
                        var full_path = PathBuf { bytes: [] };
                        for b in cur_dir { full_path.bytes.push(b); }
                        if full_path.bytes.len > 0 && full_path.bytes[full_path.bytes.len - 1] != '/' && full_path.bytes[full_path.bytes.len - 1] != '\\' {
                            full_path.bytes.push('/');
                        }
                        for b in entry_name { full_path.bytes.push(b); }

                        if is_dir(full_path.bytes) {
                            dir_queue.push(full_path);
                        } else {
                            out.push(full_path);
                        }
                    }
                }

                while p < dir_entries.len && (dir_entries[p] == '\n' || dir_entries[p] == '\r') {
                    p++;
                }
            }
        }
    }
}

fn print_help() {
    var out: u8[>..] = [];
    format(out,
        "\n", c_bold(), c_green(), "spacelint", c_reset(), ": A fast, language-aware whitespace linter and fixer.\n\n",
        c_bold(), c_yellow(), "Usage:", c_reset(), " ", c_bold(), "spacelint", c_reset(), " [COMMAND] [OPTIONS] [PATH]...\n\n",
        c_bold(), c_cyan(), "Commands:", c_reset(), "\n",
        "  ", c_bold(), "files", c_reset(), "                    Print the list of files that will be linted, then exit\n",
        "  ", c_bold(), "timings", c_reset(), "                  Enable per-rule timing information\n\n",
        c_bold(), c_cyan(), "Arguments:", c_reset(), "\n",
        "  ", c_bold(), "[PATH]...", c_reset(), "                Files or directories to lint (use ", c_bold(), "-", c_reset(), " for stdin)\n\n",
        c_bold(), c_cyan(), "Options:", c_reset(), "\n",
        "  ", c_bold(), "-h, --help", c_reset(), "               Print help information\n",
        "  ", c_bold(), "-v, -V, --version", c_reset(), "        Print version information\n",
        "      ", c_bold(), "--init", c_reset(), "               Create a configuration file (.spacelintrc.json)\n",
        "      ", c_bold(), "--rules", c_reset(), "              List all the rules that are currently registered\n",
        "      ", c_bold(), "--fix", c_reset(), "                Automatically fix whitespace issues\n",
        "  ", c_bold(), "-i, --interactive", c_reset(), "        Prompt to apply fix for each issue\n",
        "      ", c_bold(), "--no-color", c_reset(), "           Disable color output (also respects NO_COLOR env)\n"
    );
    format(out,
        "  ", c_bold(), "-f, --format", c_reset(), " <FORMAT>    Use a specific output format (default, agent, stylish)\n",
        "  ", c_bold(), "-c, --config", c_reset(), " <PATH>      Configuration file (JSON format)\n",
        "  ", c_bold(), "-A, --allow", c_reset(), " <NAME>       Allow / turn off a rule or category (suppress lint)\n",
        "  ", c_bold(), "-W, --warn", c_reset(), " <NAME>        Enable a rule or category as warning\n",
        "  ", c_bold(), "-D, --deny", c_reset(), " <NAME>        Enable a rule or category as error\n",
        "  ", c_bold(), "-C", c_reset(), " <RULE=VALUE>          Configure rule severity or options (supports JSON array syntax)\n",
        "      ", c_bold(), "--max-warnings", c_reset(), " <INT>    Specify a warning threshold to force exit with error\n",
        "      ", c_bold(), "--max-problems", c_reset(), " <INT>    Specify a total problem threshold to force exit with error\n\n",
        c_bold(), c_cyan(), "Examples:", c_reset(), "\n",
        "  spacelint .\n",
        "  spacelint files .\n",
        "  spacelint timings .\n",
        "  spacelint -f agent .\n",
        "  spacelint -f stylish .\n",
        "  spacelint -D no-trailing-spaces -W no-carriage-return\n",
        "  spacelint -A correctness -D no-trailing-spaces\n",
        "  spacelint -A all -D indent -W no-mixed-spaces-and-tabs\n",
        "  spacelint -C indent=warn -C no-trailing-spaces=error\n",
        "  spacelint -C 'indent=[\"error\", 2]'\n",
        "  spacelint -c .spacelintrc.json src/\n",
        "  cat file.js | spacelint -\n",
        "  cat file.js | spacelint --fix - > fixed.js\n\n"
    );
    format(out,
        c_bold(), c_cyan(), "Stdin / Piping:", c_reset(), "\n",
        "  Pass \"", c_bold(), "-", c_reset(), "\" as path to read from standard input (e.g. ", c_dim(), "cat file | spacelint -", c_reset(), ").\n",
        "  Use with ", c_bold(), "--fix", c_reset(), " to write fixed output directly to stdout.\n\n",
        c_bold(), c_cyan(), "Supported file types:", c_reset(), "\n",
        "  ", c_dim(), "TypeScript, JavaScript, JSON, YAML, XML, PROPS, INI, TOML, C++, C, Rust, Zig, Markdown, MDX, Goose, Vlang, D, Lua, Assembly, AssemblyScript, Kotlin, Java, Dart, Odin, Python, Go, Ruby, Shell, PHP, Swift, C#, Scala, CSS, SQL, R, Julia, Perl, Elixir, Erlang, Haskell, Elm, PureScript, GraphQL, Dockerfile, Makefile, Nix, Terraform, Vue, Svelte, Astro, Fortran, Ada, Pascal, OCaml, Clojure, F#, Groovy, PowerShell, Solidity, Nim, Crystal, CMake, Protobuf, Shaders (GLSL, HLSL, WGSL, Metal, Cg, OpenCL, Godot), GameDev (GML, Wren, Squirrel, UnrealScript, QuakeC, Papyrus, GDScript), CSV, TSV, etc.", c_reset(), "\n"
    );
    write_stdout(out);
}

fn print_version() {
    print("spacelint 0.1.0");
}

fn run_init() {
    let config_filename = ".spacelintrc.json";
    var existing: u8[>..] = [];
    if read_file(config_filename, existing) {
        write_stdout("Configuration file .spacelintrc.json already exists.\n");
        return;
    }

    var content: u8[>..] = [];
    format(content,
        "{\n",
        "  \"$schema\": \"https://raw.githubusercontent.com/Mopsgamer/spacelint/main/configuration_schema.json\",\n",
        "  \"categories\": {\n",
        "    \"correctness\": \"warn\",\n",
        "    \"style\": \"warn\"\n",
        "  },\n",
        "  \"rules\": {\n",
        "    \"no-trailing-spaces\": \"warn\",\n",
        "    \"no-carriage-return\": \"warn\",\n",
        "    \"no-mixed-spaces-and-tabs\": \"warn\",\n",
        "    \"indent\": \"warn\"\n",
        "  },\n",
        "  \"overrides\": []\n",
        "}\n"
    );

    if write_file(config_filename, content) {
        write_stdout("Created .spacelintrc.json\n");
    } else {
        write_stderr("Error: Failed to create .spacelintrc.json\n");
        exit(1);
    }
}

fn main() {
    let start_time = clock_ns();
    let cfg = parse_cli_args();
    set_color_enabled(cfg.use_color);

    if cfg.help {
        print_help();
        return;
    }

    if cfg.version {
        print_version();
        return;
    }

    if cfg.init {
        run_init();
        return;
    }

    if cfg.rules {
        print_rules();
        return;
    }

    var total_warnings: i32 = 0;
    var total_errors: i32 = 0;
    var files_processed: i32 = 0;

    // Track rule timing stats
    var timing_no_trailing_spaces_ns: i64 = 0;
    var timing_no_carriage_return_ns: i64 = 0;
    var timing_no_mixed_spaces_tabs_ns: i64 = 0;
    var timing_indent_ns: i64 = 0;

    var calls_no_trailing_spaces: i32 = 0;
    var calls_no_carriage_return: i32 = 0;
    var calls_no_mixed_spaces_tabs: i32 = 0;
    var calls_indent: i32 = 0;

    if cfg.files.len == 0 {
        write_stdout("No files specified. Please specify a file, directory (or '.'): spacelint <file|dir>\n");
        return;
    }

    // Check if reading from stdin
    let is_stdin = cfg.files.len == 1 && cfg.files[0] == "-";

    if is_stdin {
        if cfg.cmd == SubCommand.Files {
            write_stdout("<stdin>\n");
            return;
        }

        var input_bytes: u8[>..] = [];
        read_stdin(input_bytes);

        var fixed_buf: u8[>..] = [];
        var diags: Diagnostic[>..] = [];

        let buf_start = clock_ns();
        process_buffer(input_bytes, "<stdin>", cfg, fixed_buf, diags);
        let buf_elapsed = clock_ns() - buf_start;

        if cfg.cmd == SubCommand.Timings {
            let part = buf_elapsed / 4;
            timing_no_trailing_spaces_ns += part;
            timing_no_carriage_return_ns += part;
            timing_no_mixed_spaces_tabs_ns += part;
            timing_indent_ns += (buf_elapsed - part * 3);
            calls_no_trailing_spaces++;
            calls_no_carriage_return++;
            calls_no_mixed_spaces_tabs++;
            calls_indent++;
        }

        if cfg.fix {
            write_stdout(fixed_buf);
        } else {
            match cfg.format {
                Agent => {
                    for d in diags {
                        match d.severity {
                            Error => { total_errors++; },
                            _ => { total_warnings++; }
                        }
                        print_diagnostic_agent("<stdin>", d.line, d.col, d.rule, d.message, d.severity);
                    }
                },
                Stylish => {
                    if diags.len > 0 {
                        var max_line_col_len: i32 = 0;
                        var max_msg_len: i32 = 0;
                        for d in diags {
                            match d.severity {
                                Error => { total_errors++; },
                                _ => { total_warnings++; }
                            }
                            let lc_len = get_num_digits(d.line) + 1 + get_num_digits(d.col);
                            if lc_len > max_line_col_len { max_line_col_len = lc_len; }
                            if (d.message.len as! i32) > max_msg_len { max_msg_len = d.message.len as! i32; }
                        }
                        var s_out: u8[>..] = [];
                        format_stylish_file_header(s_out, "<stdin>");
                        for d in diags {
                            format_stylish_diagnostic(s_out, d.line, d.col, max_line_col_len, d.rule, d.message, max_msg_len, d.severity);
                        }
                        write_stdout(s_out);
                    }
                    print_stylish_summary(total_warnings, total_errors);
                },
                Default => {
                    for d in diags {
                        match d.severity {
                            Error => { total_errors++; },
                            _ => { total_warnings++; }
                        }
                        print_diagnostic("<stdin>", d.line, d.col, d.end_col, d.rule, d.message, "", d.severity);
                    }
                    let end_time = clock_ns();
                    let elapsed_ms = (end_time - start_time) / 1000000;
                    let max_warn_exceeded = cfg.max_warnings >= 0 && total_warnings > cfg.max_warnings;
                    print_summary(total_warnings, total_errors, 1, elapsed_ms, max_warn_exceeded);
                }
            }

            if cfg.cmd == SubCommand.Timings {
                var timings_list: RuleTimingInfo[>..] = [];
                timings_list.push(RuleTimingInfo { name: "no-trailing-spaces", duration_ns: timing_no_trailing_spaces_ns, calls: calls_no_trailing_spaces });
                timings_list.push(RuleTimingInfo { name: "no-carriage-return", duration_ns: timing_no_carriage_return_ns, calls: calls_no_carriage_return });
                timings_list.push(RuleTimingInfo { name: "no-mixed-spaces-and-tabs", duration_ns: timing_no_mixed_spaces_tabs_ns, calls: calls_no_mixed_spaces_tabs });
                timings_list.push(RuleTimingInfo { name: "indent", duration_ns: timing_indent_ns, calls: calls_indent });
                print_rule_timings(timings_list);
            }
        }

        let max_warn_fail = cfg.max_warnings >= 0 && total_warnings > cfg.max_warnings;
        let max_prob_fail = cfg.max_problems >= 0 && (total_warnings + total_errors) > cfg.max_problems;
        if total_errors > 0 || max_warn_fail || max_prob_fail {
            exit(1);
        }
        return;
    }

    // Expand directories (like '.') into individual files
    var files_to_lint: PathBuf[>..] = [];
    for target in cfg.files {
        if is_dir(target) {
            collect_dir(target, files_to_lint);
        } else {
            var owned_target = PathBuf { bytes: [] };
            for b in target { owned_target.bytes.push(b); }
            files_to_lint.push(owned_target);
        }
    }

    // If 'files' subcommand was passed: print the list of files that will be linted, then exit
    if cfg.cmd == SubCommand.Files {
        for entry in files_to_lint {
            let file_name = entry.bytes;
            if is_git_path(file_name) {
                continue;
            }
            var file_bytes: u8[>..] = [];
            if read_file(file_name, file_bytes) {
                if !is_binary(file_bytes) {
                    write_stdout(file_name);
                    write_stdout("\n");
                }
            }
        }
        return;
    }

    // Process file list
    for entry in files_to_lint {
        let file_name = entry.bytes;
        if is_git_path(file_name) {
            continue;
        }

        var file_bytes: u8[>..] = [];
        if !read_file(file_name, file_bytes) {
            write_stderr("Error: cannot read file ");
            write_stderr(file_name);
            write_stderr("\n");
            total_errors++;
            continue;
        }

        if is_binary(file_bytes) {
            continue;
        }

        files_processed++;
        var fixed_buf: u8[>..] = [];
        var diags: Diagnostic[>..] = [];

        let buf_start = clock_ns();
        let modified = process_buffer(file_bytes, file_name, cfg, fixed_buf, diags);
        let buf_elapsed = clock_ns() - buf_start;

        if cfg.cmd == SubCommand.Timings {
            let part = buf_elapsed / 4;
            timing_no_trailing_spaces_ns += part;
            timing_no_carriage_return_ns += part;
            timing_no_mixed_spaces_tabs_ns += part;
            timing_indent_ns += (buf_elapsed - part * 3);
            calls_no_trailing_spaces++;
            calls_no_carriage_return++;
            calls_no_mixed_spaces_tabs++;
            calls_indent++;
        }

        if cfg.fix {
            if modified {
                write_file(file_name, fixed_buf);
            }
        } else if cfg.interactive {
            if diags.len > 0 {
                var line_starts: i32[>..] = [];
                line_starts.push(0);
                var p = 0;
                while p < file_bytes.len {
                    if file_bytes[p] == '\n' {
                        line_starts.push((p + 1) as! i32);
                    }
                    p++;
                }

                var should_fix_file = false;
                for d in diags {
                    match d.severity {
                        Error => { total_errors++; },
                        _ => { total_warnings++; }
                    }
                    let l_idx = d.line - 1;
                    var line_cnt: u8[>..] = [];
                    if l_idx >= 0 && l_idx < line_starts.len {
                        let ls = line_starts[l_idx];
                        var le = ls;
                        while le < file_bytes.len && file_bytes[le] != '\n' && file_bytes[le] != '\r' {
                            le++;
                        }
                        if le > ls {
                            line_cnt.append(file_bytes[ls..le]);
                        }
                    }

                    var diag_out: u8[>..] = [];
                    format_diagnostic(diag_out, file_name, d.line, d.col, d.end_col, d.rule, d.message, line_cnt, d.severity);
                    write_stdout(diag_out);

                    var prompt_str: u8[>..] = [];
                    format(prompt_str, "  ", c_bold(), c_cyan(), "Apply fix? [yes / no / all / quit] (default: no):", c_reset(), " ");
                    write_stdout(prompt_str);
                    var ans_buf: u8[>..] = [];
                    read_stdin(ans_buf);

                    var choice: u8 = 0;
                    for b in ans_buf {
                        if b != ' ' && b != '\t' && b != '\r' && b != '\n' {
                            choice = b;
                            break;
                        }
                    }

                    if choice == 'y' || choice == 'Y' {
                        should_fix_file = true;
                    } else if choice == 'a' || choice == 'A' {
                        should_fix_file = true;
                        cfg.fix = true;
                        cfg.interactive = false;
                        break;
                    } else if choice == 'q' || choice == 'Q' {
                        return;
                    }
                }

                if should_fix_file && modified {
                    write_file(file_name, fixed_buf);
                    var updated_msg: u8[>..] = [];
                    format(updated_msg, "  ", c_green(), "✔ File updated.", c_reset(), "\n");
                    write_stdout(updated_msg);
                }
            }
        } else {
            if diags.len > 0 {
                match cfg.format {
                    Agent => {
                        var out_batch: u8[>..] = [];
                        for d in diags {
                            match d.severity {
                                Error => { total_errors++; },
                                _ => { total_warnings++; }
                            }
                            format_diagnostic_agent(out_batch, file_name, d.line, d.col, d.rule, d.message, d.severity);
                            if out_batch.len >= 16384 {
                                write_stdout(out_batch);
                                out_batch.clear();
                            }
                        }
                        if out_batch.len > 0 {
                            write_stdout(out_batch);
                        }
                    },
                    Stylish => {
                        var max_line_col_len: i32 = 0;
                        var max_msg_len: i32 = 0;
                        for d in diags {
                            match d.severity {
                                Error => { total_errors++; },
                                _ => { total_warnings++; }
                            }
                            let lc_len = get_num_digits(d.line) + 1 + get_num_digits(d.col);
                            if lc_len > max_line_col_len { max_line_col_len = lc_len; }
                            if (d.message.len as! i32) > max_msg_len { max_msg_len = d.message.len as! i32; }
                        }
                        var s_out: u8[>..] = [];
                        format_stylish_file_header(s_out, file_name);
                        for d in diags {
                            format_stylish_diagnostic(s_out, d.line, d.col, max_line_col_len, d.rule, d.message, max_msg_len, d.severity);
                        }
                        write_stdout(s_out);
                    },
                    Default => {
                        // Precompute line offsets in single pass: O(file_len)
                        var line_starts: i32[>..] = [];
                        line_starts.push(0);
                        var p = 0;
                        while p < file_bytes.len {
                            if file_bytes[p] == '\n' {
                                line_starts.push((p + 1) as! i32);
                            }
                            p++;
                        }

                        var out_batch: u8[>..] = [];
                        for d in diags {
                            match d.severity {
                                Error => { total_errors++; },
                                _ => { total_warnings++; }
                            }
                            let l_idx = d.line - 1;
                            var line_cnt: u8[>..] = [];
                            if l_idx >= 0 && l_idx < line_starts.len {
                                let ls = line_starts[l_idx];
                                var le = ls;
                                while le < file_bytes.len && file_bytes[le] != '\n' && file_bytes[le] != '\r' {
                                    le++;
                                }
                                if le > ls {
                                    line_cnt.append(file_bytes[ls..le]);
                                }
                            }

                            format_diagnostic(out_batch, file_name, d.line, d.col, d.end_col, d.rule, d.message, line_cnt, d.severity);
                            if out_batch.len >= 16384 {
                                write_stdout(out_batch);
                                out_batch.clear();
                            }
                        }
                        if out_batch.len > 0 {
                            write_stdout(out_batch);
                        }
                    }
                }
            }
        }
    }

    if !cfg.fix {
        match cfg.format {
            Agent => {},
            Stylish => {
                print_stylish_summary(total_warnings, total_errors);
            },
            Default => {
                let end_time = clock_ns();
                let elapsed_ms = (end_time - start_time) / 1000000;
                let max_warn_exceeded = cfg.max_warnings >= 0 && total_warnings > cfg.max_warnings;
                print_summary(total_warnings, total_errors, files_processed, elapsed_ms, max_warn_exceeded);
            }
        }

        if cfg.cmd == SubCommand.Timings {
            var timings_list: RuleTimingInfo[>..] = [];
            timings_list.push(RuleTimingInfo { name: "no-trailing-spaces", duration_ns: timing_no_trailing_spaces_ns, calls: calls_no_trailing_spaces });
            timings_list.push(RuleTimingInfo { name: "no-carriage-return", duration_ns: timing_no_carriage_return_ns, calls: calls_no_carriage_return });
            timings_list.push(RuleTimingInfo { name: "no-mixed-spaces-and-tabs", duration_ns: timing_no_mixed_spaces_tabs_ns, calls: calls_no_mixed_spaces_tabs });
            timings_list.push(RuleTimingInfo { name: "indent", duration_ns: timing_indent_ns, calls: calls_indent });
            print_rule_timings(timings_list);
        }
    }

    let max_warn_fail = cfg.max_warnings >= 0 && total_warnings > cfg.max_warnings;
    let max_prob_fail = cfg.max_problems >= 0 && (total_warnings + total_errors) > cfg.max_problems;

    if total_errors > 0 || max_warn_fail || max_prob_fail {
        exit(1);
    }
}
