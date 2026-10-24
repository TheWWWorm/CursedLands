class_name GraphicsAttribution
extends RefCounted
## Package contents determine attribution, independently of GPU support or
## current settings. build_rtx_preview.py sets these flags in its export copy.
## NVIDIA artwork is a local review layout until written placement approval.

const NRD_FLAG := "application/graphics_sdk/nrd"
const NRD_CREDIT := "NVIDIA Real-Time Denoisers (NRD): REBLUR path-tracing denoising."
const NVIDIA_FLAG := "application/graphics_sdk/nvidia"
const AMD_FLAG := "application/graphics_sdk/amd"
const NVIDIA_CREDIT := "NVIDIA DLSS and NVIDIA Reflex via NVIDIA Streamline."
const NVIDIA_SOURCE := "This software contains source code provided by NVIDIA Corporation."
const NVIDIA_MARKS := "NVIDIA, the NVIDIA logo, GeForce RTX and DLSS are trademarks and/or registered trademarks of NVIDIA Corporation in the U.S. and other countries."
const AMD_CREDIT := "AMD FSR Upscaling and AMD FSR Frame Generation via AMD FidelityFX SDK."
const AMD_MARKS := "AMD, the AMD Arrow logo, AMD FSR and combinations thereof are trademarks of Advanced Micro Devices, Inc."
const LICENSES := "Full license and copyright notices are included in the licenses folder."
const TEXTS := ["Graphics technologies", NVIDIA_CREDIT, NRD_CREDIT, NVIDIA_SOURCE, NVIDIA_MARKS, AMD_CREDIT, AMD_MARKS, LICENSES]


static func credits_bbcode() -> String:
	var nvidia := bool(ProjectSettings.get_setting(NVIDIA_FLAG, false))
	var nrd := bool(ProjectSettings.get_setting(NRD_FLAG, false))
	var amd := bool(ProjectSettings.get_setting(AMD_FLAG, false))
	if not nvidia and not nrd and not amd:
		return ""
	var text := "[center][font_size=26]" + RemakeText.t("Graphics technologies") + "[/font_size]\n\n"
	if nvidia or nrd:
		text += "[img width=280 height=85]res://assets/branding/vendors/nvidia-geforce-rtx.tres[/img]\n\n"
		if nvidia: text += "[font_size=20]" + RemakeText.t(NVIDIA_CREDIT) + "\n[/font_size]"
		if nrd: text += "[font_size=20]" + RemakeText.t(NRD_CREDIT) + "\n[/font_size]"
		text += "[font_size=16]" + RemakeText.t(NVIDIA_SOURCE) + "\n\n" + RemakeText.t(NVIDIA_MARKS) + "[/font_size]\n\n\n"
	if amd:
		text += "[img width=175 height=110]res://assets/branding/vendors/amd-fsr-upscaling-white.png[/img]      "
		text += "[img width=202 height=110]res://assets/branding/vendors/amd-fsr-frame-generation-white.png[/img]\n\n"
		text += "[font_size=20]" + RemakeText.t(AMD_CREDIT) + "[/font_size]\n"
		text += "[font_size=16]" + RemakeText.t(AMD_MARKS) + "[/font_size]\n\n"
	text += "[font_size=16]" + RemakeText.t(LICENSES) + "[/font_size]\n\n\n\n[/center]"
	return text
