"""Reproduce the cave-only cliff supplement from pinned editor metadata.

Usage: python3 check_cave_cliff_metadata.py RENDERER_REPO CENSUS_JSON
The ordinary natural-transition catalog deliberately excludes dirt/swamp.
This verifies the extra corner identities used only by steep cliff mapping.
"""
import base64
import json
from pathlib import Path
import re
import subprocess
import sys

revision = "0092dc6e1d7c4aab3f74644a79e9bfca11ecf293"
source = subprocess.check_output(
    ["git", "-C", sys.argv[1], "show", revision + ":Source/terrain_tile_presets.h"], text=True
)
record = re.search(r'\{"Zone5_1", 192, "([^"]+)", "([^"]+)"\}', source)
assert record is not None
assert record[2] == "1=Stone / Dark gray;2=Stone / Greenish;3=Ground / Dirt;4=Grass / Swamp;5=Stone / Underwater;6=Water / Dark;"
raw = base64.b64decode(record[1])
census = json.loads(Path(sys.argv[2]).read_text())["zone5_1"]
mapping = {0: 0, 1: 31, 2: 36, 3: 254, 4: 253, 5: 0, 6: 0}
expected = {}
for row in census:
    assert (row["width"], row["height"], row["mips"]) == (512, 512, False)
    start = row["atlas"] * 256
    expected[row["sha256"]] = bytes(mapping[x] for x in raw[start:start + 256]).hex()
path = Path(__file__).resolve().parents[2] / "game/src/game/fx/terrain_cliff_tiles.gd"
natural_path = path.with_name("terrain_transition_tiles.gd")
names = json.loads(re.search(r"const FAMILIES := (\[.*\])", natural_path.read_text())[1])
assert names[31] == "stone / dark gray" and names[36] == "stone / greenish"
actual = dict(re.findall(r'"([0-9a-f]{64})": "([0-9a-f]+)"', path.read_text().split("const CAVE_CORNERS := {")[1].split("}", 1)[0]))
assert actual == expected
print(f"Reproduced {len(actual)} cave atlas corner tables; water/underwater remain unsupported")
