#!/usr/bin/env python3
"""Raise catalog `min_checks` thresholds from green runs.

A registered test whose `min_checks` is far below the number of checks it
really performs can skip most of its body and still pass. This reads retained
results (`results.json` from tools/check_regressions.py or `report.json` from
tools/parity/gameplay.py), keeps the highest passing check count per catalog
entry, and raises `min_checks` to 90% of it (never lowering it).

    python3 tools/raise_min_checks.py RESULTS...          # report only
    python3 tools/raise_min_checks.py --apply RESULTS...  # rewrite the catalog

Both runners read tools/parity/gameplay_catalog.json; a focused results row
names its entry by `catalog_id` (older results only by the short `focused` ID).
"""
import argparse
import json
import math
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[1]
CATALOG = REPO / "tools/parity/gameplay_catalog.json"
RATIO = 0.9


def green_counts(paths, rows):
    """Highest passing check count per catalog ID."""
    by_alias = {row["focused"]: row["id"] for row in rows if "focused" in row}
    green = {}
    for path in paths:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if "cases" in data:
            for row in data["cases"]:
                if row.get("passed") and row.get("result"):
                    key = row.get("catalog_id") or by_alias.get(row["id"], row["id"])
                    green[key] = max(green.get(key, 0), row["result"]["checks"])
        elif "tests" in data:
            for row in data["tests"]:
                if row.get("status") == "passed":
                    green[row["id"]] = max(green.get(row["id"], 0), row["checks"])
        else:
            raise ValueError(f"{path}: neither a focused results.json nor a catalog report.json")
    return green


def proposals(green, catalog):
    changes = []
    for row in catalog["tests"]:
        wanted = max(row["min_checks"], math.floor(green.get(row["id"], 0) * RATIO))
        if wanted > row["min_checks"]:
            changes.append((row["id"], row["min_checks"], wanted))
            row["min_checks"] = wanted
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("results", nargs="*", type=Path, help="results.json / report.json files")
    parser.add_argument("--apply", action="store_true", help="rewrite the catalog")
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    changes = proposals(green_counts(args.results, catalog["tests"]), catalog)
    for case, old, new in changes:
        print(f"{case:48} {old:6} -> {new}")
    print(f"{len(changes)} thresholds would rise" if not args.apply else f"{len(changes)} thresholds raised")
    if args.apply and changes:
        CATALOG.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
