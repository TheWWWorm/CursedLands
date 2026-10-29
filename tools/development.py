#!/usr/bin/env python3
"""Portable private-project setup, checks and native build entry point."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".dev"
LOCK = ROOT / "manifests/development.json"


def execute(argv, **kwargs):
    print("+", subprocess.list2cmdline([str(x) for x in argv]), flush=True)
    return subprocess.run([str(x) for x in argv], check=True, cwd=kwargs.pop("cwd", ROOT),
                          env=kwargs.pop("env", {**os.environ, "PYTHONUTF8": "1"}), **kwargs)


def checksum(path, algorithm="sha256"):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def unpack_zip(archive, destination):
    """Reject traversal and link entries before extracting a downloaded ZIP."""
    destination = Path(destination).resolve()
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            target = (destination / entry.filename).resolve()
            if not target.is_relative_to(destination) or ((entry.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError("Unsafe archive entry: " + entry.filename)
        package.extractall(destination)


def fetch(url, target, expected, algorithm="sha256"):
    target = Path(target)
    if target.is_file() and checksum(target, algorithm) == expected:
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".download")
    try:
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        if checksum(temporary, algorithm) != expected:
            raise ValueError("Downloaded file does not match its pinned checksum: " + target.name)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    return target


def bootstrap():
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    platform = "windows" if sys.platform == "win32" else "linux" if sys.platform.startswith("linux") else None
    if platform is None:
        raise ValueError("This bootstrap currently supports Windows x64 and Linux x64")
    import platform as host
    if host.machine().lower() not in ("amd64", "x86_64"):
        raise ValueError("The pinned editor downloads are x64; use --godot for another architecture")
    spec = lock["godot"]["editors"][platform]
    destination = CACHE / "tools/godot"
    binary = destination / spec["executable"]
    receipt = destination / ".bootstrap.json"
    if receipt.is_file():
        saved = json.loads(receipt.read_text(encoding="utf-8"))
        if (saved["archive_sha512"] == spec["sha512"] and saved["files"]
                and all((destination / name).is_file() and checksum(destination / name) == digest
                        for name, digest in saved["files"].items())):
            execute([binary, "--version"])
            return binary
    archive = fetch(spec["url"], CACHE / "downloads" / spec["archive"], spec["sha512"], "sha512")
    unpack_zip(archive, destination)
    binary.chmod(binary.stat().st_mode | 0o111)
    receipt.write_text(json.dumps({"archive_sha512": spec["sha512"], "files": {
        p.relative_to(destination).as_posix(): checksum(p)
        for p in destination.rglob("*") if p.is_file() and p != receipt}}, indent=2) + "\n", encoding="utf-8")
    # Keep extraction reproducible but avoid retaining a duplicate 75-85 MB ZIP.
    archive.unlink()
    execute([binary, "--version"])
    return binary


def godot(explicit=None):
    if explicit:
        result = shutil.which(explicit)
        if not result:
            raise ValueError("Godot executable not found: " + explicit)
        return Path(result)
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    platform = "windows" if sys.platform == "win32" else "linux"
    cached = CACHE / "tools/godot" / lock["godot"]["editors"][platform]["executable"]
    if cached.is_file():
        return cached
    raise ValueError("Run bootstrap first, or pass --godot with your Godot executable")


def checkout(spec, destination):
    """Fetch a pinned upstream commit; never reset an existing checkout."""
    destination = Path(destination)
    if not destination.exists():
        destination.mkdir(parents=True)
        execute(["git", "init", "--quiet", destination])
        execute(["git", "-C", destination, "config", "core.autocrlf", "false"])
        execute(["git", "-C", destination, "remote", "add", "origin", spec["url"]])
        execute(["git", "-C", destination, "fetch", "--depth", "1", "origin", spec["commit"]])
        execute(["git", "-C", destination, "checkout", "--detach", "FETCH_HEAD"])
    actual = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
    if actual != spec["commit"]:
        raise ValueError("Dependency checkout has another revision; preserve it and choose a new directory")
    return destination


def native(args):
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    bindings = checkout(lock["godot_cpp"], CACHE / "deps/godot-cpp")
    sources = {"navigation": ("source", "terrain_search"), "archive": ("archive", "mod_archive"),
               "lua": ("mod_lua", "mod_lua")}
    folder, library = sources[args.component]
    build = CACHE / "build/native" / args.component
    cmd = ["cmake", "-S", ROOT / "game/src/native" / folder, "-B", build,
           "-DCMAKE_BUILD_TYPE=Release", "-DGODOTCPP_DIR=" + str(bindings)]
    if args.generator:
        cmd += ["-G", args.generator]
    execute(cmd)
    execute(["cmake", "--build", build, "--config", "Release", "--parallel", str(args.jobs)])
    filename = "lib" + library + (".dll" if sys.platform == "win32" else ".so")
    matches = list(build.rglob(filename))
    if len(matches) != 1:
        raise ValueError("Expected exactly one built " + filename)
    result = matches[0]
    if args.install:
        shutil.copy2(result, ROOT / "game/src/native/bin" / filename)
    receipt = {"component": args.component, "bindings": lock["godot_cpp"]["commit"],
               "library": str(result.relative_to(ROOT)), "sha256": checksum(result),
               "installed": args.install}
    (build / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))


def engine_source(args):
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    spec = lock["godot"]
    destination = Path(args.destination).resolve() if args.destination else CACHE / "deps" / ("godot-" + args.profile)
    checkout(spec, destination)
    stamp = destination / ".cl-patches.json"
    patches = lock["engine_profiles"][args.profile]
    expected = {"base": spec["commit"], "profile": args.profile,
                "patches": {name: checksum(ROOT / "engine_patches/godot-4.7" / name) for name in patches}}
    if stamp.exists():
        saved = json.loads(stamp.read_text(encoding="utf-8"))
        tree = subprocess.check_output(["git", "-C", str(destination), "write-tree"], text=True).strip()
        if saved != {**expected, "patched_tree": tree}:
            raise ValueError("Engine profile changed; preserve this tree and select a new --destination")
        execute(["git", "-C", destination, "diff", "--exit-code"], stdout=subprocess.DEVNULL)
        print("Existing engine patch profile verified:", destination)
        return
    dirty = subprocess.check_output(["git", "-C", str(destination), "status", "--porcelain"], text=True)
    if dirty:
        raise ValueError("Refusing to patch a modified engine tree; preserve it and select a new --destination")
    for name in patches:
        patch = ROOT / "engine_patches/godot-4.7" / name
        execute(["git", "-C", destination, "apply", "--index", "--check", patch])
        execute(["git", "-C", destination, "apply", "--index", patch])
    tree = subprocess.check_output(["git", "-C", str(destination), "write-tree"], text=True).strip()
    stamp.write_text(json.dumps({**expected, "patched_tree": tree}, indent=2) + "\n", encoding="utf-8")
    print("Prepared engine source:", destination)
    print("See docs/development/BUILD-ENGINE.md for compiler and SDK setup.")


def profile_environment(profile):
    profile = Path(profile).resolve()
    user = profile / "data/godot/app_userdata/Cursed Lands"
    user.mkdir(parents=True, exist_ok=True)
    settings = "[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\n"
    # This is a dedicated development profile, never the player's directory.
    (user / "settings.cfg").write_text(settings, encoding="utf-8")
    return {**os.environ, "PYTHONUTF8": "1", "XDG_DATA_HOME": str(profile / "data"),
            "XDG_CONFIG_HOME": str(profile / "config"), "XDG_CACHE_HOME": str(profile / "cache"),
            "APPDATA": str(profile / "data"), "LOCALAPPDATA": str(profile / "local")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Explicit engine path (otherwise use bootstrap's pinned editor)")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("bootstrap", help="Download and checksum the official Godot editor")
    sub.add_parser("doctor", help="Show source and tool availability")
    check = sub.add_parser("check", help="Run asset-free Python, localization and Godot parse checks")
    check.add_argument("--python-only", action="store_true")
    for action in ("run", "editor"):
        run = sub.add_parser(action)
        run.add_argument("--data", type=Path, help="Your own original game's installation directory")
        run.add_argument("--headless", action="store_true")
    build = sub.add_parser("native", help="Build a native helper using CMake and pinned bindings")
    build.add_argument("--component", choices=["navigation", "archive", "lua"], default="navigation")
    build.add_argument("--generator", help="CMake generator, such as Ninja or MinGW Makefiles")
    build.add_argument("--jobs", type=int, default=4)
    build.add_argument("--install", action="store_true", help="Replace this checkout's library after a successful build")
    engine = sub.add_parser("engine-source", help="Prepare pinned Godot source and its ordered patch stack")
    engine.add_argument("--profile", choices=["windows", "linux"], default="windows")
    engine.add_argument("--destination")
    args = parser.parse_args()
    if args.action == "bootstrap":
        bootstrap()
    elif args.action == "doctor":
        print("Project:", ROOT)
        print("Python:", sys.version.split()[0], sys.executable)
        for name in ("git", "cmake", "ninja", "scons", "gcc", "clang", "cl"):
            print(name + ":", shutil.which(name) or "not on PATH")
        print("Original game data is supplied separately; this command never reads player settings.")
    elif args.action == "native":
        if args.jobs < 1:
            parser.error("--jobs must be positive")
        native(args)
    elif args.action == "engine-source":
        engine_source(args)
    elif args.action == "check":
        for folder in ("tools/tests", "tools/parity"):
            execute([sys.executable, "-B", "-m", "unittest", "discover", "-s", folder, "-p", "test_*.py"])
        for script in ("check_translations.py", "check_issue_coverage.py"):
            execute([sys.executable, "-B", ROOT / "tools" / script])
        if not args.python_only:
            execute([sys.executable, "-B", ROOT / "tools/check_test_scripts.py", "--engine", godot(args.godot),
                     "--import-first", "--timeout", "1500"])
    else:
        engine = godot(args.godot)
        env = profile_environment(CACHE / "profiles" / args.action)
        argv = [engine, "--path", ROOT / "game", "--audio-driver", "Dummy", "--max-fps", "30"]
        if args.action == "editor":
            argv += ["--editor"]
        if args.headless:
            argv += ["--headless"]
        elif sys.platform.startswith("linux"):
            argv += ["--display-driver", "x11"]
        if args.data:
            argv += ["--", "--ei-path=" + str(args.data.resolve())]
        if sys.platform.startswith("linux") and not args.headless:
            lab = shutil.which("gpu-lab")
            if not lab:
                raise ValueError("Graphical Linux development runs use GPU Lab on this workstation")
            owned = ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"]
            argv = [lab, "run", "--gpu", "auto", "--cwd", ROOT, "--timeout", "3600", "--", "env"] + [
                key + "=" + env[key] for key in owned] + argv
        execute(argv, env=env)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Development command failed:", error, file=sys.stderr)
        sys.exit(1)
