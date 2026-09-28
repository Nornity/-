extends RefCounted
## Only sector unlocks, records and preferences are saved. No hidden passwords.

const PATH = "user://lower_level.cfg"
var unlocked: int = 1
var best: Dictionary = {}
var endless_best: int = 0
var settings: Dictionary = {
	"sensitivity": 1.0, "volume": 0.55, "brightness": 1.0,
	"reduced_effects": false
}

func load_progress() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	unlocked = clampi(int(file.get_value("progress", "unlocked", 1)), 1, 3)
	endless_best = maxi(0, int(file.get_value("progress", "endless_best", 0)))
	var stored_best = file.get_value("progress", "best", {})
	if stored_best is Dictionary:
		for key in stored_best:
			if stored_best[key] is float or stored_best[key] is int:
				if float(stored_best[key]) > 0.0:
					best[str(key)] = float(stored_best[key])
	settings.sensitivity = clampf(float(file.get_value("settings", "sensitivity", 1.0)), 0.3, 3.0)
	settings.volume = clampf(float(file.get_value("settings", "volume", 0.55)), 0.0, 1.0)
	settings.brightness = clampf(float(file.get_value("settings", "brightness", 1.0)), 0.7, 1.7)
	settings.reduced_effects = bool(file.get_value("settings", "reduced_effects", false))

func save_progress() -> Error:
	var file := ConfigFile.new()
	file.set_value("progress", "unlocked", unlocked)
	file.set_value("progress", "best", best)
	file.set_value("progress", "endless_best", endless_best)
	for key in settings:
		file.set_value("settings", key, settings[key])
	var result := file.save(PATH)
	if result != OK:
		push_warning("Не удалось сохранить настройки: %s" % error_string(result))
	return result

func record_sector(id: int, seconds: float) -> bool:
	var key := str(id)
	var is_record: bool = not best.has(key) or seconds < float(best[key])
	if is_record:
		best[key] = seconds
	if id > 0:
		unlocked = maxi(unlocked, mini(3, id + 1))
	save_progress()
	return is_record

static func format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
