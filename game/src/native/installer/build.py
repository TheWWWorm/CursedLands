#!/usr/bin/env python3
"""Build the installer decoder (installer_lzma.c) for the exports.

  python3 game/src/native/installer/build.py [--zig ZIG] [--ndk NDK] [linux windows android]

Linux and Windows x86-64 are cross-compiled with Zig (zig cc), Android ARM64
with the Android NDK's clang (r29, as the other Android helpers). The
libraries go to game/src/native/bin/, named as installer_lzma.gdextension
expects. Platforms without them (macOS, Web) unpack with the GDScript decoder.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "installer_lzma.c"
BIN = HERE.parent / "bin"
# Paths of the build machine are kept out of the libraries.
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Wno-cast-function-type", "-fvisibility=hidden", "-shared",
         f"-ffile-prefix-map={HERE}=installer", "-g0", "-s"]


def zig_cc(zig, target, output, extra=()):
    cmd = [zig, "cc", "-target", target, *FLAGS, *extra, "-o", str(output), str(SOURCE)]
    print("  " + " ".join(cmd))
    subprocess.run(cmd, check=True)


def linux(zig, ndk):
    zig_cc(zig, "x86_64-linux-gnu.2.28", BIN / "libinstaller_lzma.so", ["-fPIC"])


def windows(zig, ndk):
    with tempfile.TemporaryDirectory() as tmp:
        dll = Path(tmp) / "installer_lzma.dll"
        zig_cc(zig, "x86_64-windows-gnu", dll)
        shutil.copy(dll, BIN / "libinstaller_lzma.dll")


ANDROID_API = 24


def android(zig, ndk):
    clang = Path(ndk) / f"toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android{ANDROID_API}-clang"
    # 16 KB pages: required by recent Android devices.
    cmd = [str(clang), *FLAGS, "-fPIC", "-Wl,-z,max-page-size=16384", "-o", str(BIN / "libinstaller_lzma_android.so"), str(SOURCE)]
    print("  " + " ".join(cmd))
    subprocess.run(cmd, check=True)


PLATFORMS = {"linux": linux, "windows": windows, "android": android}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zig", default=os.environ.get("ZIG", shutil.which("zig") or "zig"))
    parser.add_argument("--ndk", default=os.environ.get("ANDROID_NDK_ROOT", ""))
    parser.add_argument("platforms", nargs="*", default=list(PLATFORMS))
    args = parser.parse_args()
    BIN.mkdir(exist_ok=True)
    for name in args.platforms:
        if name == "android" and not Path(args.ndk, "toolchains").is_dir():
            print(f"Android NDK not found ({args.ndk or 'set --ndk or ANDROID_NDK_ROOT'})", file=sys.stderr)
            return 1
        if name != "android" and not shutil.which(args.zig):
            print(f"zig not found ({args.zig})", file=sys.stderr)
            return 1
        print(name)
        PLATFORMS[name](args.zig, args.ndk)
    for name in ("libinstaller_lzma.so", "libinstaller_lzma.dll", "libinstaller_lzma_android.so"):
        library = BIN / name
        if library.exists() and (str(HERE).encode() in library.read_bytes() or b"/home/" in library.read_bytes()):
            print(f"{name}: contains a local path", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
