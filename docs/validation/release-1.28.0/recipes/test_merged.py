from pathlib import Path
import concurrent.futures,json,os,subprocess,sys
W=Path(__file__).resolve().parent
LIA='/home/llm2x/Documents/EI/local/scratchpad/lia-official-patches-20261023/patched-game'
BASE='/home/llm2x/Documents/EI/inspection/extracted/app'
GROUPS={
 'cpu': [(x,'headless',BASE) for x in ['story_coop_captivity','prison_alarm_state','prison_alarm_late_join','prison_damage_state','prison_discovery_state','prison_progression_state','story_guard_escape','patrol_escape_alerts','script_parity_boundaries','save_actor_refs','spell_alert_encounter','object_activity','stamina_ack','ui_real_time','arena_flat_equipment','arena_item_tiers','arena_equipment_localization','arena_astral','arena_astral_online','raytrace_source_cache','path_trace_budget','ground_mark_animation']]+[(x,'headless',LIA) for x in ['zone7_entry_fx','story_coop_effects','story_coop_effects_net','story_coop_predicates','story_coop_predicates_net','story_coop_traps','story_coop_traps_net','script_clock_coop']],
 'tutorials': [('contextual_tutorials','opengl3',BASE),('esc_board_frames','opengl3',BASE)],
 'autochess': [(x,'opengl3',BASE) for x in ['arena_portrait_feedback_ui','arena_portrait_polish_ui','arena_commander_events_ui','arena_astral_ui','arena_astral_events_ui','arena_snow_edges']],
 'vulkan': [(x,'vulkan',BASE) for x in ['path_trace_upload_staging','path_trace_history_handoff','path_trace_nrd_device','path_trace_nrd_motion','path_trace_grass_receivers','shader_compilation_water']],
}
group=sys.argv[1]
def check(item):
 suite,renderer,data=item
 tag=group+'-'+suite
 cmd=[sys.executable,str(W/'run_packaged.py'),'single','--suite',suite,'--tag',tag,'--renderer',renderer]
 if suite.startswith('arena_astral'):cmd+=['--','--astral-path='+LIA]
 result=subprocess.run(cmd,cwd=W,env=dict(os.environ,EI_PATH=data),capture_output=True,text=True)
 print(result.stdout.strip(),flush=True)
 if result.stderr:print(result.stderr[-1600:],flush=True)
 return {'suite':suite,'tag':tag,'exit':result.returncode}
with concurrent.futures.ThreadPoolExecutor(max_workers=3 if group=='cpu' else 1) as pool:
 rows=list(pool.map(check,GROUPS[group]))
(W/(group+'-merged.json')).write_text(json.dumps(rows,indent=2)+'\n')
sys.exit(int(any(x['exit'] for x in rows)))
