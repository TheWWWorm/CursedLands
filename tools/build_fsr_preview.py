#!/usr/bin/env python3
"""Export a committed Windows FSR build, including optional formula mods. Does not publish or tag."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

import prepare_fsr_sdk
from check_fsr_distribution import check_source, check_template, check_package

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def build(args):
    include_nvidia = args.rtx_sdk is not None
    check_source(ROOT, include_nvidia=include_nvidia)
    check_template(args.windows_template, include_nvidia)
    prepare_fsr_sdk.prepare(args.fsr_sdk)
    if digest(args.fsr_sdk / "agility/x86_64/D3D12Core.dll") != prepare_fsr_sdk.AGILITY_CORE_SHA256:
        raise ValueError("DirectX Agility runtime checksum mismatch")
    commit = subprocess.check_output(["git", "rev-parse", args.ref], cwd=ROOT, text=True).strip()
    args.output.mkdir(parents=True, exist_ok=False)
    source = args.output / "source"
    source.mkdir()
    archive = args.output / "source.tar"
    with archive.open("wb") as stream:
        subprocess.run(["git", "archive", commit], cwd=ROOT, stdout=stream, check=True)
    with tarfile.open(archive) as stream:
        stream.extractall(source, filter="data")
    archive.unlink()
    check_source(source, archived=True, include_nvidia=include_nvidia)
    game = source / "game"
    project = game / "project.godot"
    version = re.search(r'^config/version="([^"]+)"', project.read_text(), re.M)[1]
    splash = "splash-graphics.png" if include_nvidia else "splash-fsr.png"
    flags = "\ngraphics_sdk/amd=true" + ("\ngraphics_sdk/nrd=true" if (game / "src/native/path_nrd.cfg").exists() else "") + ("\ngraphics_sdk/nvidia=true" if include_nvidia else "")
    project.write_text(project.read_text().replace(
        'boot_splash/image="res://assets/branding/splash.png"',
        'boot_splash/image="res://assets/branding/' + splash + '"' + flags))
    profile = args.output / "export-profile"
    user = profile / "data/godot/app_userdata/Cursed Lands"
    user.mkdir(parents=True)
    (user / "settings.cfg").write_text("[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\n")
    env = dict(os.environ, **{f"XDG_{key}_HOME": str(profile / key.lower()) for key in ("DATA", "CONFIG", "CACHE")})
    presets = game / "export_presets.cfg"
    parts = re.split(r"(?=\[preset\.\d+\]\n)", presets.read_text())
    for i, part in enumerate(parts):
        if 'name="Windows"' in part:
            parts[i] = part.replace('custom_template/release=""', 'custom_template/release=' + json.dumps(str(args.windows_template)))
    presets.write_text("".join(parts))

    def run(label, command, bootstrap=False):
        log = args.output / (label + ".log")
        for attempt in range(2 if bootstrap else 1):
            with log.open("w") as stream:
                result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=600)
            errors = re.findall(r"(?m)^(?:SCRIPT ERROR:|ERROR:).*$", log.read_text())
            if result.returncode == 0 and not errors:
                print(label, "passed", flush=True)
                return
            if not bootstrap or attempt or "no resource loaders" not in log.read_text():
                raise RuntimeError(f"{label} failed: inspect {log}")
            log.rename(args.output / (label + "-bootstrap.log"))

    run("import", [args.godot, "--headless", "--path", str(game), "--editor", "--import", "--quit"], True)
    out = args.output / f"CursedLands-{version}-windows-x86_64"
    out.mkdir()
    run("export", [args.godot, "--headless", "--path", str(game), "--export-release", "Windows", str(out / "CursedLands.exe")])
    for name in prepare_fsr_sdk.DLLS:
        shutil.copy2(args.fsr_sdk / "Kits/FidelityFX/signedbin" / name, out / name)
    notices = out / "licenses/AMD-FidelityFX"
    notices.mkdir(parents=True)
    shutil.copy2(args.fsr_sdk / "Kits/FidelityFX/docs/license.md", notices)
    shutil.copy2(args.fsr_sdk / "3rdpartynotice.md", notices)
    shutil.copytree(args.fsr_sdk / "agility", out, dirs_exist_ok=True)
    for name in ("LICENSE.md", "THIRD_PARTY_NOTICES.md", "CHANGELOG.md"):
        shutil.copy2(source / name, out)
    shutil.copytree(source / "licenses", out / "licenses", dirs_exist_ok=True)
    shutil.copytree(source / "engine_patches/godot-4.7", out / "engine_patches/godot-4.7")
    shutil.copy2(source / "public/GODOT_LICENSES.txt", out)
    shutil.copy2(game / "fonts/LICENSE.txt", out / "FONT_LICENSE.txt")
    for notice in (game / "src/native").glob("*NOTICES.txt"):
        shutil.copy2(notice, out)
    for launcher in (source / "tools/windows").glob("Play-*.cmd"):
        shutil.copy2(launcher, out)
    for relative in ("docs/integrations/fsr-experiment.md", "docs/integrations/nvidia-dlss.md",
                     "docs/integrations/path-tracing-nrd.md", "docs/branding/graphics-sdk-attribution.md",
                     "docs/branding/graphics-sdk-assets.json", f"docs/releases/{version}.md",
                     "docs/validation/fsr-only.md", "docs/validation/fsr-only.json"):
        if (source / relative).exists():
            target = out / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / relative, target)
    if (source / "docs/validation/fsr-only").exists():
        shutil.copytree(source / "docs/validation/fsr-only", out / "docs/validation/fsr-only")
    for record in (source / "docs/validation").glob(f"release-{version}*.json"):
        shutil.copy2(record, out / "docs/validation" / record.name)
    shutil.copy2(source / "docs/releases" / (version + ".md"), out / "RELEASE-NOTES.md")
    (out / "README.txt").write_text(
        "Cursed Lands — graphics options and formula mods\n\n"
        "EN: Run CursedLands.exe. Select Forward+ (Direct3D 12) under Options > Screen > Renderer, restart if needed, then choose Anti-aliasing, Upscale quality and Frame generation on Screen. SDK upscaling and frame generation start Off. Import the example mods through Mods and rules.\n"
        "RU: Запустите CursedLands.exe. Выберите Forward+ (Direct3D 12) в Настройки > Экран > Рендерер, при необходимости перезапустите игру, затем выберите Сглаживание, Качество масштабирования и Генерация кадров в разделе Экран. Масштабирование SDK и генерация кадров по умолчанию выключены. Импортируйте примеры модов через Моды и правила.\n"
        "DE: Starten Sie CursedLands.exe. Wählen Sie Forward+ (Direct3D 12) unter Optionen > Bildschirm > Renderer, starten Sie bei Bedarf neu und wählen Sie dann Kantenglättung, Skalierungsqualität und Frame-Generierung unter Bildschirm. SDK-Skalierung und Frame-Generierung sind zunächst aus. Importieren Sie die Beispiel-Mods über Mods und Regeln.\n\n"
        "docs/integrations/fsr-experiment.md\ndocs/mod-formulas.md\n"
        "Runtime / Библиотеки / Laufzeit: Microsoft Visual C++ v14 x64\n"
        "https://aka.ms/vc14/vc_redist.x64.exe\n", encoding="utf-8")
    if (game / "src/native/bin/libmod_lua.dll").exists():
        from package_mod import package
        native = out / "src/native/bin"
        native.mkdir(parents=True, exist_ok=True)
        shutil.copy2(game / "src/native/bin/libmod_lua.dll", native)
        if (game / "src/native/path_nrd.cfg").exists():
            shutil.copy2(game / "src/native/bin/libpath_nrd.dll", native)
            shutil.copy2(game / "src/native/NATIVE_NRD_NOTICES.txt", out)
            nrd_notices = out / "licenses/NVIDIA/NRD"
            nrd_notices.mkdir(parents=True, exist_ok=True)
            shutil.copy2(game / "src/native/NATIVE_NRD_NOTICES.txt", nrd_notices)
        for name in ("mods.md", "mod-formulas.md", "versioning.md"):
            shutil.copy2(source / "docs" / name, out / "docs" / name)
        for name in ("expedition-xp", "quest-focus", "field-medicine", "quick-recovery"):
            package(source / "examples/mods" / name, out / "mods" / (name + "-1.0.0.eimod"))
            shutil.copytree(source / "examples/mods" / name, out / "examples/mods" / name)
    if include_nvidia:
        import prepare_rtx_sdk
        manifest = json.loads((source / "engine_patches/godot-4.7/streamline-sdk.json").read_text())
        for name, expected in manifest["files"].items():
            src = args.rtx_sdk / name
            if not src.is_file() or digest(src) != expected:
                raise ValueError("NVIDIA SDK file does not match pinned manifest: " + name)
            dest = out / (Path(name).name if name.endswith(".dll") else "licenses/NVIDIA/" + name)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
    check_package(out, include_nvidia)
    info = {
        "version": version, "source_commit": commit, "platform": "windows-x86_64",
        "base_release": "v1.27.0", "godot_commit": "5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88",
        "engine_template_sha256": digest(args.windows_template), "protocol": 23,
        "fsr_sdk": prepare_fsr_sdk.VERSION,
        "dlss_sdk_included": include_nvidia, "nvidia_placement_approval": "pending; local review only" if include_nvidia else None,
        "fsr_in_normal_settings": True, "formula_api": 1, "package_api": 3,
        "fsr_manifest_sha256": digest(source / "engine_patches/godot-4.7/fsr-sdk.json"),
        "fsr_engine_patch_sha256": digest(source / "engine_patches/godot-4.7/experimental-fsr.patch"),
        "agility_sdk": prepare_fsr_sdk.AGILITY_VERSION,
        "native_windows_qualified": False, "fsr4_hardware_qualified": False,
        "files": {str(p.relative_to(out)): digest(p) for p in sorted(out.rglob("*")) if p.is_file()},
    }
    (out / "BUILD-INFO.json").write_text(json.dumps(info, indent=2) + "\n")
    print(out, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--windows-template", type=Path, required=True)
    parser.add_argument("--fsr-sdk", type=Path, required=True)
    parser.add_argument("--rtx-sdk", type=Path, help="Include the pinned NVIDIA SDK for a local combined preview")
    parser.add_argument("--godot", default="godot-4")
    parser.add_argument("--ref", default="HEAD")
    args = parser.parse_args()
    for key in ("output", "windows_template", "fsr_sdk"):
        setattr(args, key, getattr(args, key).resolve())
    if args.rtx_sdk: args.rtx_sdk = args.rtx_sdk.resolve()
    build(args)
