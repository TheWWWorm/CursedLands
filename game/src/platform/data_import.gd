class_name PrivateDataImport
extends Node
## Native document URIs are copied into app-private storage. No broad Android
## storage permission is needed, and the URI never becomes the saved game root.
signal progress(text: String)
signal completed(folder: String)
signal failed(message: String)
var cancelled := false
var busy := false
var _installer: EIInnoSetup

func _exit_tree() -> void:
	cancelled = true
	if _installer:
		_installer.cancel()
		_installer.wait_to_finish()
		_installer = null

func import_file(path: String) -> void:
	if busy:
		return
	busy = true
	cancelled = false
	var stage := "user://import-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(stage)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_finish(stage, "The selected document could not be opened.")
		return
	var signature := file.get_buffer(8).get_string_from_ascii()
	file.seek(0)
	var error := ""
	if signature == "EIPACK01":
		error = await _pack(file, stage)
	else:
		var installer := stage.path_join("installer.exe")
		var output := FileAccess.open(installer, FileAccess.WRITE)
		if output == null:
			error = "Could not create the private import folder."
		else:
			while file.get_position() < file.get_length() and not cancelled:
				var bytes := file.get_buffer(mini(1048576, file.get_length() - file.get_position()))
				if bytes.is_empty():
					error = "Could not read the selected installer."
					break
				output.store_buffer(bytes)
				if output.get_error() != OK:
					error = "Not enough space to copy the installer."
					break
				progress.emit(RemakeText.t("Copying installer: %d%%") % (file.get_position() * 100 / maxi(file.get_length(), 1)))
				await get_tree().process_frame
			output.close()
			if not cancelled and error.is_empty():
				var setup := EIInnoSetup.open(installer)
				error = setup.error
				if error.is_empty():
					_installer = setup
					setup.extract(ProjectSettings.globalize_path(stage))
					while not setup.finished():
						if cancelled:
							setup.cancel()
						progress.emit(RemakeText.t("Unpacking installer: %d%%") % int(setup.progress() * 100.0))
						await get_tree().process_frame
					error = setup.failure()
					_installer = null
			DirAccess.remove_absolute(installer)
	file.close()
	if cancelled:
		error = "Import cancelled."
	if error.is_empty():
		error = GameData.validate(stage)
	_finish(stage, error)

func _pack(file: FileAccess, stage: String) -> String:
	file.seek(8)
	var header_size := file.get_32()
	if header_size < 2 or header_size > 4194304 or header_size + 12 > file.get_length():
		return "Invalid data pack header."
	var index: Variant = JSON.parse_string(file.get_buffer(header_size).get_string_from_utf8())
	if not index is Dictionary or index.is_empty() or index.size() > 20000:
		return "Invalid data pack index."
	var payload := header_size + 12
	# Validate every path and range before creating any file.
	for key: Variant in index:
		if not key is String or not index[key] is Dictionary:
			return "Invalid data pack entry."
		var name: String = key
		var entry: Dictionary = index[key]
		var offset := int(entry.get("offset", -1))
		var length := int(entry.get("size", -1))
		if name.is_empty() or name.is_absolute_path() or name.contains("\\") or name.contains(":") or ".." in name.split("/") or "" in name.split("/") or "." in name.split("/"):
			return "Invalid data pack path."
		if offset < 0 or length < 0 or length > 536870912 or payload + offset + length > file.get_length():
			return "Invalid data pack range."
	for key: String in index:
		if cancelled:
			return "Import cancelled."
		progress.emit(RemakeText.t("Importing %s") % key)
		var dest := stage.path_join(key)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var output := FileAccess.open(dest, FileAccess.WRITE)
		if output == null:
			return "Could not write imported game data."
		file.seek(payload + int(index[key].offset))
		var left := int(index[key].size)
		while left > 0:
			if cancelled:
				output.close()
				return "Import cancelled."
			var bytes := file.get_buffer(mini(left, 1048576))
			if bytes.is_empty():
				return "The data pack is incomplete."
			output.store_buffer(bytes)
			if output.get_error() != OK:
				return "Not enough space to import game data."
			left -= bytes.size()
			await get_tree().process_frame
		output.close()
	return ""

func _finish(stage: String, error: String) -> void:
	busy = false
	if error:
		_remove_tree(stage)
		failed.emit(error)
	else:
		completed.emit(stage)

static func _remove_tree(path: String) -> void:
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
