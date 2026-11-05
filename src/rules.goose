// Core whitespace checking and fixing rules for spacelint.
import std;
import os;

struct Diagnostic {
    line: i32,
    col: i32,
    end_col: i32,
    rule: const u8[:],
    message: const u8[:]
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
            // count consecutive spaces
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
