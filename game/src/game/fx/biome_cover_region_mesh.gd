extends RefCounted
## Opaque local-space regional shapes; the existing cover builder supplies
## transforms, anchors, wind, pressure, LOD indices and native lighting.
const Regions = preload("res://src/game/fx/biome_cover_regions.gd")
const K = Regions.Kind


static func ring(angle: float, radius: float, y: float) -> Vector3:
	return Vector3(sin(angle)*radius,y,cos(angle)*radius)


static func cylinder(g: RefCounted, a: Vector3, b: Vector3, radius: float, colour: Color, sides := 5) -> void:
	var axis := (b-a).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.x)<0.8 else Vector3.UP).normalized()*radius
	var other := axis.cross(side)
	for i in sides:
		var p := side*cos(i*TAU/sides)+other*sin(i*TAU/sides)
		var q := side*cos((i+1)*TAU/sides)+other*sin((i+1)*TAU/sides)
		g.triangle(a+p,b+p,a+q,colour); g.triangle(a+q,b+p,b+q,colour)
		g.triangle(b,b+q,b+p,colour*1.05); g.triangle(a,a+p,a+q,colour*0.9)


static func ellipsoid(g: RefCounted, centre: Vector3, scale: Vector3, colour: Color) -> void:
	for y in 4:
		var a := y*PI/4.0; var b := (y+1)*PI/4.0
		for x in 6:
			var left := x*TAU/6.0; var right := (x+1)*TAU/6.0
			var p := centre+ring(left,sin(a),cos(a))*scale
			var q := centre+ring(right,sin(a),cos(a))*scale
			var r := centre+ring(left,sin(b),cos(b))*scale
			var s := centre+ring(right,sin(b),cos(b))*scale
			if y>0: g.triangle(p,q,r,colour)
			if y<3: g.triangle(q,s,r,colour)


static func patch(g: RefCounted, colour: Color) -> void:
	for i in 12:
		var a := i*TAU/12.0; var b := (i+1)*TAU/12.0
		var p := ring(a,0.42+0.06*sin(i*2.8+g.seed),0.005)
		var q := ring(b,0.42+0.06*sin((i+1)*2.8+g.seed),0.005)
		g.triangle(p,Vector3(0,0.025,0),q,colour*(0.94+0.06*sin(i)),Vector3(0,1,0))


static func slab(g: RefCounted, colour: Color, shard: bool, radius := 0.45) -> void:
	var sides := 5 if shard else 6
	var top := Vector3(0.02,0.30 if shard else 0.09,0.025)
	for i in sides:
		var a := ring(i*TAU/sides,radius*(0.85+0.1*sin(i*3.0+g.seed)),0)
		var b := ring((i+1)*TAU/sides,radius*(0.85+0.1*sin((i+1)*3.0+g.seed)),0)
		g.triangle(a,top,b,colour*(0.88+0.1*cos(i)))


static func emit(g: RefCounted, record: Dictionary) -> void:
	var kind := int(record.kind); var ground: Color = record.colour
	match kind:
		K.ASH: patch(g,ground*Color(0.68,0.68,0.66))
		K.SCORIA: slab(g,ground*Color(0.58,0.55,0.5),false,0.11)
		K.OBSIDIAN: slab(g,ground*Color(0.28,0.30,0.34),true,0.14)
		K.CRUST: slab(g,ground*Color(0.48,0.43,0.39),false)
		K.MOSS: patch(g,ground.lerp(Color(0.25,0.38,0.15),0.65))
		K.LICHEN: patch(g,ground.lerp(Color(0.52,0.56,0.35),0.50))
		K.WET: patch(g,ground)
		K.SLAB: slab(g,ground,false)
		K.RUBBLE: slab(g,ground,true,0.17)
		K.FERN:
			var c := ground.lerp(Color(0.21,0.38,0.16),0.75)
			for i in 7:
				var turn := Basis(Vector3.UP,i*TAU/7.0+g.seed)
				var middle := turn*Vector3(0,0.22,0.13)
				var tip := turn*Vector3(0,0.23,0.38)
				g.bent_ribbon(Vector3.ZERO,middle,tip,0.006,0.003,c*0.8,c)
				for j in range(1,6):
					var t := float(j)/6.0; var at := Vector3(0,sin(t*2.0)*0.25,t*0.38)
					var length := 0.09*(1.0-t)+0.015
					for sign: float in [-1.0,1.0]:
						g.triangle(turn*(at+Vector3(0,0,-0.018)),turn*(at+Vector3(sign*length,0.01,0.035)),turn*(at+Vector3(0,0,0.02)),c)
		K.ROOTS:
			var c := ground.lerp(Color(0.26,0.21,0.14),0.7)
			for i in 6:
				var turn := Basis(Vector3.UP,i*TAU/6.0+g.seed)
				var a := turn*Vector3(0,0.65+0.1*sin(i),0.03)
				var b := turn*Vector3(0.02,0.18,0.16)
				var end := turn*Vector3(0.04,0.01,0.43)
				cylinder(g,a,b,0.012,c); cylinder(g,b,end,0.007,c)
		K.MUSHROOM:
			for i in 3:
				var base := ring(i*2.4,0.10,0.0)
				var top := base+Vector3(0,0.16+0.025*i,0)
				cylinder(g,base,top,0.016,Color(0.39,0.48,0.31))
				ellipsoid(g,top,Vector3(0.085,0.04,0.085),Color(0.40,0.62,0.30))
		K.BONES:
			var ivory := Color(0.70,0.65,0.50)
			for i in 4:
				var turn := Basis(Vector3.UP,i*2.4+g.seed)
				var a := turn*Vector3(-0.15+i*0.008,0.028,-0.08)
				var b := turn*Vector3(0.20+i*0.025,0.036,-0.04)
				cylinder(g,a,b,0.012,ivory)
				ellipsoid(g,a,Vector3.ONE*0.021,ivory); ellipsoid(g,b,Vector3.ONE*0.021,ivory)
		K.SKULL:
			var ivory := Color(0.72,0.67,0.53)
			ellipsoid(g,Vector3(0,0.105,0),Vector3(0.105,0.10,0.12),ivory)
			ellipsoid(g,Vector3(0,0.036,0.065),Vector3(0.075,0.025,0.07),ivory*0.85)
			for sign: float in [-1.0,1.0]: ellipsoid(g,Vector3(sign*0.044,0.11,0.106),Vector3(0.028,0.033,0.012),Color(0.13,0.12,0.10))
		K.WEB:
			var silk := Color(0.58,0.59,0.56)
			for i in 8:
				g.ribbon(Vector3(0,0.2,0),ring(i*TAU/8.0,0.46,0.01),0.003,silk)
				for j in range(1,5):
					var t := j/4.0
					g.ribbon(ring(i*TAU/8.0,0.46*t,0.2-0.19*t),ring((i+1)*TAU/8.0,0.46*t,0.2-0.19*t),0.002,silk*0.9)
		K.CRYSTAL:
			for i in 4:
				var base := ring(i*2.4,0.065,0)
				var top := base+Vector3(0.02,0.22+0.035*i,0.01)
				for j in 6: g.triangle(base+ring(j*TAU/6.0,0.05,0),top,base+ring((j+1)*TAU/6.0,0.05,0),Color(0.40,0.47,0.45)*(0.8+0.1*(j%3)))
