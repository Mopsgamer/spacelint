import os
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent
VERSION_FILE = ROOT_DIR / "VERSION"

if VERSION_FILE.exists():
    raise SystemExit("Remove the existing VERSION file before building.")

version = os.environ.get("SPACELINT_VERSION", "").strip()
if version and not version.startswith("v"):
    raise SystemExit("SPACELINT_VERSION must start with 'v'.")
if not version:
    version = subprocess.check_output(
        ["git", "describe", "--tags", "--always"],
        cwd=ROOT_DIR,
        text=True,
    ).strip()

if not version.startswith("v"):
    version = f"v0.0.0-{version}"

try:
    VERSION_FILE.write_text(f"{version}\n", encoding="ascii")
    subprocess.run(["goose", *sys.argv[1:]], cwd=ROOT_DIR, check=True)
finally:
    VERSION_FILE.unlink(missing_ok=True)
