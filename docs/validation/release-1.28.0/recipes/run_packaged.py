from pathlib import Path
import os,sys,subprocess,re,json,time,shutil
W=Path(__file__).resolve().parent;R=W.parent/'repo'
BASE=os.environ.get('EI_PATH','/home/llm2x/Documents/EI/inspection/extracted/app')
LIB=Path('/home/llm2x/Documents/EI/local/scratchpad/zone-speed-retention-20261019/wine-tools/root/usr')
PREFIX=Path('/home/llm2x/Documents/EI/local/scratchpad/water-raytracing-20261021/dx12-quality/wine-check-profile-hardware')
SETTINGS='[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\nauto_graphics=0\ndisplay_mode=0\nresolution=1\nnet_directory=0\nnet_upnp=0\nnet_lan=0\nvsync=0\nfps_limit=1\nfsr_upscaling=0\nfsr_quality=1\nfsr_frame_generation=0\n'
REFRESH='ERROR: Parameter "monitors" is null.'
def virtual_refresh(lines,i):
    # GPU Lab's virtual screen has no active RandR monitor; allow only this exact X11 refresh-rate query diagnostic.
    return lines[i]==REFRESH and i+1<len(lines) and 'at: screen_get_refresh_rate (platform/linuxbsd/x11/' in lines[i+1]
def run(suite,tag,platform='linux',renderer='headless',extra=(),exe_override=None,profile_source=None):
    p=W/'checks'/tag;p.mkdir(parents=True,exist_ok=False)
    win=platform=='windows';folder=W/('CursedLands-1.28.0-'+('windows-x86_64' if win else 'linux-x86_64'))
    exe=Path(exe_override or folder/('CursedLands.exe' if win else 'CursedLands.x86_64'))
    env=dict(os.environ)
    if win:
        prefix=p/'prefix';shutil.copytree(PREFIX,prefix,symlinks=True)
        u=prefix/'drive_c/users/llm2x/AppData/Roaming/Godot/app_userdata/Cursed Lands'
        if u.exists():shutil.rmtree(u)
        system=prefix/'drive_c/windows/system32';shutil.copy2(LIB/'x86_64-w64-mingw32/lib/zlib1.dll',system/'zlib1.dll')
        env.update(WINEPREFIX=str(prefix),WINEARCH='win64',WINEDEBUG='-all',WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree,mshtml=;dinput8=d;winedbg.exe=d;d3d12,d3d12core,dxgi,d3d11,nvapi64=n',LD_LIBRARY_PATH=str(LIB/'lib/x86_64-linux-gnu'),DXVK_ENABLE_NVAPI='1',DXVK_LOG_LEVEL='warn',DXVK_NVAPI_LOG_LEVEL='warn',DXVK_LOG_PATH=str(p),VKD3D_DEBUG='warn',VKD3D_SHADER_CACHE_PATH=str(p))
        cmd=[str(LIB/'lib/wine/wine64'),str(exe)]
    else:
        u=p/'data/godot/app_userdata/Cursed Lands';cmd=[str(exe)]
        env.update({f'XDG_{k}_HOME':str(p/k.lower()) for k in ['DATA','CONFIG','CACHE']})
    u.mkdir(parents=True)
    if profile_source is not None:
        shutil.copytree(Path(profile_source),u,dirs_exist_ok=True)
    (u/'settings.cfg').write_text(SETTINGS)
    cmd+=['--render-thread','safe','--audio-driver','Dummy','--max-fps','30']
    if renderer=='headless':cmd+=['--headless']
    else:
        # Invoke rendered runs through GPU Lab auto; never select a physical GPU here.
        if not win: cmd+=['--display-driver','x11']
        cmd+=['--rendering-method','forward_plus' if renderer in ['d3d12','vulkan'] else 'gl_compatibility','--rendering-driver',renderer,'--windowed','--resolution','1280x720']
    def path(v):return ('Z:' if win else '')+str(v)
    fixture=p/'fixtures';fixture.mkdir()
    for source in (R/'tools/tests').glob('*.gd'):
        (fixture/source.name).write_text(source.read_text().replace('res://tools/tests/',path(fixture)+'/'))
    shutil.copytree(R/'tools/benchmarks',p/'benchmarks')
    cmd+=['--','--ei-path='+path(BASE),'--no-movies','--tool='+path(fixture/(suite+'.gd')),'--audit-out='+path(p),'--mod-tests','--examples='+path(folder/'mods')]
    cmd+=list(extra)
    start=time.monotonic()
    with (p/'run.log').open('w') as f:
        try:result=subprocess.run(cmd,env=env,cwd=p,stdout=f,stderr=subprocess.STDOUT,timeout=600);code=result.returncode
        except subprocess.TimeoutExpired:code=124
    lines=(p/'run.log').read_text(errors='replace').splitlines()
    row={'suite':suite,'platform':platform,'renderer':renderer,'exit':code,'seconds':round(time.monotonic()-start,2),'argv':cmd,'profile':{'confine_mouse':0,'show_fps':1,'volume_sfx':0,'volume_stream':0,'volume_voice':0},'summary':[x for x in lines if re.search(r'checks|failures|^FAIL |^PASS ',x)],'errors':[x for i,x in enumerate(lines) if re.search(r'SCRIPT ERROR|^ERROR:|Parse Error|Unhandled exception|Assertion.*failed|^FAIL |\b[1-9][0-9]* failures(?![=\w])',x) and not virtual_refresh(lines,i)],'allowed_diagnostics':[x for i,x in enumerate(lines) if virtual_refresh(lines,i)]}
    for src in u.iterdir():
        if src.suffix in ['.png','.json'] and src.is_file():shutil.copy2(src,p/src.name)
    if (u/'logs/godot.log').exists():shutil.copy2(u/'logs/godot.log',p/'godot.log')
    for report in p.glob('*.json'):
        try: data=json.loads(report.read_text())
        except (ValueError,OSError): continue
        if isinstance(data,dict) and data.get('failures'): row['errors'].append(report.name+': '+str(data['failures']))
    row['source_game_tree']=subprocess.check_output(['git','rev-parse','HEAD:game'],cwd=R,text=True).strip()
    row['fixture_sha256']=__import__('hashlib').sha256((fixture/(suite+'.gd')).read_bytes()).hexdigest()
    if profile_source is not None:
        seed=Path(profile_source)
        row['profile_seed']={'path':str(seed),'files':{str(f.relative_to(seed)):__import__('hashlib').sha256(f.read_bytes()).hexdigest() for f in sorted(seed.rglob('*')) if f.is_file()}}
    (p/'result.json').write_text(json.dumps(row,indent=2)+'\n')
    print(tag,code,len(row['errors']),'errors',[(x[:160]+'...') if len(x)>160 else x for x in row['summary'][-2:]],flush=True)
    return row
if __name__=='__main__':
    if sys.argv[1]=='single':
        import argparse
        parser=argparse.ArgumentParser()
        parser.add_argument('group');parser.add_argument('--suite',required=True);parser.add_argument('--tag',required=True)
        parser.add_argument('--platform',choices=['linux','windows'],default='linux');parser.add_argument('--renderer',choices=['headless','opengl3','vulkan','d3d12'],default='headless')
        parser.add_argument('--profile-source',type=Path)
        args,extra=parser.parse_known_args()
        row=run(args.suite,args.tag,args.platform,args.renderer,[x for x in extra if x!='--'],profile_source=args.profile_source)
        sys.exit(int(bool(row['exit'] or row['errors'])))
    group=sys.argv[1];results=[]
    if group=='linux':
        for suite in ['mod_formulas','mod_profiles','mod_texture_packages','mod_effects','xp_distribution','equipment_animation_continuity','issue_ui_controls','local_host_permissions','zone_speed_retention','coop_permissions']:
            results.append(run(suite,'linux-'+suite))
        pack=W/'CursedLands-1.28.0-linux-x86_64/mods/expedition-xp-1.0.0.eimod'
        results.append(run('mod_worker','linux-formula-worker',extra=['--formula','--package='+str(pack)]))
        for suite in ['mod_formula_ui','fsr_experiment','fsr_attribution']:
            results.append(run(suite,'linux-'+suite,renderer='opengl3'))
    elif group=='windows':
        for suite in ['mod_formulas','issue_ui_controls','equipment_animation_continuity']:
            results.append(run(suite,'windows-'+suite,'windows'))
        pack=W/'CursedLands-1.28.0-windows-x86_64/mods/expedition-xp-1.0.0.eimod'
        results.append(run('mod_worker','windows-formula-worker','windows',extra=['--formula','--package=Z:'+str(pack)]))
        for suite in ['fsr_render','fsr_campaign','fsr_attribution']:
            results.append(run(suite,'windows-'+suite,'windows','d3d12'))
        results.append(run('fsr_campaign','windows-fsr-formulas','windows','d3d12',['--formula-package=Z:'+str(pack)]))
        for lang in ['en','ru','de']:
            results.append(run('scaled_menu_arena_text','windows-arena-'+lang,'windows','opengl3',['--lang='+lang]))
    (W/(group+'-packaged.json')).write_text(json.dumps(results,indent=2)+'\n')
    sys.exit(int(any(x['exit'] or x['errors'] for x in results)))
