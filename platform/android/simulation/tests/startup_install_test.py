#!/usr/bin/env python3
"""Check early-startup integration against clean and already customized templates."""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

source = Path(__file__).resolve().parents[1]
android = '{http://schemas.android.com/apk/res/android}'
with tempfile.TemporaryDirectory(prefix='cursedlands-startup-install-') as temporary:
    engine = Path(temporary)
    root = engine / 'platform/android/java/lib/src/main'
    header = root / 'java/org/godotengine/godot/GodotHeadlessRenderView.java'
    header.parent.mkdir(parents=True)
    header.touch()
    manifest = root / 'AndroidManifest.xml'
    manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application></application></manifest>')
    command = ['python3', str(source / 'install_into_engine.py'), str(engine)]
    subprocess.run(command, check=True, capture_output=True)
    first = manifest.read_bytes()
    app = ET.fromstring(first).find('application')
    assert app.get(android + 'name') == 'org.cursedlands.simulation.StartupApplication'
    assert app.find('service').get(android + 'process') == ':simulation'
    assert app.find('service').get(android + 'exported') == 'false'
    assert len(app.findall('provider')) == 0
    for name in ['StartupApplication.java', 'EarlyStartup.java', 'EISimulation.java']:
        assert (root / 'java/org/cursedlands/simulation' / name).read_bytes() == (source / name).read_bytes()
    subprocess.run(command, check=True, capture_output=True)
    assert manifest.read_bytes() == first
    custom = first.replace(b'org.cursedlands.simulation.StartupApplication', b'example.CustomApplication')
    manifest.write_bytes(custom)
    result = subprocess.run(command, capture_output=True)
    assert result.returncode != 0 and b'Conflicting Android Application class' in result.stderr
    assert manifest.read_bytes() == custom
print('Startup integration: 10 checks passed')
