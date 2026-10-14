## Run through --tool with --gfx-detect --gfx-handheld. An external controller
## kills the process after PROBE_DETECTION_STARTED for --prepare-detection,
## then restarts the same profile with --expect-no-test. --manual-detection
## must subsequently finish successfully. --cancel-detection / --quit-detection
## exercise cancellation and orderly exit on a fresh --fresh-detection run.
extends Node
var detecting := false
var elapsed := 0.0
var main: Node
var consent_given := false
func _ready() -> void:
    process_mode=Node.PROCESS_MODE_ALWAYS
    main=get_parent()
    if (OS.get_cmdline_user_args().has("--prepare-detection") or OS.get_cmdline_user_args().has("--fresh-detection")):
        GameData.options.merge(GfxDetect.base_values(),true)
        GameData.options.auto_graphics=1
        GameData.options.display_mode=0
        GameData.options.confine_mouse=0
        GameData.save_settings()
    await main.open_menu()
    GameData.options_changed.connect(observe)
    if OS.get_cmdline_user_args().has("--manual-detection"):
        GfxDetect.start(true)
    set_process(true)
func observe() -> void:
    for n in get_tree().root.get_children():
        if n is GfxDetect and int(n.get("_step")) > 0 and not detecting:
            detecting=true
            FileAccess.open("user://probe-detection-started.txt",FileAccess.WRITE).store_string(str(n.get("_step")))
            print("PROBE_DETECTION_STARTED")
            if OS.get_cmdline_user_args().has("--quit-detection"):
                print("PROBE_FINISHED clean-quit-during-test")
                get_tree().quit()
            if OS.get_cmdline_user_args().has("--cancel-detection"):
                n.cancel()
func _process(dt: float) -> void:
    elapsed+=dt
    if not consent_given and not OS.get_cmdline_user_args().has("--expect-no-test"):
        for n in get_tree().root.get_children():
            if n is GfxDetect and n._box is GraphicsCheckBox:
                consent_given=true
                print("PROBE_CONSENT accepted")
                n._box._answer(true)
    var rec := GfxDetect.load_record()
    var done: bool = detecting and not rec.get("testing",false) and (int(rec.get("tier",-1))>=0 or rec.get("cancelled",0) or rec.get("interrupted",0))
    if (elapsed>5 and OS.get_cmdline_user_args().has("--expect-no-test")) or done:
        print("PROBE_RECORD ",JSON.stringify(rec))
        print("PROBE_FINISHED detecting=",detecting)
        get_tree().quit()
    elif elapsed>60:
        printerr("PROBE_TIMEOUT")
        get_tree().quit(1)
