class_name CoopPermissions
extends RefCounted
## Host-owned campaign permissions. Names use the same reconnect identity as
## CoopProgress; transport peer IDs and occupied slots are never saved as grants.

const KEY := "permissions"
const PAUSE := 1
const SPEED := 2
const SAVE := 4
const LOAD := 8
const ALL := PAUSE | SPEED | SAVE | LOAD
const CLOCK_CHOICES := ["Host only", "Pause only", "Speed only", "Pause and speed"]
const SAVE_CHOICES := ["Host only", "Save only", "Load only", "Save and load"]

static func preferences() -> Array:
	return [GameData.option("coop_clock"), GameData.option("coop_guest_clock"), GameData.option("coop_guest_saves")]

static func defaults() -> Dictionary:
	return {"enabled": GameData.option("coop_clock") == 1,
		"default": clampi(GameData.option("coop_guest_clock"), 0, 3) |
			(clampi(GameData.option("coop_guest_saves"), 0, 3) << 2), "players": {}}

static func policy(s: Session) -> Dictionary:
	var value: Variant = s.state.coop.get(KEY) if s.state else null
	return value if value is Dictionary else (defaults() if s.is_host else {"default": 0, "players": {}})

static func ensure(s: Session) -> Dictionary:
	if not s.state.coop.get(KEY) is Dictionary:
		s.state.coop[KEY] = defaults()
	return s.state.coop[KEY]

static func identity(s: Session, player: int) -> String:
	for p: Dictionary in s.players.values():
		if int(p.index) == player:
			return String(p.name).strip_edges().to_lower()
	return ""

static func mask(s: Session, player: int) -> int:
	if player == 0: return ALL
	var key := identity(s, player)
	if key.is_empty(): return 0
	var rules := policy(s)
	var individual: Dictionary = rules.get("players", {}) if rules.get("players") is Dictionary else {}
	return int(individual.get(key, int(rules.get("default", 0)))) & ALL

static func allows(s: Session, player: int, permission: int) -> bool:
	return s.multiplayer_game and s.lmp.is_empty() and permission in [PAUSE, SPEED, SAVE, LOAD] \
		and (mask(s, player) & permission) != 0

static func set_player(s: Session, pid: int, permission: int, enabled: bool) -> void:
	if not s.is_host or not s.multiplayer_game or not s.lmp.is_empty() \
			or not s.players.has(pid) or permission not in [PAUSE, SPEED, SAVE, LOAD]:
		return
	var player := int(s.players[pid].index)
	if player == 0: return
	var key := identity(s, player)
	if key.is_empty(): return
	var value := mask(s, player)
	var rules := ensure(s)
	if not rules.get("players") is Dictionary: rules.players = {}
	rules.players[key] = (value | permission) if enabled else (value & ~permission)
