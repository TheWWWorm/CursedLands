#!/usr/bin/env python3
"""Test a freshly built navigation library in an asset-free Godot project."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

import development as dev
sys.path.insert(0, str(dev.ROOT / "tools/parity"))
from process import run_program, diagnostic_in, parse_summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine")
    args = parser.parse_args()
    receipt = json.loads((dev.CACHE / "build/native/navigation/build-receipt.json").read_text())
    library = dev.ROOT / receipt["library"]
    if dev.checksum(library) != receipt["sha256"]:
        raise ValueError("Native library no longer matches its build receipt")
    engine = dev.godot(args.engine)
    with tempfile.TemporaryDirectory(prefix="native-identity-", dir=dev.CACHE) as directory:
        root = Path(directory)
        shutil.copy2(library, root / library.name)
        shutil.copy2(dev.ROOT / "tools/development/native_object_identity.gd", root / "probe.gd")
        (root / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Native identity regression"\n'
            '[threading]\nworker_pool/max_threads=4\n')
        platform = "windows.x86_64" if sys.platform == "win32" else "linux.x86_64"
        (root / "native.gdextension").write_text(
            '[configuration]\nentry_symbol="terrain_search_init"\ncompatibility_minimum="4.7"\n'
            '[libraries]\n' + platform + '="res://' + library.name + '"\n')
        env = dev.profile_environment(root / "profile")
        common = [str(engine), "--headless", "--render-thread", "safe", "--audio-driver", "Dummy", "--path", str(root)]
        # No imported resources: the probe explicitly loads the extension and
        # exercises its real runtime registration and object conversions.
        log = root / "probe.log"
        code, error = run_program(common + ["--script", str(root / "probe.gd")], log, env, 90)
        output = log.read_text(encoding="utf-8", errors="replace")
        print(output, end="")
        if code or error or diagnostic_in(output):
            raise RuntimeError(error or "Native identity probe failed with exit " + str(code))
        summary = parse_summary(output, "NATIVE_OBJECT_IDENTITY", 10)
        if summary["failures"]:
            raise RuntimeError("Native object identity regression failed")
        print(json.dumps({"native_sha256": receipt["sha256"], "summary": summary}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
