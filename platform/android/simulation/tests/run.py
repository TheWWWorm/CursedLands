#!/usr/bin/env python3
"""Run the bounded tombstone reader tests using the JDK on PATH."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='cursedlands-tombstone-') as classes:
    subprocess.run(['javac', '-d', classes, str(root.parent / 'NativeTombstone.java'),
                    str(root / 'NativeTombstoneTest.java')], check=True)
    subprocess.run(['java', '-cp', classes, 'org.cursedlands.simulation.NativeTombstoneTest'], check=True)
