// Glob pattern matching helper for spacelint configuration overrides.
// Patterns are pre-parsed into inline stack structures for fast traversal and evaluation.
import std;

enum GlobKind {
    Exact,
    Prefix,
    Suffix,
    General
}

struct ParsedGlob {
    kind: GlobKind,
    has_slash: bool,
    pattern: u8[..128],
    prefix_or_suffix: u8[..64]
}

recursive fn glob_match_core(pattern: const u8[:], path: const u8[:]) -> bool {
    if pattern.len >= 3 && pattern[0] == '*' && pattern[1] == '*' && pattern[2] == '/' {
        let rest = pattern[3..];
        if glob_match_core(rest, path) {
            return true;
        }
        var i: i64 = 0;
        while i < path.len {
            if path[i] == '/' {
                if glob_match_core(rest, path[i + 1..]) {
                    return true;
                }
            }
            i++;
        }
        return false;
    }

    var p: i64 = 0;
    var s: i64 = 0;
    var star_p: i64 = -1;
    var match_s: i64 = 0;

    while s < path.len {
        if p < pattern.len && pattern[p] == path[s] {
            p++;
            s++;
        } else if p < pattern.len && pattern[p] == '?' {
            if path[s] == '/' {
                return false;
            }
            p++;
            s++;
        } else if p < pattern.len && pattern[p] == '*' {
            if p + 1 < pattern.len && pattern[p + 1] == '*' {
                var rest_p = p + 2;
                if rest_p < pattern.len && pattern[rest_p] == '/' {
                    rest_p++;
                }
                let rest = pattern[rest_p..];
                var sub_s = s;
                while sub_s <= path.len {
                    if glob_match_core(rest, path[sub_s..]) {
                        return true;
                    }
                    sub_s++;
                }
                return false;
            } else {
                star_p = p;
                p++;
                match_s = s;
            }
        } else if star_p != -1 {
            if path[match_s] == '/' {
                return false;
            }
            p = star_p + 1;
            match_s++;
            s = match_s;
        } else {
            return false;
        }
    }

    while p < pattern.len && pattern[p] == '*' {
        p++;
    }

    return p == pattern.len;
}

fn normalize_path_for_match(path: const u8[:], out: u8[>..]&) {
    var start: i64 = 0;
    if path.len >= 2 && path[0] == '.' && (path[1] == '/' || path[1] == '\\') {
        start = 2;
    }
    var i = start;
    while i < path.len {
        if path[i] == '\\' {
            out.push('/');
        } else {
            out.push(path[i]);
        }
        i++;
    }
}

fn parse_single_glob(raw: const u8[:]) -> ParsedGlob {
    var norm: u8[>..] = [];
    normalize_path_for_match(raw, norm);

    var p = ParsedGlob {
        kind: GlobKind.General,
        has_slash: false,
        pattern: [],
        prefix_or_suffix: []
    };
    for b in norm {
        if b == '/' { p.has_slash = true; }
        p.pattern.push(b);
    }

    var star_count: i64 = 0;
    var q_count: i64 = 0;
    var star_idx: i64 = -1;
    var i: i64 = 0;
    while i < p.pattern.len {
        if p.pattern[i] == '*' {
            star_count++;
            star_idx = i;
        } else if p.pattern[i] == '?' {
            q_count++;
        }
        i++;
    }

    // Exact matches: direct equality / subpath check
    if star_count == 0 && q_count == 0 {
        p.kind = GlobKind.Exact;
    } else if star_count == 1 && q_count == 0 {
        if star_idx == 0 {
            // Suffix check: e.g. *.rs
            p.kind = GlobKind.Suffix;
            let suffix = p.pattern[1..];
            for b in suffix { p.prefix_or_suffix.push(b); }
        } else if star_idx == p.pattern.len - 1 {
            // Prefix check: e.g. abc*
            p.kind = GlobKind.Prefix;
            let prefix = p.pattern[0..p.pattern.len - 1];
            for b in prefix { p.prefix_or_suffix.push(b); }
        } else {
            p.kind = GlobKind.General;
        }
    } else {
        p.kind = GlobKind.General;
    }

    return p;
}

fn parse_pattern_into_globs(pattern: const u8[:], out: ParsedGlob[..16]&) {
    var brace_start: i64 = -1;
    var brace_end: i64 = -1;
    var i: i64 = 0;
    while i < pattern.len {
        if pattern[i] == '{' && brace_start == -1 {
            brace_start = i;
        } else if pattern[i] == '}' && brace_start != -1 {
            brace_end = i;
            break;
        }
        i++;
    }

    if brace_start >= 0 && brace_end > brace_start {
        let prefix = pattern[0..brace_start];
        let suffix = pattern[brace_end + 1..];
        let choices = pattern[brace_start + 1..brace_end];

        var part_start: i64 = 0;
        var p: i64 = 0;
        while p <= choices.len {
            if p == choices.len || choices[p] == ',' {
                let choice = choices[part_start..p];
                var expanded: u8[>..] = [];
                for b in prefix { expanded.push(b); }
                for b in choice { expanded.push(b); }
                for b in suffix { expanded.push(b); }
                out.push(parse_single_glob(expanded));
                part_start = p + 1;
            }
            p++;
        }
    } else {
        out.push(parse_single_glob(pattern));
    }
}

fn match_parsed_glob(pg: const ParsedGlob&, path: const u8[:]) -> bool {
    let pat = pg.pattern;

    match pg.kind {
        Exact => {
            if path == pat { return true; }
            if !pg.has_slash {
                var base_idx: i64 = 0;
                var j: i64 = 0;
                while j < path.len {
                    if path[j] == '/' { base_idx = j + 1; }
                    j++;
                }
                if path[base_idx..] == pat { return true; }
            }
            if pat.len > 0 {
                if pat.len <= path.len && path[0..pat.len] == pat && (path.len == pat.len || path[pat.len] == '/') {
                    return true;
                }
                var idx: i64 = 0;
                while idx < path.len {
                    if path[idx] == '/' {
                        let sub = path[idx + 1..];
                        if pat.len <= sub.len && sub[0..pat.len] == pat && (sub.len == pat.len || sub[pat.len] == '/') {
                            return true;
                        }
                    }
                    idx++;
                }
            }
            return false;
        },
        Suffix => {
            let suf = pg.prefix_or_suffix;
            if suf.len <= path.len && path[path.len - suf.len..] == suf {
                return true;
            }
            return false;
        },
        Prefix => {
            let pref = pg.prefix_or_suffix;
            if pref.len <= path.len && path[0..pref.len] == pref {
                return true;
            }
            var k: i64 = 0;
            while k < path.len {
                if path[k] == '/' {
                    let sub = path[k + 1..];
                    if pref.len <= sub.len && sub[0..pref.len] == pref {
                        return true;
                    }
                }
                k++;
            }
            return false;
        },
        General => {
            if glob_match_core(pat, path) { return true; }
            var k: i64 = 0;
            while k < path.len {
                if path[k] == '/' {
                    if glob_match_core(pat, path[k + 1..]) { return true; }
                }
                k++;
            }
            if !pg.has_slash {
                var base_idx: i64 = 0;
                var j: i64 = 0;
                while j < path.len {
                    if path[j] == '/' { base_idx = j + 1; }
                    j++;
                }
                if glob_match_core(pat, path[base_idx..]) { return true; }
            }
            return false;
        }
    }
}
