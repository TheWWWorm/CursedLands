extends RefCounted
## Volumetric cloud colour is unused when a fully confident opaque-screen
## reflection replaces it, or when the final reflection weight is exactly zero.
const SKY := "ei_lin(ei_cloud_sky(ei_sky,wpos,reflect(normalize((INV_VIEW_MATRIX*vec4(vdir,0.0)).xyz),wn),ei_ambient,ei_sun))"
const START := "vec3 R = ei_lin(ei_sky);"
const TRACE := "vec4 r = water_ssr("
const MIX := "R = mix(R, r.rgb, r.a);"
const WEIGHT := "w *= (1.0 - foam) * shore;"

static func inject(source: String, skip_hidden: bool) -> String:
	var legacy := source.replace(START,"vec3 R = "+SKY+";")
	if not skip_hidden: return legacy
	# Retain the original injection if a different water implementation does
	# not expose this composition. Qualification checks require all markers.
	for marker: String in [START,TRACE,MIX,WEIGHT]:
		if source.count(marker) != 1: return legacy
	var code := source.replace(START,START+"\n\t\tvec4 r = vec4(0.0);")
	code = code.replace(TRACE,"r = water_ssr(")
	code = code.replace(MIX,"")
	# Keep fractional-confidence blending and every contributing ray exact.
	# No threshold, sample-count reduction or texture history is introduced.
	return code.replace(WEIGHT,WEIGHT+"\n\t\tif (w != 0.0 && (!reflections || r.a != 1.0)) { R = "+SKY+"; }\n\t\tif (reflections) { "+MIX+" }")
