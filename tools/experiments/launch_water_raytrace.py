#!/usr/bin/env python3
"""Launch the local Linux water RT experiment with a separate, muted test profile."""
import argparse
import os
from pathlib import Path
import re
import subprocess


def set_values(text, section, values):
    """Edit only the requested scalar keys; preserve other Godot Variant values."""
    pattern = re.compile(r"(?ms)^\[" + re.escape(section) + r"\]\s*\n(.*?)(?=^\[|\Z)")
    match = pattern.search(text)
    body = match[1] if match else ""
    for key, value in values.items():
        key_pattern = re.compile(r"(?m)^" + re.escape(key) + r"\s*=.*$")
        line = f"{key}={value}"
        if key_pattern.search(body):
            body = key_pattern.sub(lambda _: line, body)
        else:
            body = body.rstrip() + "\n" + line + "\n"
    replacement = f"[{section}]\n{body.strip()}\n\n"
    return text[:match.start()] + replacement + text[match.end():] if match else text.rstrip() + "\n\n" + replacement


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path, help="Patched Linux template with its sibling PCK")
    parser.add_argument("--ei-path", required=True, type=Path, help="Original Evil Islands installation")
    parser.add_argument("--profile", type=Path, help="Isolated experiment directory; never point this at a player profile")
    args = parser.parse_args()
    engine = args.engine.resolve()
    if not engine.is_file() or not engine.with_suffix(".pck").is_file():
        parser.error("The patched engine and its sibling .pck must both exist.")
    profile = args.profile.resolve() if args.profile else engine.parent / "water-rt-profile"
    normal = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")).resolve()
    if profile == normal or normal in profile.parents:
        parser.error("Use a separate experiment directory outside the normal application-data directory.")
    marker = profile / ".water-rt-experiment"
    if profile.exists() and any(profile.iterdir()) and not marker.exists():
        parser.error("An existing nonempty profile must already belong to this experiment.")
    profile.mkdir(parents=True, exist_ok=True)
    marker.touch()
    settings = profile / "data/godot/app_userdata/Cursed Lands/settings.cfg"
    settings.parent.mkdir(parents=True, exist_ok=True)
    text = settings.read_text() if settings.exists() else "[remake]\ngfx=4\n"
    text = set_values(text, "options", {
        "confine_mouse": 0, "show_fps": 1, "volume_sfx": 0, "volume_stream": 0,
        "volume_voice": 0, "auto_graphics": 0, "graphics_preset": 0,
        "gfx_water": 1, "gfx_water_reflections": 3, "display_mode": 0,
        "net_directory": 0, "net_lan": 0, "net_upnp": 0,
    })
    text = set_values(text, "display", {"resolution": '"1280x720"'})
    settings.write_text(text)
    env = dict(os.environ)
    for name in ("DATA", "CONFIG", "CACHE"):
        env[f"XDG_{name}_HOME"] = str(profile / name.lower())
    command = [str(engine), "--render-thread", "safe", "--rendering-method", "forward_plus",
               "--rendering-driver", "vulkan", "--audio-driver", "Dummy", "--windowed",
               "--resolution", "1280x720", "--", "--ei-path=" + str(args.ei_path.resolve()), "--no-movies"]
    return subprocess.call(command, env=env, cwd=engine.parent)


if __name__ == "__main__":
    raise SystemExit(main())
