#!/usr/bin/env python3
"""Check that every behaviour-changing cvar is in the hack registry.

src/gta4_hack_registry.h lists every setting that makes the port behave
differently from the original game, so that safe mode (gta4_safe_mode) can
turn them back. A cvar defined in one of the registered categories below but
missing from the registry would silently escape safe mode, so the Android
build (os/android/scripts/build_native.sh) runs this check before compiling.

Also fails on registry entries that name no defined cvar, and on duplicates.

Rebuilt for this fork: the original script was never committed (the
repository's .gitignore ignores *.py unless listed). The categories are the
ones the registry covers completely at the time of writing.

usage: check_hack_registry.py            (exit status 0 = OK, 1 = problems)
"""
from collections import Counter
from pathlib import Path
import re
import sys

SDK = Path(__file__).resolve().parents[2]  # glue/rexglue-sdk-main
REGISTRY = SDK / "gta4-recomp" / "src" / "gta4_hack_registry.h"
SOURCES = [SDK / "gta4-recomp" / "src", SDK / "src"]

# Every cvar defined in these categories must have a registry entry.
REGISTERED_CATEGORIES = {
    "GTA IV/Graphics/Native Renderer",
    "GTA IV/Performance",
    "GTA IV/Streaming",
    "GTA IV/Population",
    "GTA IV/Stability",
}
# Cvars of those categories that are not hacks themselves.
EXEMPT = {
    "gta4_safe_mode",  # the switch that applies the registry
}

ENTRY = re.compile(r'\{\s*"([A-Za-z0-9_]+)"\s*,\s*Kind::')
# REXCVAR_DEFINE_<TYPE>(name, default, "category", ...); the default may be an
# expression with commas or strings, so match lazily up to the first string
# literal that is followed by another argument.
DEFINE = re.compile(r'REXCVAR_DEFINE_\w+\(\s*([A-Za-z0-9_]+)\s*,.*?,\s*"([^"]*)"\s*,', re.S)


def main() -> int:
    entries = ENTRY.findall(REGISTRY.read_text(encoding="utf-8"))
    registered = set(entries)

    defined: dict[str, tuple[str, Path]] = {}
    for root in SOURCES:
        for path in sorted(root.rglob("*.cpp")):
            text = path.read_text(encoding="utf-8", errors="replace")
            for name, category in DEFINE.findall(text):
                defined.setdefault(name, (category, path))

    problems = []
    for name, count in Counter(entries).items():
        if count > 1:
            problems.append(f"{name}: listed {count} times in the registry")
    for name in sorted(registered - defined.keys()):
        problems.append(f"{name}: in the registry but no such cvar is defined")
    for name, (category, path) in sorted(defined.items()):
        if category in REGISTERED_CATEGORIES and name not in registered and name not in EXEMPT:
            rel = path.relative_to(SDK)
            problems.append(f"{name} ({category}, {rel}): missing from {REGISTRY.name}")

    if problems:
        print("hack registry check failed:")
        for problem in problems:
            print("  " + problem)
        return 1
    print(f"hack registry OK: {len(registered)} entries, "
          f"{sum(1 for c, _ in defined.values() if c in REGISTERED_CATEGORIES)} cvars in "
          f"{len(REGISTERED_CATEGORIES)} registered categories")
    return 0


if __name__ == "__main__":
    sys.exit(main())
