class_name EnemyWordDb
extends RefCounted

const PATH := "res://data/enemy_words.json"

static var _words: Array[String] = []
static var _loaded: bool = false


static func pick_random() -> String:
	_ensure_loaded()
	if _words.is_empty():
		return "???"
	return _words[randi() % _words.size()]


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("EnemyWordDb: no se pudo abrir %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var arr: Variant = parsed.get("words", [])
		if arr is Array:
			for w in arr:
				var s := str(w).strip_edges()
				if not s.is_empty():
					_words.append(s)
