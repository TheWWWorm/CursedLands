class_name ModCatalog
extends RefCounted
## Reviewed, version-pinned downloads. Nothing is fetched when opening the menu.
## Add a tested recipe and its original publisher URL here; never infer support
## from an archive extension or accept a remote catalog as executable policy.
const ENTRIES := [{
	"id": "community.hd-lands-textures", "version": "1.4.0",
	"title": "HD Lands textures", "author": "Atom",
	"description": "Sharper terrain, buildings and character textures from HD Lands 1.4.0.",
	"notes": "Texture-only installation. Original readme and credits are included. One damaged source texture is omitted.",
	"source": "https://hd-lands.gipat.ru/",
	"url": "https://hd-lands.gipat.ru/wp-content/uploads/2021/10/hd-lands-v-1.4.0.7z",
	"hosts": ["hd-lands.gipat.ru"], "bytes": 244608954,
	"sha256": "f08f8c11058dbbe3cb12a1ca75b6263a5eec12fae0e62ffd1f47be359bc4ed1c",
	"campaigns": ["cursed_lands"], "format": "resource-7z",
	"folder": "HD Lands v 1.4.0",
	"resources": [
		{"source": "textures.res", "archive": "textures.res"},
		{"source": "objtextures.res", "archive": "textures.res"}],
	"exclude": ["textures.res/astralold.mmp"],
	"attachments": ["readme.txt", "changelog.txt"],
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
	var host := url.trim_prefix("https://").get_slice("/", 0).to_lower()
	return host in hosts and not host.contains("@") and not host.contains(":")
