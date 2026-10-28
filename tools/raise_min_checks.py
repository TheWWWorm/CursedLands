#!/usr/bin/env python3
"""Raise registry `min_checks` thresholds from green runs.

A registered test whose `min_checks` is far below the number of checks it
really performs can skip most of its body and still pass. This reads retained
results (`results.json` from tools/check_regressions.py or `report.json` from
tools/parity/gameplay.py), keeps the highest passing check count per
registered case, and raises `min_checks` to 90% of it (never lowering it).

    python3 tools/raise_min_checks.py RESULTS...          # report only
    python3 tools/raise_min_checks.py --apply RESULTS...  # rewrite registries

Same-script registrations in both registries (same script, arguments,
campaign and display) are kept at one threshold; `tools/tests/test_registries.py`
fails when they drift.
"""
import argparse
import json
import math
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[1]
FOCUSED = REPO / "tools/regressions.json"
CATALOG = REPO / "tools/parity/gameplay_catalog.json"
RATIO = 0.9


def green_counts(paths):
    """Highest passing check count per case ID in each registry."""
    focused, catalog = {}, {}
    for path in paths:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if "cases" in data:
            for row in data["cases"]:
                if row.get("passed") and row.get("result"):
                    focused[row["id"]] = max(focused.get(row["id"], 0), row["result"]["checks"])
        elif "tests" in data:
            for row in data["tests"]:
                if row.get("status") == "passed":
                    catalog[row["id"]] = max(catalog.get(row["id"], 0), row["checks"])
        else:
            raise ValueError(f"{path}: neither a focused results.json nor a catalog report.json")
    return focused, catalog


def registration_key(row, campaign):
    return (row["script"], tuple(row.get("args", [])), campaign, row.get("mode", row.get("display", "headless")))


def proposals(focused_green, catalog_green):
    focused = json.loads(FOCUSED.read_text(encoding="utf-8"))
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    wanted = {}
    for row in focused["cases"]:
        key = registration_key(row, "cursed_lands" if row["data"] == "base" else "lost_in_astral")
        wanted[key] = max(wanted.get(key, 0), row["min_checks"], math.floor(focused_green.get(row["id"], 0) * RATIO))
    for row in catalog["tests"]:
        key = registration_key(row, row["campaign"])
        wanted[key] = max(wanted.get(key, 0), row["min_checks"], math.floor(catalog_green.get(row["id"], 0) * RATIO))
    changes = []
    for row in focused["cases"]:
        key = registration_key(row, "cursed_lands" if row["data"] == "base" else "lost_in_astral")
        if wanted[key] > row["min_checks"]:
            changes.append(("focused", row["id"], row["min_checks"], wanted[key]))
            row["min_checks"] = wanted[key]
    for row in catalog["tests"]:
        key = registration_key(row, row["campaign"])
        if wanted[key] > row["min_checks"]:
            changes.append(("catalog", row["id"], row["min_checks"], wanted[key]))
            row["min_checks"] = wanted[key]
    return focused, catalog, changes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("results", nargs="*", type=Path, help="results.json / report.json files")
    parser.add_argument("--apply", action="store_true", help="rewrite the registries")
    args = parser.parse_args()
    focused_green, catalog_green = green_counts(args.results)
    focused, catalog, changes = proposals(focused_green, catalog_green)
    for registry, case, old, new in changes:
        print(f"{registry:8} {case:40} {old:6} -> {new}")
    print(f"{len(changes)} thresholds would rise" if not args.apply else f"{len(changes)} thresholds raised")
    if args.apply and changes:
        FOCUSED.write_text(json.dumps(focused, indent=2) + "\n", encoding="utf-8")
        CATALOG.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
