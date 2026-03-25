extends Node3D

var kart: Node3D
var speedometer: Label
var menu_ui: Control

# Hill parameters — shared with player_kart.gd via get_ground_height
const HILL_CENTER_Z = -50.0
const HILL_HALF_WIDTH = 30.0
const HILL_HEIGHT = 12.0


func _ready() -> void:
	_build_world()
	_spawn_kart()
	_create_speedometer()
	_create_menu()
	# Start paused — menu shows first
	get_tree().paused = true


func _process(_delta: float) -> void:
	if kart and speedometer and not get_tree().paused:
		var spd = abs(kart.speed)
		speedometer.text = "%d km/h" % int(spd * 3.6)


func _build_world() -> void:
	# --- Sky ---
	var env = WorldEnvironment.new()
	var environment = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.9)
	sky_mat.sky_horizon_color = Color(0.65, 0.75, 0.9)
	sky_mat.ground_bottom_color = Color(0.3, 0.25, 0.2)
	sky_mat.ground_horizon_color = Color(0.65, 0.75, 0.9)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5
	env.environment = environment
	add_child(env)

	# --- Sun ---
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	# --- Grass ground (visual only) ---
	var grass = MeshInstance3D.new()
	var grass_mesh = PlaneMesh.new()
	grass_mesh.size = Vector2(500, 500)
	grass.mesh = grass_mesh
	var grass_mat = StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.25, 0.55, 0.2)
	grass.material_override = grass_mat
	add_child(grass)

	# --- Straight road with hill ---
	_build_straight_road()

	# --- Hill terrain mesh (green mound matching the ground height) ---
	_build_hill_terrain()


func _build_straight_road() -> void:
	var road_width = 10.0
	var road_start_z = 80.0
	var road_end_z = -130.0
	var segments = 200
	var road_mat = StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.45, 0.35, 0.22)

	var total_length = road_start_z - road_end_z
	var seg_length = total_length / segments

	for i in range(segments):
		var z_front = road_start_z - i * seg_length
		var z_back = road_start_z - (i + 1) * seg_length
		var z_mid = (z_front + z_back) / 2.0

		var h_front = get_ground_height(0, z_front)
		var h_back = get_ground_height(0, z_back)
		var h_mid = (h_front + h_back) / 2.0

		var slope_angle = atan2(h_front - h_back, seg_length)

		# Deep slab — bulk is hidden below surface, top face is the road
		var segment = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(road_width, 3.0, seg_length * 1.15)
		segment.mesh = box
		segment.material_override = road_mat
		segment.position = Vector3(0, h_mid - 1.4, z_mid)
		segment.rotation.x = slope_angle
		add_child(segment)


func _build_hill_terrain() -> void:
	# Smooth hill terrain — tilted strips following the cosine curve
	var hill_mat = StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.3, 0.6, 0.25)

	var strip_width = 120.0
	var z_steps = 100
	var z_start = HILL_CENTER_Z - HILL_HALF_WIDTH
	var z_end = HILL_CENTER_Z + HILL_HALF_WIDTH
	var z_step_size = (z_end - z_start) / z_steps

	for zi in range(z_steps):
		var z_front = z_start + zi * z_step_size
		var z_back = z_start + (zi + 1) * z_step_size
		var z_mid = (z_front + z_back) / 2.0

		var h_front = get_ground_height(0, z_front)
		var h_back = get_ground_height(0, z_back)
		var h_mid = (h_front + h_back) / 2.0

		if h_mid < 0.05:
			continue

		var slope = atan2(h_front - h_back, z_step_size)

		# Deep slabs — bulk hidden below, top face is visible hill surface
		var half_w = (strip_width / 2.0) - 5.5
		var x_offset = (strip_width / 4.0) + 2.75

		# Left side
		var left_strip = MeshInstance3D.new()
		var left_box = BoxMesh.new()
		left_box.size = Vector3(half_w, 3.0, z_step_size * 1.15)
		left_strip.mesh = left_box
		left_strip.material_override = hill_mat
		left_strip.position = Vector3(-x_offset, h_mid - 1.4, z_mid)
		left_strip.rotation.x = slope
		add_child(left_strip)

		# Right side
		var right_strip = MeshInstance3D.new()
		var right_box = BoxMesh.new()
		right_box.size = Vector3(half_w, 3.0, z_step_size * 1.15)
		right_strip.mesh = right_box
		right_strip.material_override = hill_mat
		right_strip.position = Vector3(x_offset, h_mid - 1.4, z_mid)
		right_strip.rotation.x = slope
		add_child(right_strip)


func get_ground_height(_x: float, z: float) -> float:
	# Smooth hill using cosine — flat everywhere except the hill zone
	var dist = abs(z - HILL_CENTER_Z)
	if dist >= HILL_HALF_WIDTH:
		return 0.0
	return HILL_HEIGHT * 0.5 * (1.0 + cos(PI * dist / HILL_HALF_WIDTH))


func _spawn_kart() -> void:
	kart = Node3D.new()
	kart.set_script(preload("res://scripts/player_kart.gd"))
	kart.name = "PlayerKart"
	# Start on the flat approach, facing the hill (-Z direction)
	var start_z = 50.0
	kart.position = Vector3(0, 0, start_z)
	add_child(kart)


func _create_speedometer() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	speedometer = Label.new()
	speedometer.name = "Speedometer"
	speedometer.text = "0 km/h"
	speedometer.add_theme_font_size_override("font_size", 28)
	speedometer.add_theme_color_override("font_color", Color.WHITE)
	speedometer.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	speedometer.add_theme_constant_override("shadow_offset_x", 2)
	speedometer.add_theme_constant_override("shadow_offset_y", 2)
	speedometer.position = Vector2(20, 660)
	canvas.add_child(speedometer)


func _create_menu() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "MenuLayer"
	canvas.layer = 10
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	menu_ui = Control.new()
	menu_ui.set_script(preload("res://scripts/menu_ui.gd"))
	menu_ui.name = "MenuUI"
	menu_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(menu_ui)

	menu_ui.connect("drive_pressed", _on_drive_pressed)


func _on_drive_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not get_tree().paused:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if menu_ui:
				menu_ui.show_main_menu()
