extends Node
## Private fixture for standalone wiki QA; uses the same catalog/export flag.
func _ready() -> void:
	TutorialProgress.persist = false
	var output := "user://tutorial-web-fixture.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--guide-output="): output = arg.trim_prefix("--guide-output=")
	var all := {}
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		var catalog := WikiCatalog.new()
		catalog.public_export = true
		catalog.rebuild()
		var guides := {"category":RemakeText.t("Getting started"),"entries":[],"pages":{}}
		for key: String in catalog.ordered:
			var entry: Dictionary = catalog.entries[key]
			if entry.kind != "guide": continue
			var file := key.sha256_text().substr(0,20) + ".json"
			guides.entries.append({"key":key,"title":entry.title,"category":"Getting started","kind":"guide","file":file,"listed":true,"search":TutorialGuide.brief(entry.value)})
			guides.pages[file] = {"key":key,"relations":[],"versions":[{"id":"","title":entry.title,"html":catalog.page(key).html,"image":"","guide":"","pins":[]}]}
		assert(not catalog.entries.has("guide/recent"))
		all[language] = guides
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(all))
	print("TUTORIAL_WEB_FIXTURE ", output)
	get_tree().quit()
