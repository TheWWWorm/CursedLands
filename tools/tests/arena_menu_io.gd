extends Node
## The real menu must not validate the filesystem from drawing/layout/input.
var checks:=0
var failures:=0
var panel:ArenaOnlinePanel
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:int)->void:
 for i in n:await get_tree().process_frame
func _ready()->void:
 GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"confine_mouse":0,"show_fps":1},true)
 # Either owned edition suffices for this IO contract. Validating the first
 # registered path already invalidated the cache in the old draw loop.
 GameData.campaign_roots[CampaignProfile.ORIGINAL]=GameData.root
 GameData.campaign_roots[CampaignProfile.ASTRAL]=GameData.root
 panel=ArenaOnlinePanel.new();add_child(panel);panel.open()
 for language in ["en","ru","de"]:
  RemakeText.lang=language
  for page in [NetworkPanel.MODES,NetworkPanel.HOST_COOP,NetworkPanel.JOIN_COOP]:
   panel.show_page(page)
   for locked in [false,true]:
    panel.hosting=locked and page==NetworkPanel.HOST_COOP;panel.joining=locked and page==NetworkPanel.JOIN_COOP
    GameFiles._case_cache["menu-regression-sentinel"]="retained"
    for frame in 12:
     panel._rows();panel._row_h();panel._get_tooltip(Vector2(300,200));panel.pad_targets()
     await frames(1)
    check(GameFiles._case_cache.has("menu-regression-sentinel"),"no installation scan during menu work: %s/%d/%s"%[language,page,locked])
    var mode:Dictionary=panel._rows().filter(func(row):return row.id=="arena_mode")[0]
    check(bool(mode.on)==not (panel.hosting or panel.joining),"mode availability and connection lock preserved")
    check(panel._rows()[0].label==RemakeText.t("Your name"),"language updates without rebuilding availability")
 panel.hosting=false;panel.joining=false
 GameData.campaign_roots[CampaignProfile.ASTRAL]="user://missing-arena-install"
 panel.hide();panel.open();panel.show_page(NetworkPanel.HOST_COOP)
 check(not bool(panel._rows().filter(func(row):return row.id=="arena_mode")[0].on),"reopening refreshes removed installation")
 GameData.campaign_roots[CampaignProfile.ASTRAL]=GameData.root
 panel.hide();panel.open();panel.show_page(NetworkPanel.HOST_COOP)
 check(bool(panel._rows().filter(func(row):return row.id=="arena_mode")[0].on),"reopening refreshes restored installation")
 GameFiles._case_cache.erase("menu-regression-sentinel")
 panel.queue_free();await frames(3)
 print("ARENA_MENU_IO ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)
