class_name MovieSequence
extends CanvasLayer
## Plays movies one after another full screen, then emits `done` and frees
## itself: the config/movie.ini lists (the original: startup [Start]
## the credits screens' "<name>fin" / "<name>fout"). A movie that is missing
## is skipped; Esc / Space skips the current one (the original).

signal done

var _names: PackedStringArray
var _player: MoviePlayer


static func start(parent: Node, names: PackedStringArray) -> MovieSequence:
	var s := MovieSequence.new()
	s.layer = 110
	s._names = names
	parent.add_child(s)
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = MoviePlayer.new()
	add_child(_player)
	_player.finished.connect(_next, CONNECT_DEFERRED)
	_next.call_deferred()


func _next() -> void:
	while not _names.is_empty():
		var n := _names[0]
		_names.remove_at(0)
		_player.play(n)
		if _player._state != MoviePlayer.IDLE:
			return
	done.emit()
	queue_free()
