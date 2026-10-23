#!/usr/bin/env python3
"""Reproduce the roster check summary from native battle results."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent


def summarize(filename, families):
    rows = json.loads((ROOT / filename).read_text())
    result = {"fights": sum(row["trials"] for row in rows),
              "timeouts": sum(row["timeouts"] for row in rows), "families": {}}
    for family in families:
        result["families"][str(family)] = {}
        for rank in sorted({row["rank"] for row in rows}):
            sample = [row for row in rows if family in (row["a"], row["b"]) and row["rank"] == rank]
            if not sample:
                continue
            wins = sum(row["wins"] if row["a"] == family else row["trials"] - row["wins"] - row["draws"] for row in sample)
            draws = sum(row["draws"] for row in sample)
            trials = sum(row["trials"] for row in sample)
            result["families"][str(family)][str(rank + 1)] = {
                "wins": wins, "draws": draws, "trials": trials,
                "score_percent": round(100 * (wins + draws / 2) / trials, 2),
                "timeouts": sum(row["timeouts"] for row in sample),
            }
    return result


summary = {
    "base_commit": "5521491c6980669f1ed46ed18aa70a3af259cd40",
    "engine": "4.7.stable.official.5b4e0cb0f",
    "old_alliances_baseline": summarize("baseline-contexts.json", [6, 19, 22, 23, 27]),
    "old_alliances_candidate": summarize("candidate-contexts.json", [6, 19, 22, 23, 27]),
    "new_alliances_initial_recruits": summarize("new-contexts-initial.json", [28, 29]),
    "seer_control": summarize("seer-control-contexts.json", [29]),
    "seer_candidate": summarize("seer-candidate-contexts.json", [29]),
    "new_promotions": json.loads((ROOT / "new-promotions.json").read_text()),
}
(ROOT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
