extends "user://original_gameplay_versioned.gd"
## Original / 1x single-player coverage with fresh authored populations.
## Bounded entrance walks: commands, health, AI and encounters use normal rules.
## These routes exercise loaded large maps, not every view or combat encounter.

const AREAS := {
	"gz2h": {"units":323,"route":[Vector2(300.5,75),Vector2(308.5,75),Vector2(300.5,75),Vector2(308.5,75)]},
	"gz16g": {"units":294,"route":[Vector2(155,294.5),Vector2(155,286.5),Vector2(155,294.5),Vector2(155,302.5)]},
	"gz21k": {"units":207,"route":[Vector2(335.5,249.5),Vector2(335.5,241.5),Vector2(335.5,249.5),Vector2(335.5,257.5)]},
	"gz7g": {"units":262,"route":[Vector2(198,297.5),Vector2(190,297.5),Vector2(198,297.5),Vector2(206,297.5)]},
	"gz1h": {"units":415,"route":[Vector2(255.67,58.75),Vector2(255.69,66.75),Vector2(255.67,58.75),Vector2(255.65,50.75)]},
}
var _area_move := 2000
var _route_index := 0
var _logged_census := 0

func _fixture_matches()->bool:
	var saved_zone := String(cfg.save).get_file().get_basename()
	return session.zone_id==saved_zone and AREAS.has(saved_zone) and session.world.units.size()==int(AREAS[saved_zone].units)

func _process(dt:float)->void:
	next_move=2147483647
	super._process(dt)
	if not recording:return
	if census.size()!=_logged_census:
		_logged_census=census.size()
		var actors:=[]
		for uid in controlled:
			var u:GameUnit=session.world.units.get(uid)
			if u:actors.append({"uid":uid,"dead":u.dead,"hp":u.hp,"pos":u.pos,"action":u.action})
		census[-1]["controlled"]=actors
		census[-1]["units"]=session.world.units.size()
	var elapsed:=Time.get_ticks_msec()-started
	if elapsed<_area_move:return
	_area_move+=6000
	var route:Array=AREAS[session.zone_id].route
	for i in controlled.size():
		var u:GameUnit=session.world.units.get(controlled[i])
		if u==null or u.dead:continue
		var target:Vector2=route[_route_index]+Vector2(1.5*i,0)
		game.issue({"t":"move","units":[u.uid],"x":target.x,"y":target.y,"run":true})
		commands.append({"wall_ms":elapsed,"uid":u.uid,"from":u.pos,"to":target,"route":"authored entrance loop"})
	_route_index=(_route_index+1)%route.size()
