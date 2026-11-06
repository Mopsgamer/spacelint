#!/usr/bin/env python3
import subprocess
import os
import sys
import tempfile
import shutil
import re
import json

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPACELINT_BIN = os.path.join(ROOT_DIR, "spacelint")
FIXTURES_DIR = os.path.join(ROOT_DIR, "tests", "fixtures")

def run_cmd(cmd, input_data=None):
    proc = subprocess.run(
        cmd,
        cwd=ROOT_DIR,
        input=input_data.encode("utf-8") if input_data else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False
    )
    return proc.returncode, proc.stdout.decode("utf-8", errors="replace"), proc.stderr.decode("utf-8", errors="replace")

def strip_ansi(text):
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', text)

def test_cli_flags():
    print("Testing CLI flags...")
    # --help
    code, out, _ = run_cmd([SPACELINT_BIN, "--help"])
    assert code == 0, f"--help failed: code={code}"
    clean_out = strip_ansi(out)
    assert "Usage: spacelint" in clean_out, "--help output missing usage"

    # -h
    code, out, _ = run_cmd([SPACELINT_BIN, "-h"])
    assert code == 0, f"-h failed: code={code}"
    clean_out = strip_ansi(out)
    assert "Usage: spacelint" in clean_out, "-h output missing usage"

    # --version
    code, out, _ = run_cmd([SPACELINT_BIN, "--version"])
    assert code == 0, f"--version failed: code={code}"
    assert "spacelint" in out, "--version output missing spacelint"

    # -v
    code, out, _ = run_cmd([SPACELINT_BIN, "-v"])
    assert code == 0, f"-v failed: code={code}"
    assert "spacelint" in out, "-v output missing spacelint"

    # -V
    code, out, _ = run_cmd([SPACELINT_BIN, "-V"])
    assert code == 0, f"-V failed: code={code}"
    assert "spacelint" in out, "-V output missing spacelint"

    print("  CLI flags tests passed!")

def test_language_fixtures():
    print("Testing all language fixtures for trailing whitespace detection...")
    fixtures = [
        "test.ts", "test.js", "test.json", "test.yaml", "test.xml",
        "test.properties", "test.ini", "test.toml", "test.cpp", "test.c",
        "test.rs", "test.zig", "test.md", "test.mdx", "test.goose",
        "test.v", "test.d", "test.lua", "test.asm", "test.as",
        "test.kt", "test.java", "test.dart", "test.odin", "test.py",
        "test.go", "test.rb", "test.sh", "test.php", "test.swift",
        "test.cs", "test.scala", "test.css", "test.sql", "test.r",
        "test.jl", "test.pl", "test.ex", "test.erl", "test.hs",
        "test.elm", "test.purs", "test.graphql", "Dockerfile",
        "Makefile", "test.nix", "test.tf", "test.vue", "test.svelte",
        "test.astro", "test.f90", "test.adb", "test.pas", "test.ml",
        "test.clj", "test.fs", "test.groovy", "test.ps1", "test.sol",
        "test.nim", "test.cr", "CMakeLists.txt", "test.proto", "test.glsl",
        "test.tcl", "test.awk", "test.cob", "test.st", "test.vhdl",
        "test.coffee", "test.hx", "test.mojo", "test.jsonnet", "test.dhall",
        "test.typ", "test.kdl", "test.cue", "test.rego",
        "test.gotmpl", "test.pcss", "test.styl",
        "test.cls", "test.bal", "test.chpl", "test.gd",
        "test.qml", "test.raku", "test.res", "test.bzl",
        "test.vala", "test.wl", "test.hlsl", "test.metal",
        "test.gdshader", "test.gml", "test.wren", "test.nut",
        "test.psc", "test.qc", "test.csv", "test.tsv"
    ]
    for fix in fixtures:
        path = os.path.join(FIXTURES_DIR, fix)
        assert os.path.exists(path), f"Fixture missing: {path}"
        code, out, err = run_cmd([SPACELINT_BIN, path])
        assert code == 0, f"Lint failed on {fix}: code={code}, err={err}"
        assert "no-trailing-spaces" in out, f"Expected no-trailing-spaces warning for {fix}, got:\n{out}"
        assert "Found 1 warning and 0 errors" in out or "Found" in out, f"Summary missing for {fix}"
        print(f"  Passed fixture: {fix}")

def test_obscure_edge_cases():
    print("Testing obscure comment edge cases...")
    # 1. Comment syntax inside multiline template string literal
    path_str = os.path.join(FIXTURES_DIR, "obscure_comment_in_multiline_str.ts")
    code, out, _ = run_cmd([SPACELINT_BIN, path_str])
    assert code == 0
    assert "Finished" in out and "Found" not in out, f"Should have 0 warnings, got:\n{out}"

    # 2. JSDoc / TSDoc space-aligned asterisk comments
    path_jsdoc = os.path.join(FIXTURES_DIR, "obscure_jsdoc_star_align.ts")
    code, out, _ = run_cmd([SPACELINT_BIN, path_jsdoc])
    assert code == 0
    assert "Finished" in out and "Found" not in out, f"Should have 0 warnings for JSDoc, got:\n{out}"

    # 3. Triple-quote multiline string containing single quotes and double quotes
    with tempfile.NamedTemporaryFile("w+", suffix=".py", delete=False) as tf:
        tf.write('"""\nInside multiline string with \'single\' and "double" quote.\n# not a comment\n"""\n')
        tf_name = tf.name
    try:
        code, out, _ = run_cmd([SPACELINT_BIN, tf_name])
        assert code == 0
        assert "Finished" in out and "Found" not in out, f"Should have 0 warnings for multiline quotes, got:\n{out}"
    finally:
        os.remove(tf_name)

    # 4. Long filename (> 64 chars)
    long_name = "test_very_long_file_name_exceeding_sixty_four_characters_for_safety_check.py"
    with tempfile.TemporaryDirectory() as td:
        fpath = os.path.join(td, long_name)
        with open(fpath, "w") as f:
            f.write('print("OK")\n')
        code, out, _ = run_cmd([SPACELINT_BIN, fpath])
        assert code == 0
        assert "Finished" in out and "Found" not in out, f"Long filename failed: {out}"

    print("  Obscure edge case tests passed!")

def test_piping_and_fix():
    print("Testing piping and --fix...")
    # Piping with newline and carriage return
    test_input = "const a = 1;   \r\n\tconst b = 2;  \r\n"
    code, out, _ = run_cmd([SPACELINT_BIN, "--fix", "-"], input_data=test_input)
    assert code == 0
    assert "\r" not in out, "Carriage returns should be removed in fixed output"
    lines = out.split("\n")
    assert lines[0] == "const a = 1;"
    assert lines[1] == "\tconst b = 2;"

    print("  Piping and --fix tests passed!")

def test_indent_options_via_c():
    print("Testing indent rule options via -C (tabs, spaces, auto, auto.<ext>)...")
    # indent tabs
    code, out, _ = run_cmd([SPACELINT_BIN, "-C", "indent=tabs", "-"], input_data="    let x = 1;\n")
    assert code == 0
    assert "indent" in out and "Expected tab indentation" in out

    # indent spaces
    code, out, _ = run_cmd([SPACELINT_BIN, "-C", "indent=4", "-"], input_data="\tlet x = 1;\n")
    assert code == 0
    assert "indent" in out and "Expected space indentation" in out

    # auto
    with tempfile.NamedTemporaryFile("w+", suffix=".yaml", delete=False, newline="") as tf:
        tf.write("services:\n  app:\n    image: redis\n")
        tf_name = tf.name
        tf.close()

    try:
        code, out, _ = run_cmd([SPACELINT_BIN, "-C", "indent=auto", tf_name])
        assert code == 0
        assert "Finished" in out and "Found" not in out
    finally:
        os.remove(tf_name)

    # auto.<ext>
    with tempfile.NamedTemporaryFile("w+", suffix=".yml", delete=False, newline="") as tf:
        tf.write("services:\n  app:\n    image: redis\n")
        tf_name = tf.name
        tf.close()

    try:
        code, out, _ = run_cmd([SPACELINT_BIN, "-C", "indent=auto.yml", tf_name])
        assert code == 0
        assert "Finished" in out and "Found" not in out
    finally:
        os.remove(tf_name)

    print("  Indent options via -C tests passed!")

def test_in_place_fix():
    print("Testing in-place --fix file modification...")
    with tempfile.NamedTemporaryFile("w+", suffix=".ts", delete=False) as tf:
        tf.write("export const val = 42;   \r\n")
        tf_name = tf.name
        tf.close()

    try:
        code, out, _ = run_cmd([SPACELINT_BIN, "--fix", tf_name])
        assert code == 0
        with open(tf_name, "rb") as f:
            fixed_content = f.read().decode("utf-8")
        assert fixed_content == "export const val = 42;\n", f"Unexpected fixed content: {repr(fixed_content)}"
    finally:
        os.remove(tf_name)

    print("  In-place --fix tests passed!")

def test_rules():
    print("Testing --rules flag...")
    code, out, _ = run_cmd([SPACELINT_BIN, "--rules"])
    assert code == 0, f"--rules failed: code={code}"
    assert "## Correctness" in out, "--rules output missing Correctness section"
    assert "no-trailing-spaces" in out, "--rules output missing no-trailing-spaces"
    assert "no-carriage-return" in out, "--rules output missing no-carriage-return"
    assert "no-mixed-spaces-and-tabs" in out, "--rules output missing no-mixed-spaces-and-tabs"
    assert "## Style" in out, "--rules output missing Style section"
    assert "indent" in out, "--rules output missing indent"
    assert "Total: 4" in out, "--rules output missing total"
    print("  --rules tests passed!")

def test_rule_options_and_categories():
    print("Testing -A, -W, -D, -C, --config, categories and JSON syntax...")

    # 1. Enable rules as errors (-D)
    code, out, _ = run_cmd([SPACELINT_BIN, "-D", "no-trailing-spaces", "-"], input_data="let x = 1; \n")
    assert code == 1, "Exit code should be 1 on error"
    assert "error" in out or "✖" in out
    assert "no-trailing-spaces" in out

    # Unknown plugin rules supported gracefully
    code, out, _ = run_cmd([SPACELINT_BIN, "-D", "no-console", "-D", "eqeqeq", "-"], input_data="let x = 1;\n")
    assert code == 0, "Unknown rules enabled should not fail execution when no violations"

    # 2. Enable rules as warnings (-W)
    code, out, _ = run_cmd([SPACELINT_BIN, "-W", "no-trailing-spaces", "-"], input_data="let x = 1; \n")
    assert code == 0
    assert "warning" in out
    assert "no-trailing-spaces" in out

    # 3. Turn off specific rules (-A)
    code, out, _ = run_cmd([SPACELINT_BIN, "-A", "no-trailing-spaces", "-"], input_data="let x = 1; \n")
    assert code == 0
    assert "Finished" in out
    assert "no-trailing-spaces" not in out

    # 4. -C rule=warn -C rule=error
    code, out, _ = run_cmd([SPACELINT_BIN, "-C", "no-trailing-spaces=error", "-"], input_data="let x = 1; \n")
    assert code == 1
    assert "error" in out
    assert "no-trailing-spaces" in out

    code, out, _ = run_cmd([SPACELINT_BIN, "-C", "no-trailing-spaces=warn", "-"], input_data="let x = 1; \n")
    assert code == 0
    assert "warning" in out
    assert "no-trailing-spaces" in out

    # 5. Pass options array via JSON syntax
    # -C 'indent=["error", 2]'
    code, out, _ = run_cmd([SPACELINT_BIN, "-C", 'indent=["error", 2]', "-"], input_data="\tlet x = 1;\n")
    assert code == 1
    assert "error" in out
    assert "indent" in out
    assert "Expected space indentation" in out

    # -C 'indent=["warn", "tabs"]'
    code, out, _ = run_cmd([SPACELINT_BIN, "-C", 'indent=["warn", "tabs"]', "-"], input_data="  let x = 1;\n")
    assert code == 0
    assert "warning" in out
    assert "indent" in out
    assert "Expected tab indentation" in out

    # Other rules with JSON syntax
    code, out, _ = run_cmd([SPACELINT_BIN, "-C", 'no-plusplus=["error", {"allowForLoopAfterthoughts": true}]', "-"], input_data="let x = 1;\n")
    assert code == 0

    # 6. Configure plugin rules
    code, out, _ = run_cmd([SPACELINT_BIN, "--typescript-plugin", "-C", "typescript/no-explicit-any=error", "-"], input_data="let x = 1;\n")
    assert code == 0

    # 7. Turn off all correctness rules, but explicitly enable no-trailing-spaces as error
    code, out, _ = run_cmd([SPACELINT_BIN, "-A", "correctness", "-D", "no-trailing-spaces", "-"], input_data="let x = 1; \r\n")
    assert code == 1
    assert "no-trailing-spaces" in out
    assert "no-carriage-return" not in out

    # 8. Turn off everything, then enable only specific rules
    code, out, _ = run_cmd([SPACELINT_BIN, "-A", "all", "-D", "indent", "-C", "indent=2", "-"], input_data="let x = 1;   \r\n\tlet y = 2;\n")
    assert code == 1
    assert "no-trailing-spaces" not in out
    assert "no-carriage-return" not in out
    assert "indent" in out

    # 9. Configuration file via -c / --config
    config_data = {
        "categories": {
            "correctness": "off",
            "style": "warn"
        },
        "rules": {
            "no-trailing-spaces": "error",
            "indent": ["error", 2]
        }
    }
    with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as cf:
        json.dump(config_data, cf)
        cf_path = cf.name

    try:
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", cf_path, "-"], input_data="let x = 1; \r\n\tlet y = 2;\n")
        assert code == 1
        assert "no-trailing-spaces" in out
        assert "indent" in out
        # no-carriage-return was turned off via correctness: off
        assert "no-carriage-return" not in out
    finally:
        os.remove(cf_path)

    # 10. indent off via -C indent=off and -C indent=off.<ext>
    code, out, _ = run_cmd([SPACELINT_BIN, "-C", "indent=off", "-"], input_data="    let x = 1;\n")
    assert code == 0
    assert "indent" not in out

    with tempfile.NamedTemporaryFile("w+", suffix=".py", delete=False, newline="") as tf:
        tf.write("    let x = 1;\n")
        tf_name = tf.name
        tf.close()
    try:
        code, out, _ = run_cmd([SPACELINT_BIN, "-C", "indent=off.py", tf_name])
        assert code == 0
        assert "Finished" in out and "Found" not in out
    finally:
        os.remove(tf_name)

    print("  Rule options, categories, and JSON syntax tests passed!")

def test_config_overrides():
    print("Testing config overrides for different extensions and folders...")
    with tempfile.TemporaryDirectory() as td:
        # Create directory structure:
        #   src/app.ts (spaces indent, trailing spaces)
        #   src/legacy.js (tab indent)
        #   scripts/build.js (trailing spaces allowed in scripts)
        #   tests/app.test.ts (mixed spaces & tabs, denied in test)
        #   docs/guide.md (trailing spaces allowed)
        src_dir = os.path.join(td, "src")
        scripts_dir = os.path.join(td, "scripts")
        tests_dir = os.path.join(td, "tests")
        docs_dir = os.path.join(td, "docs")
        os.makedirs(src_dir, exist_ok=True)
        os.makedirs(scripts_dir, exist_ok=True)
        os.makedirs(tests_dir, exist_ok=True)
        os.makedirs(docs_dir, exist_ok=True)

        app_ts = os.path.join(src_dir, "app.ts")
        legacy_js = os.path.join(src_dir, "legacy.js")
        build_js = os.path.join(scripts_dir, "build.js")
        test_ts = os.path.join(tests_dir, "app.test.ts")
        guide_md = os.path.join(docs_dir, "guide.md")

        # app.ts: space indented (2 spaces), trailing spaces
        with open(app_ts, "w") as f:
            f.write("  const a = 1; \n")

        # legacy.js: tab indented, no trailing spaces
        with open(legacy_js, "w") as f:
            f.write("\tconst b = 2;\n")

        # build.js: trailing spaces
        with open(build_js, "w") as f:
            f.write("const c = 3;  \n")

        # test.ts: mixed spaces and tabs
        with open(test_ts, "w") as f:
            f.write(" \tconst d = 4;\n")

        # guide.md: trailing spaces
        with open(guide_md, "w") as f:
            f.write("# Heading   \n")

        config = {
            "categories": {
                "correctness": "warn"
            },
            "rules": {
                "indent": ["warn", "tabs"]
            },
            "overrides": [
                {
                    "files": ["*.ts", "**/*.ts"],
                    "rules": {
                        "indent": ["error", 2]
                    }
                },
                {
                    "files": ["scripts/*"],
                    "rules": {
                        "no-trailing-spaces": "off"
                    }
                },
                {
                    "files": ["tests/**"],
                    "rules": {
                        "no-mixed-spaces-and-tabs": "error"
                    }
                },
                {
                    "files": ["docs/*.md"],
                    "categories": {
                        "correctness": "off"
                    }
                }
            ]
        }
        config_path = os.path.join(td, ".spacelintrc.json")
        with open(config_path, "w") as f:
            json.dump(config, f)

        # 1. Test app.ts:
        # *.ts override expects 2 spaces indentation (so 2 spaces is OK, not an indent warning)
        # trailing spaces should be reported
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", config_path, app_ts])
        assert code == 0
        assert "no-trailing-spaces" in out
        assert "indent" not in out, f"app.ts should match 2 space indent override, got:\n{out}"

        # 2. Test legacy.js:
        # Base config expects tabs, so tab indented file should have no warnings
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", config_path, legacy_js])
        assert code == 0
        assert "Finished" in out and "Found" not in out, f"legacy.js should have 0 warnings, got:\n{out}"

        # 3. Test scripts/build.js:
        # scripts/* overrides no-trailing-spaces to "off"
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", config_path, build_js])
        assert code == 0
        assert "Finished" in out and "Found" not in out, f"scripts/build.js should have no-trailing-spaces turned off, got:\n{out}"

        # 4. Test tests/app.test.ts:
        # tests/** overrides no-mixed-spaces-and-tabs to "error" -> exit code 1
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", config_path, test_ts])
        assert code == 1, f"tests/app.test.ts should fail with error exit code 1, got code={code}, out={out}"
        assert "no-mixed-spaces-and-tabs" in out
        assert "error" in out

        # 5. Test docs/guide.md:
        # docs/*.md overrides correctness category to "off"
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", config_path, guide_md])
        assert code == 0
        assert "Finished" in out and "Found" not in out, f"docs/guide.md should have correctness turned off, got:\n{out}"

        # 6. Test CLI flags interaction with config overrides (-D, -A, -W, -C)
        # If CLI specifies -D no-trailing-spaces, CLI takes precedence
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", config_path, "-D", "no-trailing-spaces", app_ts])
        assert code == 1, "CLI -D should elevate warning to error"
        assert "error" in out
        assert "no-trailing-spaces" in out

        # If CLI specifies -A no-trailing-spaces, it turns off the warning
        code, out, _ = run_cmd([SPACELINT_BIN, "-c", config_path, "-A", "no-trailing-spaces", app_ts])
        assert code == 0
        assert "Finished" in out and "Found" not in out

    print("  Config overrides tests passed!")

def test_format_options():
    print("Testing format options (-f agent, -f stylish, -f default, --format)...")
    sample_file = os.path.join(FIXTURES_DIR, "test.js")

    # 1. -f agent
    code, out, _ = run_cmd([SPACELINT_BIN, "-f", "agent", sample_file])
    assert code == 0, f"-f agent failed: code={code}"
    # Must not contain ANSI escape codes
    assert "\x1b[" not in out, f"-f agent should not contain ANSI colors, got: {repr(out)}"
    # Must match: <file>:<line>:<col>: warning spacelint(<rule>): <msg>
    assert f"{sample_file}:2:16: warning spacelint(no-trailing-spaces): Trailing whitespace found\n" == out
    # Must not contain summary
    assert "Found" not in out and "problem" not in out

    # Test agent with stdin
    code, out, _ = run_cmd([SPACELINT_BIN, "-f", "agent", "-"], input_data="var a = 1; \n")
    assert code == 0
    assert "\x1b[" not in out
    assert "<stdin>:1:11: warning spacelint(no-trailing-spaces): Trailing whitespace found\n" == out

    # Test agent with error severity
    code, out, _ = run_cmd([SPACELINT_BIN, "-f", "agent", "-D", "no-trailing-spaces", "-"], input_data="var a = 1; \n")
    assert code == 1
    assert "<stdin>:1:11: error spacelint(no-trailing-spaces): Trailing whitespace found\n" == out

    # Test --format=agent
    code, out, _ = run_cmd([SPACELINT_BIN, "--format=agent", sample_file])
    assert code == 0
    assert f"{sample_file}:2:16: warning spacelint(no-trailing-spaces): Trailing whitespace found\n" == out

    # 2. -f stylish
    code, out, _ = run_cmd([SPACELINT_BIN, "-f", "stylish", sample_file])
    assert code == 0, f"-f stylish failed: code={code}"
    # Verify file underline header
    assert f"\x1b[4m{sample_file}\x1b[0m" in out
    # Verify warning and rule
    assert "warning" in out and "spacelint(no-trailing-spaces)" in out
    # Verify stylish summary
    clean_out = strip_ansi(out)
    assert "✖ 1 problem (0 errors, 1 warning)" in clean_out

    # Test stylish with error severity
    code, out, _ = run_cmd([SPACELINT_BIN, "-f", "stylish", "-D", "no-trailing-spaces", sample_file])
    assert code == 1
    assert "error" in out
    assert "✖ 1 problem (1 error, 0 warnings)" in strip_ansi(out)

    # Test --format stylish
    code, out, _ = run_cmd([SPACELINT_BIN, "--format", "stylish", sample_file])
    assert code == 0
    assert "✖ 1 problem (0 errors, 1 warning)" in strip_ansi(out)

    # Test stylish with stdin
    code, out, _ = run_cmd([SPACELINT_BIN, "-f", "stylish", "-"], input_data="var a = 1; \n")
    assert code == 0
    assert "\x1b[4m<stdin>\x1b[0m" in out
    assert "✖ 1 problem (0 errors, 1 warning)" in strip_ansi(out)

    # 3. -f default
    code, out, _ = run_cmd([SPACELINT_BIN, "-f", "default", sample_file])
    assert code == 0, f"-f default failed: code={code}"
    # Bold blue file path in header
    assert f"\x1b[1m\x1b[34m{sample_file}\x1b[0m" in out
    # Magenta underline with horizontal dashes (─)
    assert "\x1b[35m" in out
    assert "───" in out
    # Default summary
    clean_out = strip_ansi(out)
    assert "Found 1 warning on 1 file" in clean_out

    # Test --format=default
    code, out, _ = run_cmd([SPACELINT_BIN, "--format=default", sample_file])
    assert code == 0
    assert "Found 1 warning on 1 file" in strip_ansi(out)

    print("  Format options tests passed!")

def test_files_and_timings_commands():
    print("Testing files and timings subcommands...")
    sample_file = os.path.join(FIXTURES_DIR, "test.js")

    # 1. files subcommand
    code, out, _ = run_cmd([SPACELINT_BIN, "files", sample_file])
    assert code == 0, f"files subcommand failed: code={code}"
    lines = [line.strip() for line in out.strip().split("\n") if line.strip()]
    assert len(lines) == 1
    assert lines[0] == sample_file

    # files subcommand with directory
    code, out, _ = run_cmd([SPACELINT_BIN, "files", FIXTURES_DIR])
    assert code == 0
    lines = [line.strip() for line in out.strip().split("\n") if line.strip()]
    assert len(lines) > 10
    assert any("test.ts" in line for line in lines)
    assert any("test.js" in line for line in lines)

    # 2. timings subcommand
    code, out, _ = run_cmd([SPACELINT_BIN, "timings", sample_file])
    assert code == 0, f"timings subcommand failed: code={code}"
    assert "Rule timings:" in out
    assert "no-trailing-spaces" in out
    assert "no-carriage-return" in out
    assert "no-mixed-spaces-and-tabs" in out
    assert "indent" in out
    assert "Time (ms)" in out
    assert "Relative" in out
    assert "Calls" in out
    assert "native" in out

    print("  files and timings subcommand tests passed!")

def test_limiters_max_warnings_and_problems():
    print("Testing --max-warnings and --max-problems limiters...")
    sample_file = os.path.join(FIXTURES_DIR, "test.js")

    # 1. --max-warnings
    # test.js has 1 warning (no-trailing-spaces).
    # If max-warnings=0, threshold is exceeded -> exit code 1
    code, out, _ = run_cmd([SPACELINT_BIN, "--max-warnings=0", sample_file])
    assert code == 1, f"--max-warnings=0 should return exit code 1, got {code}"
    assert "Exceeded maximum number of warnings. Found 1." in out
    assert "no-trailing-spaces" in out  # Diagnostics are unlimited

    # With space syntax: --max-warnings 0
    code, out, _ = run_cmd([SPACELINT_BIN, "--max-warnings", "0", sample_file])
    assert code == 1
    assert "Exceeded maximum number of warnings. Found 1." in out

    # If max-warnings=1, threshold is not exceeded (1 <= 1) -> exit code 0
    code, out, _ = run_cmd([SPACELINT_BIN, "--max-warnings=1", sample_file])
    assert code == 0
    assert "Exceeded maximum number of warnings" not in out
    assert "no-trailing-spaces" in out

    # 2. --max-problems
    # test.js has 1 warning, 0 errors -> total problems = 1.
    # If max-problems=0, threshold is exceeded -> exit code 1
    code, out, _ = run_cmd([SPACELINT_BIN, "--max-problems=0", sample_file])
    assert code == 1
    assert "no-trailing-spaces" in out  # Diagnostics are unlimited

    # With space syntax: --max-problems 0
    code, out, _ = run_cmd([SPACELINT_BIN, "--max-problems", "0", sample_file])
    assert code == 1

    # If max-problems=1, threshold is not exceeded (1 <= 1) -> exit code 0
    code, out, _ = run_cmd([SPACELINT_BIN, "--max-problems=1", sample_file])
    assert code == 0
    assert "no-trailing-spaces" in out

    # With denied rule: -D no-trailing-spaces produces 1 error, 0 warnings -> total problems = 1.
    # --max-problems=0 fails
    code, out, _ = run_cmd([SPACELINT_BIN, "-D", "no-trailing-spaces", "--max-problems=0", sample_file])
    assert code == 1

    print("  Limiters --max-warnings and --max-problems tests passed!")

def main():
    test_cli_flags()
    test_language_fixtures()
    test_obscure_edge_cases()
    test_piping_and_fix()
    test_indent_options_via_c()
    test_in_place_fix()
    test_rules()
    test_rule_options_and_categories()
    test_config_overrides()
    test_format_options()
    test_files_and_timings_commands()
    test_limiters_max_warnings_and_problems()
    print("\nALL SPACELINT TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
