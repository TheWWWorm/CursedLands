#!/usr/bin/env python3
"""Run reproducible Trials policies through the game's real combat, without rendering.

Example: python3 tools/benchmarks/arena_balance.py --data /path/to/game --output /tmp/trials-balance
Each process owns isolated preferences and saves. Policy results are not human win rates.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import statistics
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--godot', default='godot-4')
    parser.add_argument('--seeds', type=int, default=8)
    parser.add_argument('--start', type=int, default=1900)
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--armor-formulas', nargs='+', type=int, choices=[0, 1], default=[1],
                        help='0: original absorption; 1: at least 20%% of each damage type gets through')
    args = parser.parse_args()
    if min(args.seeds, args.jobs) < 1:
        parser.error('seeds and jobs must be positive')
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    policies = ['balanced', 'beast', 'warrior', 'mage', 'reroll', 'levels']

    def run_case(case):
        armor, challenge, policy = case
        folder = output / f'armor{armor}-{challenge}-{policy}'
        env = os.environ.copy()
        for kind in ['data', 'config', 'cache']:
            path = folder / kind
            path.mkdir(parents=True, exist_ok=True)
            env[f'XDG_{kind.upper()}_HOME'] = str(path)
        cmd = [args.godot, '--path', str(repo / 'game'), '--headless', '--audio-driver', 'Dummy', '--',
               '--no-local-worker', f'--ei-path={args.data.resolve()}',
               f'--tool={repo / "tools/benchmarks/arena_alliance_runs.gd"}',
               f'--arena-policy={policy}', f'--arena-challenge={challenge}',
               f'--arena-armor-formula={armor}',
               f'--arena-seeds={args.seeds}', f'--arena-seed-start={args.start}']
        started = time.monotonic()
        with (folder / 'run.log').open('w') as log:
            result = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
        log = (folder / 'run.log').read_text()
        if result.returncode or any(marker in log for marker in ['SCRIPT ERROR:', '\nERROR:', '\nFAIL ']):
            raise RuntimeError(f'{challenge}/{policy} failed; see {folder / "run.log"}')
        artifact = folder / f'data/godot/app_userdata/Cursed Lands/alliance-runs-{policy}.json'
        data = json.loads(artifact.read_text())
        rows = data['results']
        if len(rows) != args.seeds:
            raise RuntimeError(f'Incomplete simulation: {folder}')
        by_wave = {}
        for row in rows:
            for wave in row['trace']:
                if wave['seconds'] > data['time_limit'] + 0.0551:
                    raise RuntimeError(f'Battle exceeded time limit: {folder}')
                counts = by_wave.setdefault(str(wave['wave']), {'fights': 0, 'wins': 0, 'timeouts': 0})
                counts['fights'] += 1
                counts['wins'] += wave['winner'] == 0
                counts['timeouts'] += wave['timed_out']
        durations = sorted(w['seconds'] for r in rows for w in r['trace'])
        summary = {'armor_formula': armor, 'time_limit': data['time_limit'],
                   'challenge': challenge, 'policy': policy, 'runs': len(rows),
                   'completed': sum(r['outcome'] == 'won' for r in rows),
                   'battles': sum(len(r['trace']) for r in rows),
                   'mean_wave': statistics.mean(r['wave'] for r in rows),
                   'timeouts': sum(w['timed_out'] for r in rows for w in r['trace']),
                   'mean_seconds': statistics.mean(durations),
                   'median_seconds': statistics.median(durations),
                   'p90_seconds': durations[int((len(durations) - 1) * 0.9)],
                   'by_wave': by_wave, 'elapsed_seconds': round(time.monotonic() - started, 2)}
        print(json.dumps(summary, ensure_ascii=False), flush=True)
        return summary

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = list(pool.map(run_case, [(a, c, p) for c in range(3) for p in policies for a in args.armor_formulas]))
    report = {'seed_start': args.start, 'seeds_per_case': args.seeds,
              'armor_formulas': args.armor_formulas,
              'battles': sum(r['battles'] for r in rows), 'runs': sum(r['runs'] for r in rows),
              'note': 'Deterministic shopping policies using native combat; not human player win rates.', 'cases': rows}
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Completed {report['battles']} battles across {report['runs']} expeditions.", flush=True)


if __name__ == '__main__':
    main()
