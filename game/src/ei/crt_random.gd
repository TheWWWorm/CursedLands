class_name EICrtRandom
extends RefCounted
## The game's CRT rand (6e77b7), with an explicit local stream.6f007e
## initializes a thread's seed to1. Runtime shared-stream history remains
## the caller's responsibility; this does not replace Godot's global RNG.

var state: int

func _init(seed_value := 1) -> void:
	state = seed_value & 0xffffffff

func next_int() -> int:
	state = (state * 0x343fd + 0x269ec3) & 0xffffffff
	return (state >> 16) & 0x7fff
