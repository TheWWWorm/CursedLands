from pathlib import Path
s=Path(__file__).resolve().parent
t=(s/'prepare_round4_profile.py').read_text()
t=t[:t.index('# Eligible mechanism census')]+t[t.index("(s/'round4-profile-methods.json')"):]
t=t.replace("dest=s/'round4-profile-game';out=s/'round4-profile'", "dest=s/'actor-detail-profile-game';out=s/'actor-detail-profile'")
t=t.replace("(dest/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))", "# Use the current integrated source without gameplay substitutions.")
t=t.replace('wrapped=[]', """extra['game/direct_pose.gd']=['sample','restore_pose','_compose_pose','apply_pose']
extra['game/fx/ground_marks.gd']+=['_update','_place','_sole_vertices']
extra['game/fx/terrain_details.gd']=['_camera_focus','_update_motion','_stream','_finish_grass_jobs','_install_chunk','_update_submissions']
wrapped=[]""")
t=t.replace("round4-profile-methods.json", "actor-detail-profile-methods.json")
t=t.replace("round4-profile-export.log", "actor-detail-profile-export.log")
exec(compile(t,str(s/'prepare_actor_detail_profile.py'),'exec'))
