#!/usr/bin/env python3
"""Run menu-driven online Trials and saved co-op on two persistent Linux clients.

Use an unpublished patched game export and a new output directory. Original
saves are only read; the game copies them into an isolated user-data profile.
This is automated play, not a physical-input latency measurement.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def flatten_external_scripts(source, destination):
    """Preserve virtual overrides and explicit super calls in a frozen script.

    Godot's external-script resolver rejects this three-level tool hierarchy.
    Flatten only test code, leaving the packaged Main, screens and sessions
    untouched. Keep original sources alongside it for provenance.
    """
    names = ['coop_traversal_session.gd', 'saved_coop_traversal.gd',
             'menu_coop_retention.gd']
    text = ''
    for level, name in enumerate(names):
        part = (source / name).read_text()
        shutil.copy2(source / name, destination / (name + '.source'))
        if level == 0:
            text = part
            continue
        inherited = set(re.findall(r'^func (\w+)\(', text, re.M))
        overrides = set(re.findall(r'^func (\w+)\(', part, re.M))
        for method in inherited & overrides:
            replacement = f'_parent{level}_{method}'
            text = text.replace(f'func {method}(', f'func {replacement}(')
            part = part.replace(f'super.{method}(', f'{replacement}(')
        text += '\n' + part.split('\n', 1)[1]
    script = destination / 'menu_coop_retention.gd'
    script.write_text(text)
    return script


def process_sample(root_pid):
    rows = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = dict(line.split(':', 1) for line in (entry / 'status').read_text().splitlines() if ':' in line)
            rows[int(entry.name)] = {key: fields[key].strip() for key in
                                    ('PPid', 'VmRSS', 'VmHWM', 'RssAnon', 'Threads') if key in fields}
        except (OSError, ProcessLookupError):
            continue
    owned = {root_pid}
    for _ in range(5):
        owned.update(pid for pid, row in rows.items() if int(row['PPid']) in owned)
    return {pid: rows[pid] for pid in sorted(owned) if pid in rows}


def gpu_sample(pids):
    if not shutil.which('nvidia-smi'):
        return None
    try:
        result = subprocess.run(['nvidia-smi', '--query-compute-apps=pid,gpu_uuid,used_gpu_memory',
                                 '--format=csv,noheader,nounits'], text=True,
                                capture_output=True, timeout=10, check=False)
        rows = []
        for line in result.stdout.splitlines():
            fields = [field.strip() for field in line.split(',')]
            if len(fields) == 3 and fields[0].isdigit() and int(fields[0]) in pids:
                rows.append({'pid': int(fields[0]), 'gpu': fields[1], 'mib': float(fields[2])})
        return rows
    except (ValueError, OSError, subprocess.TimeoutExpired):
        return None


def stop_owned_children(profile, executable):
    # OS.create_process may detach its process group. Never kill by name.
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            matches = ('XDG_DATA_HOME=' + str(profile)).encode() in (entry / 'environ').read_bytes().split(b'\0')
            if matches and (entry / 'cmdline').read_bytes().split(b'\0')[0] == str(executable).encode():
                os.kill(int(entry.name), signal.SIGTERM)
        except (OSError, ProcessLookupError):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ['runtime', 'ei-path', 'host-save', 'guest-save', 'output']:
        parser.add_argument('--' + option, type=Path, required=True)
    parser.add_argument('--duration', type=int, default=1800, help='Campaign play time in real seconds, after the matches.')
    parser.add_argument('--cycles', type=int, default=3, help='Complete player matches, ending after both humans are eliminated or the tournament ends.')
    parser.add_argument('--owner-size', default='3840x2160')
    parser.add_argument('--guest-size', default='2560x1440')
    parser.add_argument('--owner-display', default=os.environ.get('DISPLAY', ':0'))
    parser.add_argument('--guest-display', default='')
    parser.add_argument('--guest-xauthority', type=Path)
    parser.add_argument('--owner-gpu', type=int, default=0)
    parser.add_argument('--guest-gpu', type=int, default=1)
    parser.add_argument('--stationary', action='store_true', help='Menu smoke check or quiet comparison; not a sustained-combat test.')
    parser.add_argument('--smoke-rounds', type=int, default=0, help='Only for menu smoke checks: leave each match after this many rounds. Zero plays complete matches.')
    parser.add_argument('--checkpoint', action='store_true', help='Rejoin the existing named guest in a post-run host checkpoint instead of bringing a separate hero.')
    parser.add_argument('--match-poses', type=Path, help='For a restart comparison: walk to the recorded final positions and restore both camera poses before measurement.')
    args = parser.parse_args()
    executable = args.runtime.resolve()
    inputs = [args.host_save.resolve(), args.guest_save.resolve()]
    for path in [executable, executable.with_suffix('.pck'), *inputs]:
        if not path.is_file():
            parser.error(f'Missing input: {path}')
    if args.match_poses and not args.match_poses.is_file():
        parser.error(f'Missing pose receipt: {args.match_poses}')
    for size in [args.owner_size, args.guest_size]:
        if not re.fullmatch(r'\d+x\d+', size):
            parser.error('Resolutions must use WIDTHxHEIGHT.')
        width, height = map(int, size.split('x'))
        if width < 640 or height < 480:
            parser.error('Both views must be at least 640x480.')
    if args.cycles < 0 or args.duration < 1 or args.smoke_rounds < 0:
        parser.error('Cycles and smoke rounds must be nonnegative; duration must be positive.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    frozen = output / 'source'
    frozen.mkdir()
    script = flatten_external_scripts(Path(__file__).resolve().parent, frozen)
    profile = output / 'profile'
    env = os.environ.copy()
    env.update(DISPLAY=args.owner_display, XDG_DATA_HOME=str(profile))
    label = output.name
    command = [str(executable), '--rendering-method', 'forward_plus', '--gpu-index', str(args.owner_gpu),
               '--', '--ei-path=' + str(args.ei_path.resolve()), '--tool=' + str(script),
               '--host-save=' + str(inputs[0]), '--guest-save=' + str(inputs[1]),
               '--duration=' + str(args.duration), '--label=' + label, '--menu-cycles=' + str(args.cycles),
               '--default-render-thread', '--real-audio', '--camera-cycle', '--change-locations',
               '--owner-size=' + args.owner_size, '--guest-size=' + args.guest_size,
               '--guest-gpu=' + str(args.guest_gpu)]
    if args.guest_display:
        command.append('--guest-display=' + args.guest_display)
    if args.guest_xauthority:
        command.append('--guest-xauthority=' + str(args.guest_xauthority.resolve()))
    if args.stationary:
        command.append('--stationary')
    if args.smoke_rounds:
        command.append('--menu-smoke-rounds=' + str(args.smoke_rounds))
    if args.checkpoint:
        command.append('--checkpoint')
    if args.match_poses:
        command.append('--match-poses=' + str(args.match_poses.resolve()))
    plan = {'command': command, 'inputs': {str(path): digest(path) for path in inputs},
            'engine_sha256': digest(executable), 'runtime_sha256': digest(executable.with_suffix('.pck')),
            'source_sha256': {path.name: digest(path) for path in frozen.iterdir()},
            'menu_driven': True, 'graphics': 'Ultra', 'speed': 2, 'duration': args.duration,
            'cycles': args.cycles, 'owner_size': args.owner_size, 'guest_size': args.guest_size,
            'stationary': args.stationary, 'smoke_rounds': args.smoke_rounds,
            'checkpoint': args.checkpoint,
            'match_poses_sha256': digest(args.match_poses) if args.match_poses else None}
    started = time.monotonic()
    with (output / 'run.log').open('w') as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        plan['pid'] = process.pid
        (output / 'plan.json').write_text(json.dumps(plan, indent=2))
        print(json.dumps({'pid': process.pid, 'output': str(output)}), flush=True)
        next_sample = 0.0
        try:
            while process.poll() is None:
                now = time.monotonic()
                if now - started > args.duration + 240 + args.cycles * 3600:
                    plan['timed_out'] = True
                    os.killpg(process.pid, signal.SIGTERM)
                    break
                if now >= next_sample:
                    next_sample = now + 30
                    processes = process_sample(process.pid)
                    with (output / 'processes.jsonl').open('a') as stream:
                        stream.write(json.dumps({'unix': time.time(), 'processes': processes,
                                                 'gpu': gpu_sample(processes)}) + '\n')
                time.sleep(1)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        except KeyboardInterrupt:
            plan['interrupted'] = True
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=15)
        finally:
            stop_owned_children(profile, executable)
    plan.update(exit_code=process.returncode, wall_seconds=time.monotonic()-started,
                inputs_unchanged=all(digest(Path(path)) == value for path, value in plan['inputs'].items()))
    (output / 'plan.json').write_text(json.dumps(plan, indent=2))
    print(json.dumps({key: plan[key] for key in ['exit_code', 'wall_seconds', 'inputs_unchanged']}))
    return process.returncode


if __name__ == '__main__':
    raise SystemExit(main())
