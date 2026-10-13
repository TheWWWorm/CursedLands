class_name ModCatalog
extends RefCounted
## Reviewed, version-pinned downloads. Nothing is fetched when opening the menu.
## Add a tested recipe and its original publisher URL here; never infer support
## from an archive extension or accept a remote catalog as executable policy.
const ENTRIES := [{
	"id": "community.hd-lands-textures", "version": "1.5.0",
	"title": "HD Lands textures", "author": "Atom",
	"description": "Sharper terrain, buildings and character textures from HD Lands 1.5.0.",
	"notes": "Texture-only installation. Original readme and development notes are included.",
	"source": "https://allods.gipat.ru/index.php?p=eimodshdlands",
	"url": "https://allods.gipat.ru/files/ei/mods/hdlands/hdlands-1-5-0.7z",
	"hosts": ["allods.gipat.ru"], "bytes": 285931035,
	"fallback": {
		"url": "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=https%3A%2F%2Fdisk.yandex.ru%2Fd%2Fc8hPzBwUtYr50w&path=%2FHD_Lands_1.5.7z",
		"resolver": "yandex-disk",
		"hosts": ["cloud-api.yandex.net", "downloader.disk.yandex.ru", "*.storage.yandex.net"]},
	"sha256": "574f9a2dd91e530054c07cc27c868d5db8e04f047254b89669460c621b43a955",
	"campaigns": ["cursed_lands"], "format": "resource-7z",
	"folder": "HD_Lands_1.5",
	# Texture providers follow config.ini order; the HD Pack contributes only
	# entries not supplied by the preceding HD Lands archives. No models load.
	"resources": [
		{"source": "HDRes/share.res", "archive": "textures.res", "entries": ["gipatmap.mmp", "gipatmapg.mmp", "suslangermap.mmp", "suslangermapg.mmp"]},
		{"source": "HDTexRes/t_nature.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_objects.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_units.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_world.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_interface.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zoneMain.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_basegipat.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz2g.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz3g.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz4g.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz5g.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz6g.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz7g.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz8k.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz9k.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz10k.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz11k.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz13h.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz14h.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz15h.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz16h.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_bz18h.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone1.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone2.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone3.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone4.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone5.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone6.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone7.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone8.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone9.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone10.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone11.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone12.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone13.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone14.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone15.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone16.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone17.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone18.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone19.res", "archive": "textures.res"},
		{"source": "HDTexRes/t_zone20.res", "archive": "textures.res"},
		{"source": "HDRes/hdpack.res", "archive": "textures.res", "entries": ["beholder03.mmp", "bloodprints.mmp", "campfire00.mmp", "curse01.mmp", "fakedocument00.mmp", "hadoganshipyard00.mmp", "moneysack00.mmp", "rainsnow.mmp", "tree04.mmp"]}],
	"attachments": ["readme.txt", "changelog.txt", "dev.txt", "zones_completion_stage.md"],
	"conflicts": ["legacy.hd-lands"],
	"space_bytes": 2147483648
}]

static func entry(id: String) -> Dictionary:
	for item in ENTRIES:
		if item.id == id: return item.duplicate(true)
	return {}

static func key(item: Dictionary) -> String:
	return item.id + "@" + item.version

static func unavailable(item: Dictionary) -> String:
	# The solid archive needs about 0.8 GiB temporary RAM. Keep this entry
	# unavailable on Android until installation is qualified on-device.
	if OS.has_feature("web") or OS.has_feature("android"): return "This download is available in the Windows and Linux apps."
	if item.format == "resource-7z" and not ClassDB.class_exists("ModArchiveExtractor"):
		return "This build does not include the archive installer."
	if GameData.campaign_id not in item.campaigns: return "This download is for Cursed Lands."
	return ""

static func allowed_url(url: String, hosts: Array) -> bool:
	if not url.begins_with("https://") or url.contains("#") or url.contains("\\"): return false
	var host := url.trim_prefix("https://").get_slice("/", 0).get_slice("?", 0).to_lower()
	if host.contains("@") or host.contains(":") or host.contains("%"): return false
	for approved: String in hosts:
		if host == approved: return true
		# Yandex Disk redirects to rotating nodes beneath this reviewed domain.
		if approved.begins_with("*.") and host.ends_with(approved.substr(1)) and host.length() > approved.length() - 1: return true
	return false
