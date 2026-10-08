extends "user://original_city_gameplay.gd"
## Long entrance walk with live camera and normal commands, avoiding the
## straight route's known fight at y=90. No health/rules/population changes.
var _loop_move := 2000
var _route_index := 0
const ROUTE := [Vector2(255.67,58.75),Vector2(255.69,66.75),Vector2(255.67,58.75),Vector2(255.65,50.75)]

func _process(dt:float)->void:
	next_move=2147483647
	super._process(dt)
	if not recording:return
	var elapsed:=Time.get_ticks_msec()-started
	if elapsed<_loop_move:return
	_loop_move+=6000
	for i in controlled.size():
		var u:GameUnit=session.world.units.get(controlled[i])
		if u==null or u.dead:continue
		var target:Vector2=ROUTE[_route_index]+Vector2(1.5*i,0)
		game.issue({"t":"move","units":[u.uid],"x":target.x,"y":target.y,"run":true})
		commands.append({"wall_ms":elapsed,"uid":u.uid,"from":u.pos,"to":target,"route":"entrance loop"})
	_route_index=(_route_index+1)%ROUTE.size()
