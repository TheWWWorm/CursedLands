extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	var fx:=ParticleFx.new();add_child(fx);fx.set_process(false)
	for i in 32:
		var effect:=ParticleFx.Effect.new();effect.e=FxTypes.create(fx,[0x2001,0x2003,0x2004][i%3]);effect.e.rng.seed=6519+i
		effect.e.d0=12;effect.e.d8=200;effect.e.cc=100;fx.effects.append(effect)
	for tick in 40:fx._tick()
	check(fx.effects.all(func(effect):return not effect.e.parts.is_empty()),"fixture contains active fire and smoke")
	fx.hide();fx._draw(0.5)
	check(fx.effects.all(func(effect):return effect.mmi==null),"hidden boards allocate no particle draw resources")
	var start:=Time.get_ticks_usec()
	for frame in 1000:fx._draw(0.5)
	var hidden_us:=Time.get_ticks_usec()-start
	var before:int=fx.effects[0].e.rng.state
	fx._tick()
	check(fx.effects[0].e.rng.state!=before,"hidden effects keep advancing their random stream")
	fx.show();fx._draw(0.5)
	check(fx.drawn>0 and fx.effects.all(func(effect):return effect.mmi!=null),"revealed board draws current particles")
	for effect in fx.effects:
		var reference:=ParticleFx.Effect.new();reference.e=effect.e
		ParticleFx._fill_calc_script(reference,false,Vector3.ZERO,Vector3.ZERO,fx.tick)
		check(effect.buf.to_byte_array()==reference.buf.to_byte_array(),"revealed particle buffers preserve simulation")
	fx.hide();fx._draw(0.5)
	check(fx.drawn==0 and fx.effects.all(func(effect):return not effect.mmi.visible and effect.filled==-1),"leaving board hides existing resources and stops uploads")
	for effect in fx.effects:effect.e.parts.clear()
	fx.show();fx._draw(0.5)
	check(fx.drawn==0 and fx.effects.all(func(effect):return effect.mmi.multimesh.visible_instance_count==0),"empty emitters cannot show stale particles")
	print("PARTICLE_VISIBILITY ",checks," checks ",failures," failures; hidden_draw_1000_us=",hidden_us)
	get_tree().quit(1 if failures else 0)
