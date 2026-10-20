extends "coop_progress_travel.gd"
## A returning co-op autosave can be newer than the selected host save.
## Only an unchanged acknowledged shared story may follow that checkpoint;
## independent solo progress and personal earnings retain their guards.
const Proof := preload("res://src/game/coop_checkpoint.gd")

func copy_state(st:CampaignState)->CampaignState:
	var out:=CampaignState.new()
	var data:=st.to_dict().duplicate(true)
	for key:String in data:
		if key!="version" and key in out:out.set(key,data[key])
	return out

func hello(st:CampaignState)->Dictionary:
	var data:=Proof.story(st).duplicate(true)
	data.hero=CoopProgress.main_hero(st).duplicate(true)
	data.purse=CoopProgress.main_bag(st).duplicate(true)
	data.checkpoints=Proof.receipts(st)
	data.seq={}
	for sid:String in st.coop.get("applied",{}):data.seq[sid]=st.coop.applied[sid].seq
	return data

func _ready()->void:
	var partial:=CoopProgress.fresh_state()
	var live_hero:=CoopProgress.main_hero(partial).duplicate(true);live_hero.unit_name="Network Alias"
	CoopProgress.merge(partial,{"hero":live_hero})
	check(CoopProgress.main_hero(partial).get("unit_name","Hero")=="Hero","partial package cannot replace the authored protagonist with a network alias")
	CoopProgress.main_hero(partial).unit_name="AuthoredRole"
	CoopProgress.merge(partial,{"hero":live_hero})
	check(CoopProgress.main_hero(partial).unit_name=="AuthoredRole","explicit authored identity survives a partial package")
	s=Session.new();s.online=true;s.state=CoopProgress.fresh_state()
	s.world=GameWorld.new();s.world.session=s;s.zone_id=s.state.current_zone
	s.campaign=CampaignMap.load_from(GameData.texts)
	s.coop=QuietProgress.new();s.coop.session=s
	s.state.heroes[1]=s.state.heroes[0].duplicate(true)
	s.state.visited[s.zone_id]=true
	s.state.zones[s.zone_id]={"fixture":"older shared world"}
	s.state.set_var(0,"shared_story",1.0)
	var e:=entry();e.sid="shared-fixture";e.seq=10
	e.vars={"shared_story":1.0};e.visited=s.state.visited.duplicate()
	s.coop.joiners={"guest":e}
	var origin:=CoopProgress.fresh_state()
	origin.visited=s.state.visited.duplicate()
	origin.set_var(0,"shared_story",1.0)
	var pkg:=s.coop.package(e);pkg.sid=e.sid;pkg.seq=e.seq
	CoopProgress.merge(origin,pkg)
	check(Proof.receipts(origin).has(e.sid),"a complete shared package records story provenance")
	var older_host:=s.state
	var older_entry:=e.duplicate(true)
	# Progress occurs after the host's disk save, before its final guest flush.
	s.state=copy_state(older_host)
	s.state.set_var(0,"shared_story",2.0)
	s.state.set_var(0,"q."+s.zone_id+".newly_finished",2.0)
	s.state.visited["later_shared_zone"]=true
	s.state.quest_items["later item"]=true
	e.credits.vars={"shared_story":2.0,"q."+s.zone_id+".newly_finished":2.0}
	e.credits.visited={"later_shared_zone":true}
	e.credits.quest_items={"later item":true}
	e.credits.zones={"later_shared_zone":{"fixture":"later shared world"}}
	pkg=s.coop.package(e);pkg.sid=e.sid;pkg.seq=11
	CoopProgress.merge(origin,pkg)
	check(Proof.receipts(origin).has(e.sid),"newer final package keeps its own valid receipt")
	CoopProgress.main_hero(origin).str=44.0;origin.money=777
	check(Proof.receipts(origin).has(e.sid),"personal training and wealth do not masquerade as story changes")
	var solo_world:=copy_state(origin)
	solo_world.zones[s.zone_id].fixture="independent solo kills and loot"
	check(Proof.receipts(solo_world).is_empty(),"independent solo world changes invalidate a receipt even without quest changes")
	s.state=older_host;e=older_entry;e.active=false
	s.coop.joiners={"guest":e}
	var data:=hello(origin)
	check(not s.coop._matches_checkpoint(data),"newer shared source differs from selected host checkpoint")
	check(Proof.eligible(e,data,s.state,s.zone_id),"unchanged shared source can resume its recorded host checkpoint")
	for kind:String in ["solo_story","solo_location","solo_item","solo_visit","solo_party","no_receipt","different_host"]:
		var changed:=data.duplicate(true)
		match kind:
			"solo_story":changed.vars.private_solo_progress=1.0
			"solo_location":changed.zone="other_zone"
			"solo_item":changed.quest_items.private_item=true
			"solo_visit":changed.visited.private_zone=true
			"solo_party":changed.party_context.current_party="OtherChapter"
			"no_receipt":changed.checkpoints={}
			"different_host":s.state.set_var(0,"different_host_progress",1.0)
		check(not Proof.eligible(e,changed,s.state,s.zone_id),kind+" cannot be adopted as a shared rollback")
		s.state.set_var(0,"different_host_progress",0.0)
	s.coop._pending[72]=data;s.coop.on_hello(72,1,"Guest")
	check(e.clean and e.present and e.in_sync,"ordinary hello retains full shared progression")
	check(s.state.heroes[1][0].str==44.0 and e.purse.money==777,"resuming keeps the guest's own advancement and purse")
	pkg=s.coop.package(e);pkg.sid=e.sid;pkg.seq=12
	check(pkg.replace_checkpoint,"rollback package explicitly replaces the shared story")
	for repeat in 2:
		var merged:=copy_state(origin)
		CoopProgress.merge(merged,pkg)
		check(merged.get_var(0,"shared_story")==1.0 and not merged.quest_items.has("later item") and not merged.zones.has("later_shared_zone"),"cumulative merge %d restores removals as well as values"%repeat)
		check(merged.money==777 and CoopProgress.main_hero(merged).str==44.0,"cumulative merge %d preserves personal data"%repeat)
		check(Proof.receipts(merged).has(e.sid),"merged rollback remains a resumable shared checkpoint")
	# A subsequent equal checkpoint rebases normally; its deltas must not
	# keep the destructive replacement flag from the previous source.
	CoopProgress.merge(origin,pkg)
	e.active=false;s.coop._pending[73]=hello(origin);s.coop.on_hello(73,1,"Guest")
	pkg=s.coop.package(e)
	check(not pkg.replace_checkpoint and e.credits.vars.is_empty(),"equal checkpoint clears replacement state before a new cumulative tally")
	s.world.free();s.coop.free();s.free()
	print("COOP_SHARED_CHECKPOINT ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
