class_name GraphicsAttribution
extends RefCounted
## Package contents determine attribution, independently of GPU support or
## current settings. The Windows release export sets this flag in its export copy.

const AMD_FLAG := "application/graphics_sdk/amd"
const AMD_CREDIT := "AMD FSR Upscaling and AMD FSR Frame Generation via AMD FidelityFX SDK."
const AMD_MARKS := "AMD, the AMD Arrow logo, AMD FSR and combinations thereof are trademarks of Advanced Micro Devices, Inc."
const LICENSES := "Full license and copyright notices are included in the licenses folder."


const TEXTS := ["Graphics technologies", AMD_CREDIT, AMD_MARKS, LICENSES]


static func credits_bbcode() -> String:
	var amd := bool(ProjectSettings.get_setting(AMD_FLAG, false))
	if not amd:
		return ""
	var text := "[center][font_size=26]" + RemakeText.t("Graphics technologies") + "[/font_size]\n\n"
	if amd:
		text += "[img width=175 height=110]res://assets/branding/vendors/amd-fsr-upscaling-white.png[/img]      "
		text += "[img width=202 height=110]res://assets/branding/vendors/amd-fsr-frame-generation-white.png[/img]\n\n"
		text += "[font_size=20]" + RemakeText.t(AMD_CREDIT) + "[/font_size]\n"
		text += "[font_size=16]" + RemakeText.t(AMD_MARKS) + "[/font_size]\n\n"
	text += "[font_size=16]" + RemakeText.t(LICENSES) + "[/font_size]\n\n\n\n[/center]"
	return text
