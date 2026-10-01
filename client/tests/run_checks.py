"""Run Godot checks in an isolated save directory, then validate captured contracts."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4.x executable")
    parser.add_argument("--artifacts", type=Path, help="Optional fresh directory for logs and fixtures")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.artifacts:
        artifacts = args.artifacts.resolve()
        artifacts.mkdir(parents=True, exist_ok=False)
    else:
        artifacts = Path(tempfile.mkdtemp(prefix="do-zore-tests-"))
    save_dir = artifacts / "save"
    save_dir.mkdir()
    env = dict(os.environ)
    env["DO_ZORE_TEST_USER_DIR"] = str(save_dir)
    env["DO_ZORE_TEST_OUTPUT"] = str(artifacts / "contract-fixtures.json")

    def run(name: str, command: list[str]) -> None:
        process = subprocess.run(
            command, cwd=root, env=env, text=True, encoding="utf-8",
            errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=120,
        )
        (artifacts / f"{name}.log").write_text(process.stdout, encoding="utf-8")
        print(process.stdout, end="")
        if process.returncode or "SCRIPT ERROR:" in process.stdout or "Parse Error:" in process.stdout:
            raise RuntimeError(f"{name} failed (exit {process.returncode}); logs: {artifacts}")

    run("import", [args.godot, "--headless", "--path", str(root / "client"), "--editor", "--import"])
    run("godot", [args.godot, "--headless", "--path", str(root / "client"), "--script", "res://tests/headless_tests.gd"])
    run("backup", [args.godot, "--headless", "--path", str(root / "client"), "--script", "res://tests/backup_restore.gd"])
    run("contracts", [sys.executable, str(root / "client/tests/validate_contracts.py"), "--fixtures", env["DO_ZORE_TEST_OUTPUT"]])
    print(f"All checks passed. Isolated saves, logs and fixtures: {artifacts}")


if __name__ == "__main__":
    main()
