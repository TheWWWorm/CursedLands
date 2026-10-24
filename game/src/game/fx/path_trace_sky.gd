extends RefCounted
## A low-frequency outdoor environment derived from the authored light/sky
## palette. The original ambient colour was a lighting floor (max), whereas
## PT adds sky transport to sunlight. Do not add that whole floor again.
static func palette(ambient: Color, sun: Color, sky: Color, cave: bool, daylight := -1.0) -> PackedFloat32Array:
	var result := PackedFloat32Array(); result.resize(12)
	if cave: return result
	var base := ambient.srgb_to_linear()
	var day := Gfx.sun_day(sun) if daylight<0.0 else daylight
	var colour := sky.srgb_to_linear()
	var luminance := colour.r*0.2126+colour.g*0.7152+colour.b*0.0722
	# Borrow restrained chroma, not the visible dome's exposure. A black sky
	# palette must not divide by zero or turn the night environment white.
	var tint := Color.WHITE
	if luminance>0.0001:
		tint = Color(clampf(colour.r/luminance,0.6,1.4),clampf(colour.g/luminance,0.6,1.4),clampf(colour.b/luminance,0.6,1.4))
	var zenith := base*Color.WHITE.lerp(tint,0.35*day)*lerpf(1.0,0.70,day)
	var horizon := base*lerpf(0.65,0.45,day)
	# The traced terrain supplies local ground bounce. Only a faint distant
	# environment remains below the horizon at the bounded scene's edge.
	var ground := base*lerpf(0.12,0.06,day)
	for i in 3:
		var c: Color = [zenith,horizon,ground][i]
		result[i*4]=c.r;result[i*4+1]=c.g;result[i*4+2]=c.b
	return result

## Rain closes the sky above the bounded transport scene. Apply the energy
## change before sharing the palette with PT and its conventional receivers;
## otherwise a missed ray would reveal a clear-day patch in the same storm.
static func overcast(ambient: Color, sun: Color, amount: float, cave: bool) -> Array[Color]:
	var storm := clampf(amount,0.0,1.0)*Gfx.sun_day(sun) if not cave else 0.0
	if storm<=0.0: return [ambient,sun]
	var diffuse := ambient.srgb_to_linear()*lerpf(1.0,0.65,storm)
	var direct := sun.srgb_to_linear()*lerpf(1.0,0.14,storm)
	diffuse.a=1.0;direct.a=1.0
	return [diffuse.linear_to_srgb(),direct.linear_to_srgb()]
