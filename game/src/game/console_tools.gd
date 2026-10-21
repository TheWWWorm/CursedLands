class_name ConsoleTools
extends RefCounted
## Remake testing conveniences. ConsoleCommands performs the authority and
## lifecycle checks before dispatching here; no arbitrary script execution.
const NAMES := ["status","party","inspect","heal","god","teleport","zones","travel","time"]

static func words(text: String) -> PackedStringArray:
	var out:=PackedStringArray();var token:="";var quoted:=false;var escaped:=false;var started:=false
	for ch in text:
		if escaped:
			token+=ch;escaped=false;continue
		if quoted and ch=="\\":escaped=true;continue
		if ch=='"':quoted=not quoted;started=true;continue
		if ch in [" ","\t","\n","\r"] and not quoted:
			if started:out.append(token);token="";started=false
		else:token+=ch;started=true
	if quoted or escaped:return []
	if started:out.append(token)
	return out

static func targets(s: Session, name: String, selection: Array = []) -> Array[GameUnit]:
	var found:Array[GameUnit]=[]
	match name.to_lower():
		"party":found.assign(s.party_units(0))
		"hero":
			var party:=s.party_units(0)
			if not party.is_empty():found.append(party[0])
		"selected":
			for id in selection.slice(0,32):
				if not (id is int or id is float):continue
				var u:GameUnit=s.world.units.get(int(id))
				if u and u.controller==0 and not u in found:found.append(u)
		_:
			if name.is_valid_int():
				var u:GameUnit=s.world.units.get(int(name))
				if u:found.append(u)
			else:
				for u:GameUnit in s.world.unit_rows():
					if String(u.info.get("name","")).nocasecmp_to(name)==0:found.append(u)
	return found

static func describe(u: GameUnit) -> String:
	return RemakeText.t("%s [id %d]  HP %.1f/%.1f  Energy %.1f/%.1f  Position %.2f, %.2f") % [u.display_name,u.uid,u.hp,u.max_hp,u.mana,u.max_mana,u.pos.x,u.pos.y]

static func zone_rows(s: Session, query: String = "") -> Array[Dictionary]:
	var out:Array[Dictionary]=[]
	if not s or not s.campaign:return out
	for id:String in s.campaign.zones:
		var z:Dictionary=s.campaign.zone(id)
		if not z.has("mpr") or not s.zone_exists(id):continue
		var title:=s.zone_title(id)
		if not query.is_empty() and not (id+" "+title).to_lower().contains(query.to_lower()):continue
		out.append({"id":id,"title":title})
	out.sort_custom(func(a,b):return a.id.naturalnocasecmp_to(b.id)<0)
	return out

static func execute(s: Session, line: String, selection: Array = []) -> PackedStringArray:
	var args:=words(line)
	if args.is_empty():return [RemakeText.t("Invalid console command or arguments.")]
	var cmd:=args[0].to_lower();var out:=PackedStringArray()
	match cmd:
		"status":
			if args.size()!=1:return usage("status")
			out.append(RemakeText.t("Version %s | Campaign %s | Zone %s") % [str(ProjectSettings.get_setting("application/config/version","?")),GameData.campaign_id,s.zone_id])
			out.append(RemakeText.t("Scene time %.2f h | Simulation %.2f s | Units %d | Party %d") % [s.state.world_time,s.world.time,s.world.units.size(),s.party_units(0).size()])
			out.append(RemakeText.t("God mode: %s") % RemakeText.t("On" if int(s.state.god_modes.get(0,0))!=0 else "Off"))
			out.append(RemakeText.t("Campaign changes are executed by the host."))
		"party":
			if args.size()!=1:return usage("party")
			for u:GameUnit in s.party_units(0):out.append(describe(u))
		"inspect","heal":
			if args.size()>2:return usage(cmd+" [hero|selected|party|id|name]")
			var target:=args[1] if args.size()==2 else ("party" if cmd=="heal" else "selected")
			var units:=targets(s,target,selection)
			if units.is_empty():return [RemakeText.t("No matching unit: %s")%target]
			if cmd=="heal" and units.any(func(u):return u.dead):return [RemakeText.t("Heal affects living units. Choose a living target.")]
			for u:GameUnit in units:
				if cmd=="heal":
					u.restore_parts();u.heal(u.max_hp);u.mana=u.max_mana
				out.append(describe(u))
				if cmd=="inspect":
					out.append(RemakeText.t("Dead: %s | Blocked: %s | Movement speed %.2f | Route points %d") % [RemakeText.t("Yes" if u.dead else "No"),RemakeText.t("Yes" if u.blocked else "No"),u._move_speed,u.path.size()])
			if cmd=="heal":s.state.store_party_positions(s.world);s.sync_state()
		"god":
			if args.size()>2 or (args.size()==2 and args[1].to_lower() not in ["on","off"]):return usage("god [on|off]")
			if args.size()==2:
				if args[1].to_lower()=="on":s.state.god_modes[0]=1
				else:s.state.god_modes.erase(0)
				s.sync_state()
			out.append(RemakeText.t("God mode: %s") % RemakeText.t("On" if int(s.state.god_modes.get(0,0))!=0 else "Off"))
		"teleport":
			if args.size() not in [3,4] or not args[1].is_valid_float() or not args[2].is_valid_float():return usage("teleport x y [hero|selected|id|name]")
			var p:=Vector2(float(args[1]),float(args[2]))
			var bounds:=Vector2(s.world.nav.size)*NavGrid.CELL
			if not p.is_finite() or p.x<0 or p.y<0 or p.x>=bounds.x or p.y>=bounds.y:return [RemakeText.t("Coordinates are outside the current map.")]
			var units:=targets(s,args[3] if args.size()==4 else "hero",selection)
			if units.size()!=1 or units[0].dead:return [RemakeText.t("Choose exactly one living unit.")]
			var u:GameUnit=units[0]
			s.world.nav.untrack_unit(u)
			p=s.world.nav.nearest_walkable(p,3.0,u.move_class())
			var open:=s.world.nav.is_walkable(p,u.move_class())
			s.world.nav.track_unit(u)
			if not open:return [RemakeText.t("No walkable position near those coordinates.")]
			var inst:=ScriptVM.Instance.new();inst.locals.unit=u
			s.world.vm._eval([ScriptParser.N_CALL,"SetCPFast",[[ScriptParser.N_VAR,"unit"],[ScriptParser.N_NUM,p.x],[ScriptParser.N_NUM,p.y],[ScriptParser.N_NUM,0]]],inst)
			s.world.nav.track_unit(u);s.state.store_party_positions(s.world);s.sync_state()
			out.append(describe(u))
		"zones":
			if args.size()>2:return usage('zones ["filter"]')
			var rows:=zone_rows(s,args[1] if args.size()==2 else "")
			for row:Dictionary in rows.slice(0,80):out.append(row.title+" ["+row.id+"]")
			if rows.is_empty():out.append(RemakeText.t("No matches."))
			if rows.size()>80:out.append(RemakeText.t("Showing the first %d matches. Add a filter to narrow the list.")%80)
		"travel":
			if args.size() not in [2,3] or (args.size()==3 and (not args[2].is_valid_int() or int(args[2])<1 or int(args[2])>100)):return usage("travel zone [entrance]")
			var zone:=args[1].to_lower()
			if not s.campaign.zones.has(zone) or not s.campaign.zone(zone).has("mpr") or not s.zone_exists(zone):return [RemakeText.t("Unknown zone ")+zone]
			if not s.lmp.is_empty():return [RemakeText.t("This testing command requires a campaign.")]
			s.enter_zone.call_deferred(zone,int(args[2]) if args.size()==3 else 1,false)
			out.append(RemakeText.t("Travel requested: %s. Quest requirements are not completed.")%s.zone_title(zone))
		"time":
			if args.size()==1:return [RemakeText.t("Scene time: %.2f h")%s.state.world_time]
			if args.size() not in [2,3] or not args[1].is_valid_float() or (args.size()==3 and args[2].to_lower() not in ["run","freeze"]):return usage("time hour [run|freeze]")
			var hour:=float(args[1])
			if not is_finite(hour) or hour<0 or hour>=24:return usage("time 0..23.99 [run|freeze]")
			var method:="FixWorldTime" if args.size()==3 and args[2].to_lower()=="freeze" else "RunWorldTime"
			s.world.vm._eval([ScriptParser.N_CALL,method,[[ScriptParser.N_NUM,hour]]],ScriptVM.Instance.new());s.sync_state()
			out.append(RemakeText.t("Scene time: %.2f h")%s.state.world_time)
	return out

static func usage(syntax: String) -> PackedStringArray:
	return [RemakeText.t("Usage: %s")%syntax]
