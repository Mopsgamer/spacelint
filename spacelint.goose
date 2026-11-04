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

    // Determine target indentation for this file
    var target_indent_spaces = false;
    var indent_step: i32 = 4;

    // First check for extension-specific matches
    var matched_rule = false;
    for rule in cfg.indents {
        match rule {
            SpacesExt se => {
                if file_ext == se.ext {
                    target_indent_spaces = true;
                    indent_step = se.n;
                    matched_rule = true;
                    break;
                }
            },
            TabsExt te => {
                if file_ext == te.ext {
                    target_indent_spaces = false;
                    indent_step = 4;
                    matched_rule = true;
                    break;
                }
            },
            AutoExt ae => {
                if file_ext == ae.ext {
                    let sp, st = autodetect_spaces(text);
                    target_indent_spaces = sp;
                    indent_step = st;
                    matched_rule = true;
                    break;
                }
            },
            Tabs => {},
            Spaces _ => {},
            Auto => {}
        }
    }

    // If no extension-specific match, check for global defaults (last specified wins)
    if !matched_rule {
        for rule in cfg.indents {
            match rule {
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
                SpacesExt _ => {},
                TabsExt _ => {},
                AutoExt _ => {}
            }
        }
    }

    // State for tracking multiline block comments and multiline strings
    var in_block_comment = false;
    var in_multiline_str = false;
    var str_delimiter: u8 = 0; // '`', '"', etc.
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
                if c == str_delimiter {
                    // Check for escape
                    if idx == 0 || trimmed_line[idx - 1] != '\\' {
                        in_multiline_str = false;
                    }
                }
            } else if in_block_comment {
                if language == Lang.XML {
                    if idx + 2 < trimmed_line.len && trimmed_line[idx] == '-' && trimmed_line[idx + 1] == '-' && trimmed_line[idx + 2] == '>' {
                        in_block_comment = false;
                        idx += 2;
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
                if language == Lang.XML {
                    if idx + 3 < trimmed_line.len && trimmed_line[idx] == '<' && trimmed_line[idx + 1] == '!' && trimmed_line[idx + 2] == '-' && trimmed_line[idx + 3] == '-' {
                        in_block_comment = true;
                        idx += 3;
                    }
                } else if language == Lang.TypeScript || language == Lang.JavaScript || language == Lang.CPP || language == Lang.C || language == Lang.Rust || language == Lang.Zig || language == Lang.JSON {
                    if idx + 1 < trimmed_line.len && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '*' {
                        in_block_comment = true;
                        idx += 1;
                    } else if idx + 1 < trimmed_line.len && trimmed_line[idx] == '/' && trimmed_line[idx + 1] == '/' {
                        // Line comment to end of line
                        break;
                    }
                } else if language == Lang.YAML || language == Lang.INI || language == Lang.TOML || language == Lang.PROPS {
                    if c == '#' || (language == Lang.INI && c == ';') {
                        // Line comment to end of line
                        break;
                    }
                }

                // Check for multiline string start
                if !in_block_comment {
                    if (language == Lang.TypeScript || language == Lang.JavaScript) && c == '`' {
                        in_multiline_str = true;
                        str_delimiter = '`';
                    } else if language == Lang.TOML && idx + 2 < trimmed_line.len && trimmed_line[idx] == '"' && trimmed_line[idx + 1] == '"' && trimmed_line[idx + 2] == '"' {
                        in_multiline_str = true;
                        str_delimiter = '"';
                        idx += 2;
                    } else if language == Lang.Rust && idx + 2 < trimmed_line.len && trimmed_line[idx] == 'r' && trimmed_line[idx + 1] == '#' && trimmed_line[idx + 2] == '"' {
                        in_multiline_str = true;
                        str_delimiter = '"';
                        idx += 2;
                    }
                }
            }
            idx++;
        }

        // Report trailing whitespace / carriage return if not in multiline string
        if !line_is_in_multiline_str {
            if trailing_len > 0 {
                let is_cr_only = has_cr && content_len == raw_line.len - 1 && raw_line[raw_line.len - 1] == '\r';
                let d = Diagnostic {
                    line: line_num,
                    col: (content_len + 1) as! i32,
                    end_col: (raw_line.len + 1) as! i32,
                    rule: if is_cr_only { "no-carriage-return" } else { "no-trailing-spaces" },
                    message: if is_cr_only { "Unexpected carriage return found at end of line" } else { "Trailing whitespace found" }
                };
                out_diags.push(d);
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
            if is_mixed && !is_jsdoc_star_line {
                let d = Diagnostic {
                    line: line_num,
                    col: 1,
                    end_col: (lead_idx + 1) as! i32,
                    rule: "no-mixed-spaces-and-tabs",
                    message: "Mixed spaces and tabs found in indentation"
                };
                out_diags.push(d);
            } else if target_indent_spaces && leading_tabs > 0 {
                let d = Diagnostic {
                    line: line_num,
                    col: 1,
                    end_col: (lead_idx + 1) as! i32,
                    rule: "indent",
                    message: "Expected space indentation but found tabs"
                };
                out_diags.push(d);
            } else if !target_indent_spaces && leading_spaces > 0 && !is_jsdoc_star_line {
                let d = Diagnostic {
                    line: line_num,
                    col: 1,
                    end_col: (lead_idx + 1) as! i32,
                    rule: "indent",
                    message: "Expected tab indentation but found spaces"
                };
                out_diags.push(d);
            }
        }

        // 4. Construct fixed line
        if cfg.fix {
            if is_empty_line {
                if raw_line.len > 0 {
                    was_modified = true;
                }
            } else if line_is_in_multiline_str {
                // Preserve multiline strings verbatim, only strip \r at end if present
                if has_cr && raw_line[raw_line.len - 1] == '\r' {
                    out_fixed.append(raw_line[0..raw_line.len - 1]);
                    was_modified = true;
                } else {
                    out_fixed.append(raw_line);
                }
            } else {
                let rest_of_line = trimmed_line[lead_idx..];
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
        "\n\x1b[1m\x1b[32mspacelint\x1b[0m: A fast, language-aware whitespace linter and fixer.\n\n",
        "\x1b[1m\x1b[33mUsage:\x1b[0m \x1b[1mspacelint\x1b[0m [OPTIONS] [PATH]...\n\n",
        "\x1b[1m\x1b[36mArguments:\x1b[0m\n",
        "  \x1b[1m[PATH]...\x1b[0m                Files or directories to lint (use \x1b[1m-\x1b[0m for stdin)\n\n",
        "\x1b[1m\x1b[36mOptions:\x1b[0m\n",
        "  \x1b[1m-h, --help\x1b[0m               Print help information\n",
        "  \x1b[1m-v, -V, --version\x1b[0m        Print version information\n",
        "      \x1b[1m--fix\x1b[0m                Automatically fix whitespace issues\n",
        "  \x1b[1m-i, --interactive\x1b[0m        Prompt to apply fix for each issue\n",
        "      \x1b[1m--indent\x1b[0m <MODE>      Set indentation mode (can be specified multiple times):\n",
        "                             \x1b[32mtabs\x1b[0m            Require tabs (default)\n",
        "                             \x1b[32m<N>\x1b[0m             Require N spaces (e.g. 2, 4)\n",
        "                             \x1b[32mauto\x1b[0m            Autodetect per file\n",
        "                             \x1b[32mauto.<EXT>\x1b[0m      Autodetect for extension (e.g. auto.yml)\n",
        "                             \x1b[32m<N>.<EXT>\x1b[0m       Require N spaces for extension (e.g. 2.json)\n",
        "                             \x1b[32mtabs.<EXT>\x1b[0m      Require tabs for extension (e.g. tabs.go)\n\n",
        "\x1b[1m\x1b[36mExamples:\x1b[0m\n",
        "  spacelint .\n",
        "  spacelint --indent 2.json --indent 4.py src/\n",
        "  cat file.js | spacelint -\n",
        "  cat file.js | spacelint --fix - > fixed.js\n\n",
        "\x1b[1m\x1b[36mStdin / Piping:\x1b[0m\n",
        "  Pass \"\x1b[1m-\x1b[0m\" as path to read from standard input (e.g. \x1b[2mcat file | spacelint -\x1b[0m).\n",
        "  Use with \x1b[1m--fix\x1b[0m to write fixed output directly to stdout.\n\n",
        "\x1b[1m\x1b[36mSupported file types:\x1b[0m\n",
        "  \x1b[2mTypeScript, JavaScript, JSON, YAML, XML, PROPS, INI, TOML, C++, C, Rust, Zig, etc.\x1b[0m\n"
    );
    write_stdout(out);
}

fn print_version() {
    print("spacelint 0.1.0");
}

fn main() {
    let start_time = clock_ns();
    let cfg = parse_cli_args();

    if cfg.help {
        print_help();
        return;
    }

    if cfg.version {
        print_version();
        return;
    }

    var total_warnings: i32 = 0;
    var total_errors: i32 = 0;
    var files_processed: i32 = 0;

    if cfg.files.len == 0 {
        write_stdout("No files specified. Please specify a file, directory (or '.'): spacelint <file|dir>\n");
        return;
    }

    // Check if reading from stdin
    let is_stdin = cfg.files.len == 1 && cfg.files[0] == "-";

    if is_stdin {
        var input_bytes: u8[>..] = [];
        read_stdin(input_bytes);

        var fixed_buf: u8[>..] = [];
        var diags: Diagnostic[>..] = [];

        process_buffer(input_bytes, "<stdin>", cfg, fixed_buf, diags);

        if cfg.fix {
            write_stdout(fixed_buf);
        } else {
            // Print diagnostics in oxlint style
            for d in diags {
                total_warnings++;
                print_diagnostic("<stdin>", d.line, d.col, d.end_col, d.rule, d.message, "");
            }
            let end_time = clock_ns();
            let elapsed_ms = (end_time - start_time) / 1000000;
            print_summary(total_warnings, total_errors, 1, elapsed_ms);
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

        let modified = process_buffer(file_bytes, file_name, cfg, fixed_buf, diags);

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
                    total_warnings++;
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
                    format_diagnostic(diag_out, file_name, d.line, d.col, d.end_col, d.rule, d.message, line_cnt);
                    write_stdout(diag_out);

                    write_stdout("  \x1b[1m\x1b[36mApply fix? [yes / no / all / quit] (default: no):\x1b[0m ");
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
                    write_stdout("  \x1b[32m✔ File updated.\x1b[0m\n");
                }
            }
        } else {
            if diags.len > 0 {
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
                    total_warnings++;
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

                    format_diagnostic(out_batch, file_name, d.line, d.col, d.end_col, d.rule, d.message, line_cnt);
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

    if !cfg.fix {
        let end_time = clock_ns();
        let elapsed_ms = (end_time - start_time) / 1000000;
        print_summary(total_warnings, total_errors, files_processed, elapsed_ms);
    }
}
