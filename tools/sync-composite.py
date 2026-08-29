#!/usr/bin/env python3
"""Synchronize standalone quota-aware-runner assets from canonical Skills."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTO_SCRIPTS = ROOT / "skills" / "codex-auto-resume" / "scripts"
SOL_SKILL = ROOT / "skills" / "sol-luna-handoff"
COMPOSITE = ROOT / "skills" / "quota-aware-runner"
COMPOSITE_OWNED = {COMPOSITE / "scripts" / "install-agents.ps1"}


def is_source_file(path: Path) -> bool:
    return path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"


def mappings() -> dict[Path, Path]:
    result: dict[Path, Path] = {}
    for source in AUTO_SCRIPTS.rglob("*"):
        if is_source_file(source):
            result[source] = COMPOSITE / "scripts" / source.relative_to(AUTO_SCRIPTS)
    for source in (SOL_SKILL / "assets").rglob("*"):
        if is_source_file(source):
            result[source] = COMPOSITE / "assets" / source.relative_to(SOL_SKILL / "assets")
    return result


def generated_files() -> set[Path]:
    files: set[Path] = set()
    for directory in (COMPOSITE / "scripts", COMPOSITE / "assets"):
        if directory.exists():
            files.update(path for path in directory.rglob("*") if is_source_file(path))
    return files


def check(expected: dict[Path, Path]) -> list[str]:
    problems: list[str] = []
    destinations = set(expected.values())
    for source, destination in expected.items():
        if not destination.is_file():
            problems.append(f"missing: {destination.relative_to(ROOT)}")
        elif source.read_bytes() != destination.read_bytes():
            problems.append(f"stale: {destination.relative_to(ROOT)}")
    for unexpected in sorted(generated_files() - destinations - COMPOSITE_OWNED):
        problems.append(f"unexpected: {unexpected.relative_to(ROOT)}")
    nested = [path for path in generated_files() if path.name == "SKILL.md"]
    problems.extend(f"nested Skill metadata: {path.relative_to(ROOT)}" for path in nested)
    return problems


def synchronize(expected: dict[Path, Path]) -> None:
    destinations = set(expected.values())
    for unexpected in generated_files() - destinations - COMPOSITE_OWNED:
        unexpected.unlink()
    for source, destination in expected.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists() or source.read_bytes() != destination.read_bytes():
            temporary = destination.with_name(destination.name + ".tmp")
            shutil.copyfile(source, temporary)
            temporary.replace(destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report drift without writing")
    args = parser.parse_args()
    expected = mappings()
    if args.check:
        problems = check(expected)
        if problems:
            print("\n".join(problems), file=sys.stderr)
            return 1
        print(f"composite is synchronized ({len(expected)} files)")
        return 0
    synchronize(expected)
    problems = check(expected)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"synchronized {len(expected)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
