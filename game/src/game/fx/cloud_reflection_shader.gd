extends RefCounted
## Volumetric cloud colour is unused when a fully confident opaque-screen
## reflection replaces it, or when the final reflection weight is exactly zero.
const SKY := "ei_lin(ei_cloud_sky(ei_sky,wpos,reflect(normalize((INV_VIEW_MATRIX*vec4(vdir,0.0)).xyz),wn),ei_ambient,ei_sun))"
const START := "vec3 R = ei_lin(ei_sky);"
const TRACE := "vec4 r = water_ssr("
const MIX := "vec4 reflected = reflection_over_sky(R, w, r, wm);"
const WEIGHT := "w *= (1.0 - foam) * shore;"
const BEFORE_MIX := "if (w > 0.0 && shore > 0.0 && r.a < 1.0) { R = water_sky_colour(CLOUD_SAMPLE, swamp); }\n\t\t\t"
const BEFORE_WEIGHT := "if (!reflections && w > 0.0 && shore > 0.0) { R = water_sky_colour(CLOUD_SAMPLE, swamp); }\n\t\t"
const CACHED_SKY := "ei_water_cloud(wpos,reflect(normalize((INV_VIEW_MATRIX*vec4(vdir,0.0)).xyz),wn))"
const CACHE := """
uniform sampler2D cloud_reflection_texture : source_color, filter_linear, repeat_disable;
uniform bool cloud_reflection_ready = false;
uniform mat4 cloud_reflection_projection;
uniform mat4 cloud_reflection_view;
vec3 ei_water_cloud(vec3 origin, vec3 ray) {
	if (cloud_reflection_ready) {
		vec4 clip = cloud_reflection_projection * vec4(mat3(cloud_reflection_view) * ray, 0.0);
		vec2 uv = vec2(clip.x, -clip.y) / max(clip.w, 0.00001) * 0.5 + 0.5;
		if (clip.w > 0.0 && all(greaterThanEqual(uv,vec2(0.0))) && all(lessThanEqual(uv,vec2(1.0)))) {
			return textureLod(cloud_reflection_texture,uv,0.0).rgb;
		}
	}
	return ei_lin(ei_cloud_sky(ei_sky,origin,ray,ei_ambient,ei_sun));
}
"""

static func inject(source: String, skip_hidden: bool, cached := false) -> String:
	var legacy := source.replace(START,"vec3 R = "+SKY+";")
	if not skip_hidden: return legacy
	# Retain the original injection if a different water implementation does
	# not expose this composition. Qualification checks require all markers.
	for marker: String in [START,TRACE,MIX,WEIGHT,"vec3 water_sky_colour("]:
		if source.count(marker) != 1: return legacy
	var sample_ := CACHED_SKY if cached else SKY
	var code := source.replace(MIX,BEFORE_MIX.replace("CLOUD_SAMPLE",sample_)+MIX)
	code = code.replace(WEIGHT,BEFORE_WEIGHT.replace("CLOUD_SAMPLE",sample_)+WEIGHT)
	# Keep premultiplied scene/sky composition. A full scenery reflection,
	# zero Fresnel weight or dry shoreline never evaluates the cloud layer.
	if cached: code = code.replace("void vertex() {",CACHE+"\nvoid vertex() {")
	return code
