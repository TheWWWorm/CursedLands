class_name WikiCampArt
extends RefCounted
## Original 800-unit camp sprites. The same exports are used by the website.
static var _cache := {}
static func source(name: String) -> Image:
	var image := GameData.load_image(name)
	if image:image.flip_y();image.convert(Image.FORMAT_RGBA8)
	return image
static func crop(name: String, rect: Rect2i) -> Image:
	var image := source(name)
	if not image:return null
	var factor := float(image.get_width())/256.0
	var region := image.get_region(Rect2i(Vector2(rect.position)*factor,Vector2(rect.size)*factor))
	region.resize(rect.size.x,rect.size.y,Image.INTERPOLATE_LANCZOS)
	return region
static func panel() -> Image:
	var out := Image.create(200,400,false,Image.FORMAT_RGBA8)
	var tile := crop("campinfo",Rect2i(14,14,100,100))
	if not tile:return out
	for x in 2:
		for y in 4:out.blit_rect(tile,Rect2i(0,0,100,100),Vector2i(x*100,y*100))
	var edge := crop("campinfo",Rect2i(233,76,21,100))
	for y in 4:out.blit_rect(edge,Rect2i(0,0,21,100),Vector2i(179,y*100))
	edge.flip_x()
	for y in 4:out.blit_rect(edge,Rect2i(0,0,21,100),Vector2i(0,y*100))
	var top := crop("campinfo",Rect2i(154,2,100,30));out.blit_rect(top,Rect2i(0,0,100,30),Vector2i(100,0));top.flip_x();out.blit_rect(top,Rect2i(0,0,100,30),Vector2i.ZERO)
	top.flip_y();out.blit_rect(top,Rect2i(0,0,100,30),Vector2i(0,370));top.flip_x();out.blit_rect(top,Rect2i(0,0,100,30),Vector2i(100,370))
	return out
static func texture(name: String) -> Texture2D:
	var key := GameData.campaign_id+"|"+name
	if _cache.has(key):return _cache[key]
	var image: Image
	match name:
		"panel":image=panel()
		"weapon":image=crop("campslots",Rect2i(14,14,100,100))
		"quick":image=crop("campslots",Rect2i(142,14,100,100))
		"spell":image=crop("campslots",Rect2i(14,142,100,100))
		"bag":image=crop("inventory01",Rect2i(14,14,100,100))
		"stock":image=crop("inventory02",Rect2i(14,14,100,100))
		"button":image=crop("campinfo",Rect2i(124,138,40,15))
	if not image:return null
	var tex := ImageTexture.create_from_image(image);_cache[key]=tex;return tex
static func panel_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new();style.texture=texture("panel");style.set_content_margin_all(16);return style
static func theme(base: Theme) -> Theme:
	var result := WikiWorkbench.workshop_theme(base)
	result.default_font=Interface800.font();result.default_font_size=16
	result.set_font("normal_font","RichTextLabel",Interface800.font());result.set_font("bold_font","RichTextLabel",Interface800.font())
	result.set_color("table_odd_row_bg","RichTextLabel",Color.TRANSPARENT);result.set_color("table_even_row_bg","RichTextLabel",Color.TRANSPARENT)
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxTexture.new();style.texture=texture("button");style.modulate_color=Color(1.2,1.15,1.0) if state in ["hover","focus"] else Color.WHITE;style.set_content_margin_all(5)
		result.set_stylebox(state,"Button",style)
		result.set_stylebox(state,"LineEdit",style)
	return result
