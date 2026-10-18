#!/usr/bin/env python3
"""Summarize native Trials fixtures, retaining inputs and targeted rerun provenance.

Pass context/star files in chronological order: a later identical fixture
replaces its earlier result. Never combine unrelated variants as extra trials.
Tournament samples describe purchasing policies, not human win rates or fun.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
from statistics import mean, median

POLICIES = ["economy", "expansion", "evolution", "tempo"]


def read(path):
    return json.loads(path.read_text())


def source(path):
    return {
        "run": path.parents[4].name if path.parent.name == "Cursed Lands" else path.stem,
        "file": path.name,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def merge(paths, fields):
    rows = {}
    for path in paths:
        for row in read(path):
            key = tuple(row[field] for field in fields)
            rows[key] = dict(row, evidence=source(path)["run"])
    return list(rows.values())


def contexts(rows):
    forms = defaultdict(Counter)
    reasons = Counter()
    durations = []
    for row in rows:
        assert len(row["trials"]) == 4, "Expected two seeds in both orientations"
        for trial in row["trials"]:
            reasons[trial["reason"]] += 1
            durations.append(trial["time"])
            for family in (row["a"], row["b"]):
                score = forms[(family, row["rank"], row["context"])]
                score["fights"] += 1
                score["wins"] += trial["winner"] == family
                score["draws"] += trial["winner"] == -1
    return {
        "fixtures": len(rows), "fights": len(durations), "reasons": dict(reasons),
        "mean_seconds": mean(durations), "median_seconds": median(durations),
        "forms": [dict(family=f, rank=r, context=c, **scores)
                  for (f, r, c), scores in sorted(forms.items())],
    }


def stars(rows):
    groups = defaultdict(Counter)
    for row in rows:
        group = groups[row["kind"]]
        for key in ("trials", "wins", "draws", "timeouts"):
            group[key] += row[key]
    return dict(groups)


def tournaments(games):
    policies = {}
    usage = Counter()
    distinct = []
    game_keys = set()
    for game in games:
        key = (game["seed"], game["strategy_offset"])
        assert key not in game_keys, "Duplicate tournament"
        game_keys.add(key)
        assert sorted(game["placements"]) == list(range(1, 10)), "Incomplete tournament"
    for policy, name in enumerate(POLICIES):
        places, seats = [], []
        for game in games:
            for seat, place in enumerate(game["placements"]):
                samples = [s for s in game["samples"] if s["seat"] == seat and s["strategy"] == policy]
                if samples:
                    places.append(place)
                    seats.append(samples)
                    final = samples[-1]
                    usage.update(set(zip(final["families"], final["stars"])))
                    distinct.append(len(set(final["families"])))
        spent = Counter()
        checkpoints = {}
        for samples in seats:
            for sample in samples:
                spent.update(sample.get("spending", {}))
        for number in (5, 10, 15, 20, 25):
            samples = [s for seat in seats for s in seat if s["round"] == number]
            if not samples:
                continue
            checkpoints[number] = {
                "alive": len(samples),
                **{k: mean(s[k] for s in samples) for k in ("capacity", "hp", "gold")},
                "three_star_units": mean(s["stars"].count(2) for s in samples),
            }
        policies[name] = {
            "seats": len(seats), "mean_place": mean(places), "median_place": median(places),
            "wins": places.count(1), "top_three": sum(p <= 3 for p in places),
            "average_spending": {k: v / len(seats) for k, v in spent.items()},
            "checkpoints": checkpoints,
        }
    return {
        "games": len(games), "seeds": sorted({g["seed"] for g in games}),
        "policies": policies, "mean_distinct_final_families": mean(distinct),
        "final_roster_presence": [dict(family=f, rank=r, teams=n)
                                  for (f, r), n in usage.most_common()],
    }


def expeditions(rows):
    return {
        "runs": len(rows), "clears": sum(r["outcome"] == "won" for r in rows),
        "mean_wave": mean(r["wave"] for r in rows),
        "policies": {
            name: [dict(seed=r["seed"], wave=r["wave"], outcome=r["outcome"])
                   for r in rows if r["strategy"] == i]
            for i, name in enumerate(POLICIES)
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("baseline", "contexts", "stars", "tournaments", "expeditions"):
        parser.add_argument("--" + key, type=Path, nargs="+", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = {"note": "Native deterministic fixtures; not human win rates or a measure of fun.", "inputs": {}}
    for key in ("baseline", "contexts", "stars", "tournaments", "expeditions"):
        paths = getattr(args, key)
        if not paths:
            continue
        summary["inputs"][key] = [source(p) for p in paths]
        if key in ("baseline", "contexts"):
            rows = merge(paths, ("rank", "a", "b", "context"))
            assert len(rows) == 468, "Expected all 90 forms in both contexts"
            result = contexts(rows)
        elif key == "stars":
            rows = merge(paths, ("kind", "family", "rank", "opponent", "opponent_rank", "copies"))
            assert len(rows) == 130, "Expected complete promotion and price fixtures"
            result = stars(rows)
        else:
            rows = [row for p in paths for row in read(p)]
            result = tournaments(rows) if key == "tournaments" else expeditions(rows)
        summary[key] = result
        (args.output / (key + ".json")).write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")) + "\n")
    (args.output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "inputs"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
