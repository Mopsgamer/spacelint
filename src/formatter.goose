// Oxlint-style diagnostic and summary formatting for spacelint with ANSI colors.
import std;
import os;

// ANSI escape helpers
const ANSI_RESET: const u8[:] = "\x1b[0m";
const ANSI_BOLD: const u8[:] = "\x1b[1m";
const ANSI_DIM: const u8[:] = "\x1b[2m";
const ANSI_UNDERLINE: const u8[:] = "\x1b[4m";
const ANSI_YELLOW: const u8[:] = "\x1b[33m";
const ANSI_GOLD: const u8[:] = "\x1b[38;2;255;180;84m";
const ANSI_RED: const u8[:] = "\x1b[31m";
const ANSI_GREEN: const u8[:] = "\x1b[32m";
const ANSI_CYAN: const u8[:] = "\x1b[36m";
const ANSI_BLUE: const u8[:] = "\x1b[34m";
const ANSI_MAGENTA: const u8[:] = "\x1b[35m";

fn print_rules() {
    var out: u8[>..] = [];
    format(out,
        "## Correctness (3)\n",
        "Code that is outright wrong or useless.\n",
        "| Rule name                    | Source     | Default | Enabled? | Fixable? |\n",
        "| ---------------------------- | ---------- | ------- | -------- | -------- |\n",
        "| no-carriage-return           | eslint     | ✅      | ✅       | 🛠️        |\n",
        "| no-mixed-spaces-and-tabs     | eslint     | ✅      | ✅       | 🛠️        |\n",
        "| no-trailing-spaces           | eslint     | ✅      | ✅       | 🛠️        |\n\n",
        "## Style (1)\n",
        "Code that should be written in a more idiomatic way.\n",
        "| Rule name                    | Source     | Default | Enabled? | Fixable? |\n",
        "| ---------------------------- | ---------- | ------- | -------- | -------- |\n",
        "| indent                       | eslint     | ✅      | ✅       | 🛠️        |\n\n",
        "Default: 4\n",
        "Total: 4\n"
    );
    write_stdout(out);
}

fn format_diagnostic(out: u8[>..]&, file: const u8[:], line_num: i32, col: i32, end_col: i32, rule: const u8[:], msg: const u8[:], line_content: const u8[:]) {
    var num_len = 0;
    var n = line_num;
    if n <= 0 {
        num_len = 1;
    } else {
        while n > 0 {
            num_len++;
            n = n / 10;
        }
    }
    let gutter_w = if num_len > 3 { num_len } else { 3 };

    // Header: "  ⚠ spacelint(rule): msg"
    format(out, "\n  ", ANSI_GOLD, ANSI_BOLD, "⚠ ", ANSI_RESET, ANSI_BOLD, "spacelint(", ANSI_RESET, ANSI_DIM, rule, ANSI_RESET, ANSI_BOLD, "): ", ANSI_RESET, msg, "\n");

    // Top border: e.g. "   ╭─[" aligning ╭ with │
    var k = 0;
    while k <= gutter_w {
        out.push(' ');
        k++;
    }
    format(out, "╭─[", ANSI_RESET, ANSI_BOLD, ANSI_BLUE, file, ANSI_RESET, ":", line_num, ":", col, "]", "\n");

    // Content line: " 1 │ ..." with tabs expanded for visual alignment
    var padding = gutter_w - num_len;
    while padding > 0 {
        out.push(' ');
        padding--;
    }
    format(out, ANSI_DIM, line_num, ANSI_RESET, " │ ");

    var visual_col_at_char: i32[>..] = [];
    var cur_vis_col: i32 = 1;
    var ci = 0;
    while ci < line_content.len {
        visual_col_at_char.push(cur_vis_col);
        let ch = line_content[ci];
        if ch == '\t' {
            let tab_stop: i32 = 4;
            let spaces_to_add: i32 = tab_stop - ((cur_vis_col - 1) % tab_stop);
            var s = 0;
            while s < spaces_to_add {
                out.push(' ');
                s++;
            }
            cur_vis_col += spaces_to_add;
        } else {
            out.push(ch);
            cur_vis_col++;
        }
        ci++;
    }
    visual_col_at_char.push(cur_vis_col);
    out.push('\n');

    // Underline marker: e.g. "   · " aligning · with │
    k = 0;
    while k <= gutter_w {
        out.push(' ');
        k++;
    }
    format(out, "· ", ANSI_MAGENTA);

    // Determine visual start and end columns for the caret underline
    var vis_col = 1;
    var vis_end = 2;
    let col_idx = col - 1;
    if col_idx >= 0 && col_idx < visual_col_at_char.len {
        vis_col = visual_col_at_char[col_idx];
    } else {
        vis_col = col;
    }

    let end_idx = end_col - 1;
    if end_idx >= 0 && end_idx < visual_col_at_char.len {
        vis_end = visual_col_at_char[end_idx];
    } else {
        vis_end = if end_col > col { vis_col + (end_col - col) } else { vis_col + 1 };
    }

    var i = 1;
    while i < vis_col {
        out.push(' ');
        i++;
    }
    let underline_len = if vis_end > vis_col { vis_end - vis_col } else { 1 };
    var j = 0;
    while j < underline_len {
        // UTF-8 string for '─' (U+2500)
        format(out, "─");
        j++;
    }

    format(out, ANSI_RESET, "\n");

    // Bottom border: e.g. "   ╰────\n" aligning ╰ with │
    k = 0;
    while k <= gutter_w {
        out.push(' ');
        k++;
    }
    format(out, "╰────", ANSI_RESET, "\n");
}

fn print_diagnostic(file: const u8[:], line_num: i32, col: i32, end_col: i32, rule: const u8[:], msg: const u8[:], line_content: const u8[:]) {
    var buf: u8[>..] = [];
    format_diagnostic(buf, file, line_num, col, end_col, rule, msg, line_content);
    write_stdout(buf);
}

fn format_diagnostic_agent(out: u8[>..]&, file: const u8[:], line_num: i32, col: i32, rule: const u8[:], msg: const u8[:]) {
    // Format: file:line:col: warning spacelint(rule): msg
    format(out, file, ":", line_num, ":", col, ": warning spacelint(", rule, "): ", msg, "\n");
}

fn print_diagnostic_agent(file: const u8[:], line_num: i32, col: i32, rule: const u8[:], msg: const u8[:]) {
    var buf: u8[>..] = [];
    format_diagnostic_agent(buf, file, line_num, col, rule, msg);
    write_stdout(buf);
}

fn get_num_digits(n: i32) -> i32 {
    if n <= 0 { return 1; }
    var len: i32 = 0;
    var v = n;
    while v > 0 {
        len++;
        v = v / 10;
    }
    return len;
}

// Format stylish header for a file: \n\x1b[4m<file>\x1b[0m\n
fn format_stylish_file_header(out: u8[>..]&, file: const u8[:]) {
    format(out, "\n", ANSI_UNDERLINE, file, ANSI_RESET, "\n");
}

// Format a single stylish item with line_col_w and msg_w for column alignment
fn format_stylish_diagnostic(out: u8[>..]&, line_num: i32, col: i32, max_line_col_len: i32, rule: const u8[:], msg: const u8[:], max_msg_len: i32) {
    let cur_line_col_len = get_num_digits(line_num) + 1 + get_num_digits(col);
    let pad_before = max_line_col_len - cur_line_col_len;

    out.push(' ');
    out.push(' ');
    var p = 0;
    while p < pad_before {
        out.push(' ');
        p++;
    }

    format(out, ANSI_DIM, line_num, ":", col, ANSI_RESET, "  ", ANSI_GOLD, "warning", ANSI_RESET, "  ", msg);

    var msg_pad = max_msg_len - msg.len;
    while msg_pad > 0 {
        out.push(' ');
        msg_pad--;
    }

    format(out, "  ", ANSI_DIM, "spacelint(", rule, ")", ANSI_RESET, "\n");
}

fn print_stylish_summary(warnings: i32, errors: i32) {
    let total = warnings + errors;
    if total == 0 {
        return;
    }
    var out: u8[>..] = [];
    format(out, "\n", ANSI_GOLD, "✖ ", total, if total == 1 { " problem" } else { " problems" },
        " (", errors, if errors == 1 { " error" } else { " errors" }, ", ",
        warnings, if warnings == 1 { " warning" } else { " warnings" }, ")\n", ANSI_RESET);
    write_stdout(out);
}

fn print_summary(warnings: i32, errors: i32, files_count: i32, elapsed_ms: i64) {
    var out: u8[>..] = [];

    if errors > 0 {
        format(out, "\n", ANSI_BOLD, ANSI_RED, "Found ", errors, if errors == 1 { " error" } else { " errors" }, ANSI_RESET);
        if warnings > 0 {
            format(out, ANSI_BOLD, ANSI_GOLD, " and ", warnings, if warnings == 1 { " warning" } else { " warnings" }, ANSI_RESET);
        }
    } else if warnings > 0 {
        format(out, "\n", ANSI_BOLD, ANSI_GOLD, "Found ", warnings, if warnings == 1 { " warning" } else { " warnings" }, ANSI_RESET);
    } else {
        format(out, "\n", ANSI_BOLD, ANSI_GREEN, "Finished", ANSI_RESET);
    }

    format(out, " on ", ANSI_BOLD, files_count, if files_count == 1 { " file" } else { " files" }, ANSI_RESET);

    if elapsed_ms >= 1000 {
        let sec = (elapsed_ms as! f64) / 1000.0;
        format(out, ANSI_DIM, " (", sec, "s)", ANSI_RESET, "\n");
    } else {
        format(out, ANSI_DIM, " (", elapsed_ms, "ms)", ANSI_RESET, "\n");
    }

    write_stdout(out);
}
