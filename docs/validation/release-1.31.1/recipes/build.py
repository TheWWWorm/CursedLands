from pathlib import Path
import ast,hashlib,io,json,os,re,shutil,struct,subprocess,sys,tarfile,zipfile,plistlib

from release_config import WORK as W, REPO as R, VERSION as V, PROTOCOL, GODOT, PREVIOUS_RELEASE, LINUX_TEMPLATE, LINUX_TEMPLATE_SHA256, assert_source, windows_template
SOURCE=assert_source()
TREE=subprocess.check_output(['git','rev-parse','HEAD:game'],cwd=R,text=True).strip()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def run(label,cmd,env):
    log=W/(label+'.log')
    with log.open('w') as f:p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,env=env,timeout=600)
    errors=[s for s in log.read_text().splitlines() if re.search(r'SCRIPT ERROR:|^ERROR:|Parse Error|Compile Error',s)]
    if p.returncode==0 and errors and '--import' in cmd and any('no resource loaders' in e for e in errors):
        log.rename(W/(label+'-bootstrap.log'))
        with log.open('w') as f: p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,env=env,timeout=600)
        errors=[s for s in log.read_text().splitlines() if re.search(r'SCRIPT ERROR:|^ERROR:|Parse Error|Compile Error',s)]
    assert p.returncode==0 and not errors,(label,p.returncode,errors[:15])
    print(label,'passed',flush=True)

def stage(name):
    dest=W/(name+'-stage');dest.mkdir(exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive',SOURCE+':game'],cwd=R))) as z:z.extractall(dest,filter='data')
    profile=W/(name+'-profile');(profile/'data/godot').mkdir(parents=True,exist_ok=True)
    user=profile/'data/godot/app_userdata/Cursed Lands';user.mkdir(parents=True,exist_ok=True)
    (user/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\n')
    templates=profile/'data/godot/export_templates'
    if not templates.exists(): templates.symlink_to(Path.home()/'.local/share/godot/export_templates',target_is_directory=True)
    env=dict(os.environ,**{f'XDG_{k}_HOME':str(profile/k.lower()) for k in ['DATA','CONFIG','CACHE']})
    return dest,env

from pack_audit import checked_pack_entries
def unpack(data,name):
    out={n.removeprefix('res://'):v for n,v in checked_pack_entries(name,data)}
    offset=struct.unpack_from('<Q',data,32)[0]+4
    for _ in out:
        n=struct.unpack_from('<I',data,offset)[0];offset+=4
        key=data[offset:offset+n].rstrip(b'\0').decode().removeprefix('res://');offset+=n
        assert hashlib.md5(out[key]).digest()==data[offset+16:offset+32],key
        offset+=36
    assert V.encode() in out['project.binary']
    for name in out:
        assert not re.search(r'(^|/)(tools|local|inspection|scratchpad|dev|debug)(/|$)|\.(sav|eisaves|eipack|mpr|mob|reg|bik|mmp|anm|fig|bon)$',name,re.I),name
    assert any(n.startswith('icons/wiki/') for n in out),'Missing wiki icons'
    return out

def scripts(entries):return {n:hashlib.sha256(v).hexdigest() for n,v in entries.items() if n.endswith('.gdc')}
def notices(out):
    for name in ['LICENSE.md','THIRD_PARTY_NOTICES.md','CHANGELOG.md','README.md']:
        shutil.copy2(R/name,out/name)
    shutil.copy2(R/'public/GODOT_LICENSES.txt',out/'GODOT_LICENSES.txt')
    shutil.copy2(R/'game/fonts/LICENSE.txt',out/'FONT_LICENSE.txt')
    for source in (R/'game/src/native').glob('*NOTICES.txt'):shutil.copy2(source,out/source.name)
    shutil.copytree(R/'licenses',out/'licenses')
    # Copy only committed documentation; unrelated working files never ship.
    for rel in subprocess.check_output(['git','ls-files','docs'],cwd=R,text=True).splitlines():
        parts=Path(rel).parts
        if any(p in ('validation','screenshots') or p.startswith('wiki') for p in parts[1:]): continue
        target=out/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/rel,target)
    shutil.copytree(R/'engine_patches',out/'engine_patches')
    (out/'RELEASE-NOTES.md').write_text((R/'docs/releases/1.31.1.md').read_text().replace('../../CHANGELOG.md','CHANGELOG.md').replace('../','docs/'))
    sys.path.insert(0,str(R/'tools'))
    from package_mod import package
    for name in ['expedition-xp','quest-focus','field-medicine','quick-recovery']:
        package(R/'examples/mods'/name,out/'mods'/f'{name}-1.0.0.eimod')
        shutil.copytree(R/'examples/mods'/name,out/'examples/mods'/name)
    (out/'tools').mkdir()
    shutil.copy2(R/'tools/package_mod.py',out/'tools/package_mod.py')

def desktop():
    windows_template()
    assert sha(LINUX_TEMPLATE)==LINUX_TEMPLATE_SHA256, 'Qualified Linux template hash changed'
    s,env=stage('desktop');run('desktop-import',[GODOT,'--headless','--path',str(s),'--editor','--import','--quit'],env)
    report={'version':V,'source_commit':SOURCE,'game_tree':TREE,'protocol':PROTOCOL,'platforms':{}}
    baseline=None
    for platform,preset,exe,ext in [('linux-x86_64','Linux','CursedLands.x86_64','so'),('windows-x86_64','Windows','CursedLands.exe','dll')]:
        out=W/('CursedLands-'+V+'-'+platform);out.mkdir()
        old=Path('/home/llm2x/Documents/EI/local/scratchpad/release-1.30.0-20261025/release')/('CursedLands-1.30.0-'+platform)
        core=[exe,'libterrain_search.'+ext,'libmod_archive.'+ext]
        for name in core[1:]: shutil.copy2(R/'game/src/native/bin'/name,out/name)
        native=LINUX_TEMPLATE if ext=='so' else windows_template()[0]
        assert native.is_file(), native
        presets=s/'export_presets.cfg';text=presets.read_text();parts=re.split(r'(?=\[preset\.\d+\]\n)',text)
        for i,part in enumerate(parts):
            if 'name="'+preset+'"' in part: parts[i]=part.replace('custom_template/release=""','custom_template/release='+json.dumps(str(native)))
        presets.write_text(''.join(parts))
        project=s/'project.godot';original_project=project.read_text()
        config=original_project.replace('[application]', '[application]\ngraphics_sdk/nrd=true\ngraphics_sdk/sharc=true\ngraphics_sdk/rtxdi=true')
        if ext=='dll': config=config.replace('boot_splash/image="res://assets/branding/splash.png"','boot_splash/image="res://assets/branding/splash-graphics.png"\ngraphics_sdk/amd=true\ngraphics_sdk/nvidia=true')
        project.write_text(config)
        run(platform+'-export',[GODOT,'--headless','--path',str(s),'--export-release',preset,str(out/exe)],env)
        project.write_text(original_project)
        if ext=='so':subprocess.run(['strip','--strip-unneeded',str(out/exe)],check=True)
        (out/'src/native/bin').mkdir(parents=True)
        shutil.copy2(R/f'game/src/native/bin/libmod_lua.{ext}',out/f'src/native/bin/libmod_lua.{ext}')
        core.append(f'src/native/bin/libmod_lua.{ext}')
        shutil.copy2(R/f'game/src/native/bin/libpath_nrd.{ext}',out/f'src/native/bin/libpath_nrd.{ext}')
        core.append(f'src/native/bin/libpath_nrd.{ext}')
        pack=out/'CursedLands.pck'
        entries=unpack(pack.read_bytes(),str(pack));compiled=scripts(entries)
        expected={str(p.relative_to(R/'game')).removesuffix('.gd')+'.gdc' for p in (R/'game/src').rglob('*.gd')}
        assert set(compiled)==expected
        if baseline is None:baseline=compiled
        else:assert baseline==compiled
        notices(out)
        nrd=out/'licenses/NVIDIA/NRD';nrd.mkdir(parents=True,exist_ok=True)
        shutil.copy2(R/'game/src/native/NATIVE_NRD_NOTICES.txt',nrd/'NATIVE_NRD_NOTICES.txt')
        for sdk_name in ['SHARC','RTXDI']:
            d=out/'licenses/NVIDIA'/sdk_name;d.mkdir(parents=True,exist_ok=True)
            shutil.copy2(R/'game/src/game/fx/shaders'/(sdk_name+'_NOTICES.txt'),d/(sdk_name+'_NOTICES.txt'))
        if ext=='so':shutil.copy2(old/'Play.sh',out/'Play.sh')
        else:
            shutil.copy2(R/'tools/windows/Play-Compatibility.cmd',out/'Play-Compatibility.cmd')
            shutil.copy2(R/'tools/windows/Play-Vulkan.cmd',out/'Play-Vulkan.cmd')
            for name in core:
                pe=subprocess.check_output(['objdump','-p',str(out/name)],text=True)
                assert 'pei-x86-64' in pe and not any(re.match(r'libgcc|libstdc\+\+|libwinpthread',dep,re.I) for dep in re.findall(r'DLL Name: ([^\n]+)',pe))
        if ext=='dll':
            import prepare_fsr_sdk
            sdk=Path('/home/llm2x/Documents/EI/local/scratchpad/dlss-framegen-20261020/fsr-sdk/source')
            prepare_fsr_sdk.prepare(sdk)
            prepare_fsr_sdk.prepare_agility(sdk,sdk.parent/('Microsoft.Direct3D.D3D12.'+prepare_fsr_sdk.AGILITY_VERSION+'.nupkg'))
            for name in prepare_fsr_sdk.DLLS:shutil.copy2(sdk/'Kits/FidelityFX/signedbin'/name,out/name)
            shutil.copytree(sdk/'agility',out,dirs_exist_ok=True)
            notice=out/'licenses/AMD-FidelityFX';notice.mkdir(parents=True,exist_ok=True)
            for name in ['license.md','3rdpartynotice.md']:shutil.copy2(sdk/('Kits/FidelityFX/docs/'+name if name=='license.md' else name),notice/name)
            from check_fsr_distribution import check_template,check_package
            manifest=json.loads((R/'engine_patches/godot-4.7/streamline-sdk.json').read_text())
            sdk_nvidia=Path('/home/llm2x/Documents/EI/local/scratchpad/pt-five-targets-20261024/sdk')
            for name,digest in manifest['files'].items():
                src=sdk_nvidia/name
                if not src.is_file(): src=Path('/home/llm2x/Documents/EI/local/runtime/toolchains/cursed-lands-rr-20261026/runtime')/Path(name).name
                assert sha(src)==digest, (name, str(src))
                dst=out/(Path(name).name if name.endswith('.dll') else 'licenses/NVIDIA/'+name)
                dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
            qualification=out/'qualification';(qualification/'tests').mkdir(parents=True)
            shutil.copy2(R/'tools/run_native_dlss_qualification.ps1',qualification/'run_native_dlss_qualification.ps1')
            shutil.copy2(R/'tools/tests/rtx_frame_generation.gd',qualification/'tests/rtx_frame_generation.gd')
            check_template(native,True);check_package(out,True)
        info={'version':V,'source_commit':SOURCE,'game_tree':TREE,'protocol':PROTOCOL,'platform':platform,'engine_patch_count':17 if ext=='so' else windows_template()[1]['patch_count'],'unchanged_qualified_engine':ext=='so','engine_source':('Godot 4.7 5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88; qualified Linux 1.25.0 template reused, 17 patches' if ext=='so' else windows_template()[1]['engine_source']),'compiled_scripts':len(compiled),'resource_count':len(entries),'files':{n:sha(out/n) for n in core+['CursedLands.pck']}}
        if ext=='dll': info['engine_build_provenance']=windows_template()[1]
        info.update(dlss=ext=='dll',dlss_ray_reconstruction=ext=='dll',nrd=True,nrd_directional=True,sharc=True,rtxdi=True,native_windows_qualified=False,nvidia_placement_approval='Existing approved graphics splash and branding retained from 1.30.0')
        info.update(formula_api=1,package_api=3,fsr_in_normal_settings=ext=='dll',engine_template_sha256=sha(native),files={str(p.relative_to(out)):sha(p) for p in sorted(out.rglob('*')) if p.is_file()})
        (out/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n');report['platforms'][platform]={'folder':str(out),'info':info}
    out=W/('CursedLands-'+V+'-macos-universal');out.mkdir()
    run('macos-export',[GODOT,'--headless','--path',str(s),'--export-release','macOS',str(out/'CursedLands.zip')],env)
    with zipfile.ZipFile(out/'CursedLands.zip') as z:
        assert z.testzip() is None
        n=next(n for n in z.namelist() if n.endswith('.pck'));assert scripts(unpack(z.read(n),n))==baseline
        plist=plistlib.loads(z.read(next(n for n in z.namelist() if n.endswith('Info.plist'))));assert plist['CFBundleShortVersionString']==V
        exe=next(n for n in z.namelist() if '/Contents/MacOS/' in n and not n.endswith('/'));assert z.read(exe)[:4] in [bytes.fromhex('cafebabe'),bytes.fromhex('cafebabf')]
        assert not any(n.endswith(('.so','.dll')) for n in z.namelist())
    notices(out)
    info={'version':V,'source_commit':SOURCE,'game_tree':TREE,'protocol':PROTOCOL,'platform':'macos-universal','unsigned':True,'target_os_runtime_tested':False,'compiled_scripts':len(baseline),'files':{'CursedLands.zip':sha(out/'CursedLands.zip')}}
    (out/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n');report['platforms']['macos-universal']={'folder':str(out),'info':info}
    (W/'compiled-scripts.json').write_text(json.dumps(baseline,indent=2)+'\n')
    (W/'build.json').write_text(json.dumps(report,indent=2)+'\n');print('Desktop packages audited',len(baseline),'scripts',flush=True)

def web():
    s,env=stage('web')
    old=W/'web-export-presets.cfg'
    shutil.copy2(old,s/'export_presets.cfg')
    local=W/'export_mobile.py';local.write_text((W/'export_mobile_template.py').read_text())
    out=W/'web/unsplit';out.mkdir(parents=True,exist_ok=True)
    run('web-export',['python3',str(local),'web','--project',str(s),'--output',str(out),'--release','--godot',GODOT],env)
    entries=unpack((out/'index.pck').read_bytes(),'index.pck');compiled=scripts(entries)
    for n in entries:assert not re.search(r'(^|/)native(/|$)|\.(so|dll|gdextension)$',n),n
    for name in ['LICENSE.md','THIRD_PARTY_NOTICES.md','licenses/LGPL-2.1.txt']:
        dest=out/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/name,dest)
    old=Path('/home/llm2x/Documents/EI/local/scratchpad/release-1.30.0-20261025/release/CursedLands-1.30.0-linux-x86_64')
    for name in ['GODOT_LICENSES.txt','FONT_LICENSE.txt']:shutil.copy2(old/name,out/name)
    info={'version':V,'source_tag':'v'+V,'source_commit':SOURCE,'game_tree':TREE,'protocol':PROTOCOL,'platform':'web','engine':'Godot 4.7.stable.official.5b4e0cb0f','threads':False,'extensions':False,'compiled_scripts':len(compiled),'resource_count':len(entries),'all_pck_resource_md5_valid':True,'original_game_data_bundled':False,'pck_sha256':sha(out/'index.pck'),'wasm_sha256':sha(out/'index.wasm')}
    (out/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n');(W/'web/compiled-scripts.json').write_text(json.dumps(compiled,indent=2)+'\n')
    (W/'web/build-audit.json').write_text(json.dumps(info,indent=2)+'\n')
    shutil.copytree(R/'public/wiki',out/'wiki')
    print('Web exported',len(compiled),'scripts; complete offline wiki retained',flush=True)

if __name__=='__main__':{'desktop':desktop,'web':web}[sys.argv[1]]()
