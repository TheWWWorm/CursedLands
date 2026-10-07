#!/usr/bin/env python3
"""Include the game's simulation plugin in a patched Godot Android template."""
from pathlib import Path
import argparse
import shutil
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('engine', type=Path, help='Godot 4.7 source checkout')
args = parser.parse_args()
root = args.engine.resolve() / 'platform/android/java/lib/src/main'
assert (root / 'java/org/godotengine/godot/GodotHeadlessRenderView.java').is_file(), 'Apply android-headless-service.patch first'
source = Path(__file__).resolve().parent / 'EISimulation.java'
target = root / 'java/org/cursedlands/simulation/EISimulation.java'
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source, target)

manifest = root / 'AndroidManifest.xml'
text = manifest.read_text()
application = ET.fromstring(text).find('application')
assert application is not None
android = '{http://schemas.android.com/apk/res/android}'
entries = {
    'org.godotengine.plugin.v2.EISimulation': ('meta-data', 'value', 'org.cursedlands.simulation.EISimulation'),
    'org.godotengine.godot.service.GodotService': ('service', 'process', ':simulation'),
}
additions = []
for name, (tag, key, value) in entries.items():
    matches = [node for node in application.findall(tag) if node.get(android + 'name') == name]
    assert len(matches) <= 1, 'Duplicate manifest entry: ' + name
    if matches:
        assert matches[0].get(android + key) == value, 'Conflicting manifest entry: ' + name
        if tag == 'service':
            assert matches[0].get(android + 'exported') == 'false', 'Service must be private'
    else:
        extra = ' android:exported="false"' if tag == 'service' else ''
        additions.append(f'\t\t<{tag} android:name="{name}" android:{key}="{value}"{extra} />')
if additions:
    assert text.count('</application>') == 1
    text = text.replace('</application>', '\n'.join(additions) + '\n\t</application>')
    manifest.write_text(text)
print('Installed EISimulation in', root)
