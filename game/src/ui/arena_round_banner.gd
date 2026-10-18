class_name ArenaRoundBanner
extends Control
## A brief herald's notice over the field; it never takes camera input.
var heading: Label
var detail: Label
var countdown: Label
var _key := ""
var _age := 0.0
var _kind := ""
var _ink := ArenaCreatureCard.GOLD

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(470,190)
	for item in ["heading","detail","countdown"]:
		var label := Label.new(); label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color",ArenaCreatureCard.PAPER)
		label.add_theme_color_override("font_outline_color",Color("111619")); label.add_theme_constant_override("outline_size",3)
		label.add_theme_font_size_override("font_size",42 if item=="heading" else 52 if item=="countdown" else 17)
		if item=="heading": label.add_theme_font_override("font",preload("res://fonts/LiberationSerif-Regular.ttf")); heading=label
		elif item=="detail": detail=label
		else: countdown=label
		add_child(label)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	heading.position=Vector2(16,6); heading.size=Vector2(size.x-32,60)
	detail.position=Vector2(16,80); detail.size=Vector2(size.x-32,102)
	countdown.position=Vector2(16,92); countdown.size=Vector2(size.x-32,74)
	queue_redraw()

func update_round(run: ArenaRun, dt: float, result_left: float, covered: bool) -> void:
	var key := "%d:%d:%s" % [run.run_seed,run.wave,run.stage]
	if key!=_key: _key=key; _age=0.0
	_age+=dt
	_kind=run.stage
	var preparing := run.stage=="prepare"
	var counting := preparing and run.preparation_left<=10.0
	var waiting := run.stage=="fight" and int(run.last_result.get("wave",-1))==run.wave
	var result := waiting or run.stage in ["result","won","lost"]
	visible=not covered and (counting or (preparing and _age<5.0) or (run.stage=="fight" and _age<2.0) or result)
	if not visible: return
	modulate.a=1.0
	if not result and not counting: modulate.a=clampf((5.0 if preparing else 2.0)-_age,0.0,1.0)
	countdown.visible=counting
	detail.visible=not counting
	if result:
		var winner := int(run.last_result.get("winner",-1))
		heading.text=RemakeText.t("Victory" if winner==0 else "Draw" if winner<0 else "Defeat")
		_ink=ArenaCreatureCard.GOLD if winner==0 else Color("ca7868")
		var loss := int(run.last_result.get("health_lost",0))
		detail.text=RemakeText.t("%d health lost") % loss if loss>0 else RemakeText.t("+%d gold") % int(run.last_result.get("gold",0))
		if waiting:
			detail.text=(RemakeText.t("%d health lost") % loss+"\n" if loss>0 else "")+RemakeText.t("Other battles")
		elif run.stage=="result": detail.text+="\n"+RemakeText.t("Next round in %ds") % ceili(result_left)
		elif run is ArenaTournamentRun: detail.text+="\n"+RemakeText.t("Place %d of %d") % [run.placements[0],ArenaTournamentRun.PLAYER_COUNT]
	else:
		_ink=ArenaCreatureCard.GOLD
		heading.text=run.round_title()
		if counting:
			countdown.text=str(ceili(run.preparation_left))
		elif run.stage=="fight": detail.text=RemakeText.t("Battle begins")
		else:
			var income: Dictionary=run.last_result.get("income",{})
			if income.is_empty(): detail.text=RemakeText.t("Recruit your company")
			else: detail.text=RemakeText.t("+%d base gold · +%d interest\n+%d victory · +%d streak\n%d total gold") % [income.base,income.interest,income.victory,income.streak,income.total]
	heading.add_theme_color_override("font_color",_ink)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	if detail.visible or countdown.visible:
		draw_rect(Rect2(32,76,w-64,108),Color(0.035,0.045,0.048,0.72))
	var points := PackedVector2Array([Vector2(16,0),Vector2(w-16,0),Vector2(w,34),Vector2(w-16,70),Vector2(16,70),Vector2(0,34)])
	draw_colored_polygon(points,Color(0.035,0.045,0.048,0.94))
	points.append(points[0]); draw_polyline(points,Color(_ink,0.8),1.5,true)
	draw_line(Vector2(38,4),Vector2(w-38,4),Color(_ink,0.25),1)
	draw_line(Vector2(38,66),Vector2(w-38,66),Color(_ink,0.25),1)
