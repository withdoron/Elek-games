extends Node

# === SPEED ===
var max_speed: float = 38.0
var acceleration: float = 22.0
var brake_force: float = 30.0
var reverse_speed: float = 12.0
var coast_decel: float = 7.0

# === STEERING ===
var turn_speed: float = 2.5
var turn_speed_factor: float = 0.8
var return_to_center: float = 5.0

# === DRIFT ===
var drift_factor: float = 0.92
var drift_turn_boost: float = 1.5

# === PHYSICS ===
var gravity: float = 30.0

# === CONTROLLER ===
var deadzone: float = 0.25
var stick_sensitivity: float = 1.0

# === AUDIO ===
var master_volume: float = 1.0

# Setting metadata: [default, min, max, step, section]
const SETTING_META := {
	"max_speed":        [38.0, 10.0, 75.0, 0.5, "SPEED"],
	"acceleration":     [22.0, 5.0, 45.0, 0.5, "SPEED"],
	"brake_force":      [30.0, 10.0, 60.0, 0.5, "SPEED"],
	"reverse_speed":    [12.0, 3.0, 22.0, 0.5, "SPEED"],
	"coast_decel":      [7.0, 1.0, 20.0, 0.5, "SPEED"],
	"turn_speed":       [2.5, 1.0, 5.0, 0.1, "STEERING"],
	"turn_speed_factor":[0.8, 0.3, 1.0, 0.01, "STEERING"],
	"return_to_center": [5.0, 1.0, 10.0, 0.5, "STEERING"],
	"drift_factor":     [0.92, 0.8, 0.99, 0.01, "DRIFT"],
	"drift_turn_boost": [1.5, 1.0, 2.5, 0.1, "DRIFT"],
	"gravity":          [30.0, 10.0, 50.0, 1.0, "PHYSICS"],
	"deadzone":         [0.25, 0.05, 0.5, 0.01, "CONTROLLER"],
	"stick_sensitivity": [1.0, 0.5, 2.0, 0.1, "CONTROLLER"],
	"master_volume":    [1.0, 0.0, 1.0, 0.05, "AUDIO"],
}

const SAVE_PATH := "user://settings.cfg"


func _ready() -> void:
	load_settings()


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in SETTING_META:
		var section: String = SETTING_META[key][4]
		config.set_value(section, key, get(key))
	config.save(SAVE_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		return
	for key in SETTING_META:
		var section: String = SETTING_META[key][4]
		if config.has_section_key(section, key):
			set(key, config.get_value(section, key))


func reset_defaults() -> void:
	for key in SETTING_META:
		set(key, SETTING_META[key][0])
	save_settings()


func get_sections() -> Array:
	var sections: Array = []
	for key in SETTING_META:
		var section: String = SETTING_META[key][4]
		if section not in sections:
			sections.append(section)
	return sections


func get_settings_for_section(section: String) -> Array:
	var keys: Array = []
	for key in SETTING_META:
		if SETTING_META[key][4] == section:
			keys.append(key)
	return keys
