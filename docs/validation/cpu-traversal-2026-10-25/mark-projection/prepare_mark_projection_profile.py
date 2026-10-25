from pathlib import Path
s=Path(__file__).resolve().parent
t=(s/'prepare_round4_profile.py').read_text()
t=t[:t.index('# Eligible mechanism census')]+t[t.index("(s/'round4-profile-methods.json')"):]
t=t.replace("dest=s/'round4-profile-game';out=s/'round4-profile'", "dest=s/'mark-projection-profile-game';out=s/'mark-projection-profile'")
t=t.replace("(dest/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))", "# Use the current integrated source without gameplay substitutions.")
t=t.replace('wrapped=[]', """extra['game/fx/vegetation_interaction.gd']=['update','contacts','advance','posed_bounds']
extra['game/direct_pose.gd']=['sample','restore_pose','_compose_pose','apply_pose']
extra['game/fx/ground_marks.gd']+=['_update','_place','_sole_vertices','_sole_geometry']
extra['game/fx/terrain_details.gd']=['surface_sample','grass_allowed','vegetation_allowed','_camera_focus','_update_motion','_stream','_finish_grass_jobs','_install_chunk','_update_submissions']
wrapped=[]""")
t=t.replace("round4-profile-methods.json", "mark-projection-profile-methods.json")
t=t.replace("round4-profile-export.log", "mark-projection-profile-export.log")
exec(compile(t,str(s/'prepare_actor_detail_profile.py'),'exec'))
