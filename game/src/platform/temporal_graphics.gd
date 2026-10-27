class_name TemporalGraphics
extends RefCounted
## Screen controls share a single upscaler and a single presentation owner.
const FG_CHOICES := ["Off", "FSR 3.1", "FSR 4", "NVIDIA DLSS"]
const QUALITY_HELP := "Native AA uses full resolution (DLAA with NVIDIA DLSS). Quality, Balanced and Performance render fewer pixels. Select FSR or NVIDIA DLSS in Anti-aliasing first."
const FG_HELP := "Generate one extra display frame per rendered frame. FSR can work without upscaling. NVIDIA requires DLSS or DLAA, supported RTX hardware and Windows GPU scheduling; Reflex is enabled automatically. Suspends in menus, while loading and on focus loss. Switching between AMD and NVIDIA requires a restart."

static func aa_selection(values: Dictionary) -> int:
	return 8 if RtxGraphics.selected(values) else FsrGraphics.aa_selection(values)

static func aa_reason(selection: int, values: Dictionary) -> String:
	if selection == 8: return RtxGraphics.selection_reason(values)
	if selection >= 6 and RtxGraphics.facts().launch: return ""
	return FsrGraphics.aa_reason(selection, values)

static func quality_selection(values: Dictionary) -> int:
	return int(values.get(RtxGraphics.UPSCALING, 1)) - 1 if RtxGraphics.selected(values) else int(values.get(FsrGraphics.QUALITY, 1))

static func quality_reason(values: Dictionary) -> String:
	return RtxGraphics.selection_reason(values) if RtxGraphics.selected(values) else aa_reason(aa_selection(values),values) if int(values.get(FsrGraphics.UPSCALING,0)) > 0 else FsrGraphics.ENABLE_SR

static func fg_selection(values: Dictionary) -> int:
	return 3 if int(values.get(RtxGraphics.FRAME_GENERATION, 0)) > 0 else int(values.get(FsrGraphics.FRAME_GENERATION, 0))

static func fg_reason(selection: int, values: Dictionary) -> String:
	if selection == 0: return ""
	if selection == 3:
		if not RtxGraphics.selected(values): return RtxGraphics.ENABLE_SR
		var info := RtxGraphics.facts()
		if not info.launch: return RtxGraphics.selection_reason(values)
		return RtxGraphics.reason_for(RtxGraphics.FRAME_GENERATION, info, int(values.get(RtxGraphics.UPSCALING,0)))
	if RtxGraphics.selected(values): return "Select FSR or another anti-aliasing mode before enabling FSR frame generation."
	if RtxGraphics.facts().launch: return ""
	var proposed := values.duplicate()
	proposed[FsrGraphics.FRAME_GENERATION] = selection
	return FsrGraphics.reason(FsrGraphics.FRAME_GENERATION, proposed)

static func hint(values: Dictionary) -> String:
	if RtxGraphics.needs_restart(values): return RtxGraphics.NEED_RESTART
	var fg := fg_reason(fg_selection(values), values)
	if not fg.is_empty(): return fg
	if RtxGraphics.selected(values): return RtxGraphics.reason(RtxGraphics.UPSCALING,values)
	return FsrGraphics.screen_hint(FsrGraphics.facts())
