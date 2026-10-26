"""Shared release identity. Historical inputs keep their original versions."""
from pathlib import Path
import hashlib, json, re, subprocess

WORK = Path(__file__).resolve().parent
REPO = (WORK.parent / 'repo').resolve()
VERSION = '1.31.0'
PREVIOUS_VERSION = '1.30.0'
RELEASE_DATE = '2026-10-26'
PROTOCOL = 23
ANDROID_VERSION_CODE = 65
ANDROID_APP_ID = 'org.cursedlands.engine'
ANDROID_CERT_SHA256 = '4024877c17f340055c383cacd4e0e9c4282349ad6ef48c3f576eb0a2477582d5'
PREVIOUS_RELEASE = Path('/home/llm2x/Documents/EI/local/scratchpad/release-1.30.0-20261025/release')
LINUX_TEMPLATE = Path('/home/llm2x/Documents/EI/local/scratchpad/release-1.25.0-20261023/engines/linux-rt-template.x86_64')
LINUX_TEMPLATE_SHA256 = '900844d32a705b811a2b940b26e813defcae21f3763687aeb9c8eb99c896ebfa'
ANDROID_TEMPLATE = Path('/home/llm2x/Documents/EI/local/scratchpad/release-1.25.0-20261023/release/android_release_startup.apk')
ANDROID_TEMPLATE_SHA256 = '42623535bffc8da53ae1167e4f604f221d61120a8c68774099c8d7fddd21f207'
PREVIOUS_WEB_ARCHIVE = PREVIOUS_RELEASE / 'assets/CursedLands-1.30.0-web.zip'
PREVIOUS_WEB_SHA256 = '99de28717faa14f3a6e70150ddf4a8745f2f417dcea398e889a0f03f127979ab'
VALIDATION_FILE = REPO / f'docs/validation/release-{VERSION}-{RELEASE_DATE}.json'
VALIDATION_DIR = REPO / f'docs/validation/release-{VERSION}'
GODOT = '/home/llm2x/.local/bin/godot-4'

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def windows_template():
    info = json.loads((WORK / 'windows-engine-template.json').read_text())
    assert info.get('build_complete') is True, 'Corrected Windows engine build is still pending'
    path = Path(info['path'])
    assert sha256(path) == info['sha256'], 'Windows template hash differs from its build record'
    assert Path(info['provenance_file']).is_file(), 'Missing corrected-engine provenance'
    return path, info

def assert_source():
    assert f'config/version="{VERSION}"' in (REPO/'game/project.godot').read_text()
    presets=(REPO/'game/export_presets.cfg').read_text()
    for key,value in [('file_version',VERSION+'.0'),('product_version',VERSION+'.0'),('short_version',VERSION),('version',VERSION)]:
        assert f'application/{key}="{value}"' in presets, key
    assert 'application/modify_resources=true' in presets
    net=(REPO/'game/src/game/net_status.gd').read_text()
    assert int(re.search(r'const PROTOCOL := (\d+)',net)[1]) == PROTOCOL
    assert (REPO/f'docs/releases/{VERSION}.md').is_file()
    assert not subprocess.check_output(['git','status','--porcelain','--','game'],cwd=REPO,text=True).strip(), 'Commit game metadata and source before export'
    return subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
