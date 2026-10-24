#!/usr/bin/env python3
"""Export a committed desktop mod preview with the optional formula library.

Pass the qualified Linux and Windows templates explicitly. Builds do not publish.
The output directory must be new; no existing release artifacts are replaced.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

from package_mod import package

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(args):
    commit = subprocess.check_output(["git", "rev-parse", args.ref], cwd=ROOT, text=True).strip()
    args.output.mkdir(parents=True, exist_ok=False)
    source = args.output / "source"
    source.mkdir()
    archive = subprocess.check_output(["git", "archive", commit], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
        stream.extractall(source, filter="data")
    game = source / "game"
    version = re.search(r'^config/version="([^"]+)"', (game / "project.godot").read_text(), re.M)[1]
    if "-" not in version:
        raise ValueError("This helper builds previews only")
    profile = args.output / "export-profile"
    user = profile / "data/godot/app_userdata/Cursed Lands"
    user.mkdir(parents=True)
    (user / "settings.cfg").write_text("[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\n")
    (profile / "data/godot/export_templates").symlink_to(Path.home() / ".local/share/godot/export_templates", target_is_directory=True)
    env = dict(os.environ, **{f"XDG_{key}_HOME": str(profile / key.lower()) for key in ("DATA", "CONFIG", "CACHE")})

    def run(label, command, bootstrap=False):
        log = args.output / (label + ".log")
        for attempt in range(2 if bootstrap else 1):
            with log.open("w") as out:
                result = subprocess.run(command, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=600)
            errors = re.findall(r"(?m)^(?:SCRIPT ERROR:|ERROR:).*$", log.read_text())
            if result.returncode == 0 and not errors:
                print(label, "passed", flush=True)
                return
            if not bootstrap or attempt or "no resource loaders" not in log.read_text():
                raise RuntimeError(f"{label} failed; inspect {log}: {errors[:5]}")
            log.rename(args.output / (label + "-bootstrap.log"))

    presets = game / "export_presets.cfg"
    text = presets.read_text()
    for name, template in [("Linux", args.linux_template), ("Windows", args.windows_template)]:
        parts = re.split(r"(?=\[preset\.\d+\]\n)", text)
        for index, part in enumerate(parts):
            if f'name="{name}"' in part:
                parts[index] = part.replace('custom_template/release=""', "custom_template/release=" + json.dumps(str(template)))
        text = "".join(parts)
    presets.write_text(text)
    run("import", [args.godot, "--headless", "--path", str(game), "--editor", "--import", "--quit"], True)
    reports = []
    for platform, preset, exe, extension in [
        ("linux-x86_64", "Linux", "CursedLands.x86_64", "so"),
        ("windows-x86_64", "Windows", "CursedLands.exe", "dll"),
    ]:
        out = args.output / f"CursedLands-{version}-{platform}"
        out.mkdir()
        run(platform, [args.godot, "--headless", "--path", str(game), "--export-release", preset, str(out / exe)])
        if platform.startswith("linux"):
            run("linux-strip", [args.strip_tool, "--strip-unneeded", str(out / exe)])
        native = out / "src/native/bin"
        native.mkdir(parents=True)
        shutil.copy2(game / f"src/native/bin/libmod_lua.{extension}", native)
        if (game / "src/native/path_nrd.cfg").exists():
            shutil.copy2(game / f"src/native/bin/libpath_nrd.{extension}", native)
            shutil.copy2(game / "src/native/NATIVE_NRD_NOTICES.txt", out)
        for name in ["LICENSE.md", "THIRD_PARTY_NOTICES.md", "README.md", "CHANGELOG.md"]:
            shutil.copy2(source / name, out)
        shutil.copytree(source / "licenses", out / "licenses")
        shutil.copytree(source / "docs", out / "docs", ignore=shutil.ignore_patterns("validation", "wiki*", "screenshots"))
        (out / "docs/validation").mkdir()
        for suffix in (".md", ".json"):
            shutil.copy2(source / f"docs/validation/mod-formulas-{version}{suffix}", out / "docs/validation")
        shutil.copytree(source / f"docs/validation/mod-formulas-{version}", out / f"docs/validation/mod-formulas-{version}")
        shutil.copy2(source / f"docs/releases/{version}.md", out / "RELEASE-NOTES.md")
        shutil.copy2(game / "fonts/LICENSE.txt", out / "FONT_LICENSE.txt")
        for notice in (game / "src/native").glob("*NOTICES.txt"):
            shutil.copy2(notice, out)
        # Godot's distributable notices are already part of this repository.
        godot_notices = source / "GODOT_LICENSES.txt"
        if godot_notices.exists():
            shutil.copy2(godot_notices, out)
        else:
            old = args.engine_notices
            if old is None:
                raise ValueError("--engine-notices is required when GODOT_LICENSES.txt is not in the source")
            shutil.copy2(old, out / "GODOT_LICENSES.txt")
        for name in ["expedition-xp", "quest-focus", "field-medicine", "quick-recovery"]:
            package(source / "examples/mods" / name, out / "mods" / f"{name}-1.0.0.eimod")
            shutil.copytree(source / "examples/mods" / name, out / "examples/mods" / name)
        (out / "tools").mkdir()
        shutil.copy2(source / "tools/package_mod.py", out / "tools/package_mod.py")
        if platform.startswith("windows"):
            for launcher in (source / "tools/windows").glob("Play-*.cmd"):
                shutil.copy2(launcher, out)
        else:
            (out / "Play.sh").write_text('#!/bin/sh\ncd -- "$(dirname -- "$0")" || exit 1\nexec ./CursedLands.x86_64 "$@"\n')
            (out / "Play.sh").chmod(0o755)
        info = {
            "version": version, "source_commit": commit, "platform": platform,
            "game_tree": subprocess.check_output(["git", "rev-parse", commit + ":game"], cwd=ROOT, text=True).strip(),
            "protocol": 23, "formula_api": 1, "package_api": 3,
            "qualified_engine_template_sha256": digest(args.linux_template if extension == "so" else args.windows_template),
            "linux_debug_symbols_removed": extension == "so",
            "files": {str(p.relative_to(out)): digest(p) for p in sorted(out.rglob("*")) if p.is_file()},
        }
        (out / "BUILD-INFO.json").write_text(json.dumps(info, indent=2) + "\n")
        reports.append(info)
    (args.output / "build.json").write_text(json.dumps(reports, indent=2) + "\n")
    print("Desktop previews built. Test these folders before distributing archives.", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--linux-template", type=Path, required=True)
    parser.add_argument("--windows-template", type=Path, required=True)
    parser.add_argument("--engine-notices", type=Path)
    parser.add_argument("--godot", default="godot-4")
    parser.add_argument("--strip-tool", default="strip")
    parser.add_argument("--ref", default="HEAD")
    args = parser.parse_args()
    for key in ("output", "linux_template", "windows_template", "engine_notices"):
        value = getattr(args, key)
        if value is not None:
            setattr(args, key, value.resolve())
    build(args)
