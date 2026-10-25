from pathlib import Path
s=Path(__file__).resolve().parent
text=(s/'prepare_round4_profile.py').read_text()
text=text[:text.index('# Eligible mechanism census')]+'''\n(s/'dar-figure-profile-methods.json').write_text(json.dumps(wrapped,indent=2))
shutil.copy2(s/'runtime.x86_64',out/'runtime.x86_64');shutil.copytree(r/'game/src/native/bin',out/'src/native/bin',dirs_exist_ok=True)
with (s/'dar-figure-profile-export.log').open('w') as log:
 result=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(dest),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Dar figure profile export',result.returncode,flush=True);raise SystemExit(result.returncode)
'''
text=text.replace("dest=s/'round4-profile-game';out=s/'round4-profile'","dest=s/'dar-figure-profile-game';out=s/'dar-figure-profile'")
text=text.replace("(dest/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))",'# This source includes merged local main, without private gameplay patches.')
text=text.replace("'game/game.gd':['_update_cursor'","'game/game.gd':['pick_unit','_pick_unit','pick_hover','_update_cursor'")
text=text.replace("'game/unit.gd':['_step_sleeping_presentation'","'game/unit.gd':['screen_rects','_step_sleeping_presentation'")
exec(compile(text,str(s/'prepare_dar_figure_profile.py'),'exec'))
