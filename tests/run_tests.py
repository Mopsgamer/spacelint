#!/usr/bin/env python3
import subprocess
import os
import sys
import tempfile
import shutil
import re

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

def test_indent_options():
    print("Testing --indent options (tabs, spaces, auto, auto.<ext>)...")
    # indent tabs
    code, out, _ = run_cmd([SPACELINT_BIN, "--indent", "tabs", "-"], input_data="    let x = 1;\n")
    assert "indent" in out and "Expected tab indentation" in out

    # indent spaces
    code, out, _ = run_cmd([SPACELINT_BIN, "--indent", "4", "-"], input_data="\tlet x = 1;\n")
    assert "indent" in out and "Expected space indentation" in out

    # auto
    with tempfile.NamedTemporaryFile("w+", suffix=".yaml", delete=False, newline="") as tf:
        tf.write("services:\n  app:\n    image: redis\n")
        tf_name = tf.name
        tf.close()

    try:
        code, out, _ = run_cmd([SPACELINT_BIN, "--indent", "auto", tf_name])
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
        code, out, _ = run_cmd([SPACELINT_BIN, "--indent", "auto.yml", tf_name])
        assert code == 0
        assert "Finished" in out and "Found" not in out
    finally:
        os.remove(tf_name)

    print("  Indent options tests passed!")

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

def main():
    test_cli_flags()
    test_language_fixtures()
    test_obscure_edge_cases()
    test_piping_and_fix()
    test_indent_options()
    test_in_place_fix()
    print("\nALL SPACELINT TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
