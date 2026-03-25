extends Node3D

var kart: Node3D
var speedometer: Label
var menu_ui: Control


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

	# --- Figure-8 dirt road ---
	_build_figure_eight_road()

	# --- Hills ---
	_build_hill(Vector3(40, 0, 30), 12.0, 4.0)
	_build_hill(Vector3(-35, 0, -25), 10.0, 3.0)
	_build_hill(Vector3(20, 0, -40), 8.0, 2.5)


func _build_figure_eight_road() -> void:
	# Two circular loops that cross at the origin
	var road_width = 8.0
	var loop_radius = 30.0
	var segments = 48
	var road_mat = StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.45, 0.35, 0.22)

	# Left loop center and right loop center
	var centers: Array[Vector3] = [Vector3(-loop_radius * 0.6, 0, 0), Vector3(loop_radius * 0.6, 0, 0)]

	for center: Vector3 in centers:
		for i in range(segments):
			var angle = (float(i) / segments) * TAU
			var next_angle = (float(i + 1) / segments) * TAU
			var mid_angle = (angle + next_angle) / 2.0

			var pos: Vector3 = center + Vector3(cos(mid_angle) * loop_radius, 0, sin(mid_angle) * loop_radius)
			var dir: Vector3 = Vector3(-sin(mid_angle), 0, cos(mid_angle))

			var seg_length = (TAU / segments) * loop_radius * 1.05
			var h = _get_ground_height(pos.x, pos.z)

			# Road segment (visual only)
			var segment = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(road_width, 0.05, seg_length)
			segment.mesh = box
			segment.material_override = road_mat
			segment.position = Vector3(pos.x, h + 0.02, pos.z)
			segment.rotation.y = atan2(dir.x, dir.z)
			add_child(segment)

	# Crossover patch at center
	var cross = MeshInstance3D.new()
	var cross_mesh = BoxMesh.new()
	cross_mesh.size = Vector3(road_width * 1.5, 0.05, road_width * 1.5)
	cross.mesh = cross_mesh
	cross.material_override = road_mat
	cross.position = Vector3(0, _get_ground_height(0, 0) + 0.02, 0)
	add_child(cross)


func _build_hill(pos: Vector3, radius: float, height: float) -> void:
	var hill_y = -radius + height

	# Hill (visual only)
	var hill = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius  # half-sphere effect
	hill.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.25)
	hill.material_override = mat
	hill.position = Vector3(pos.x, hill_y, pos.z)
	add_child(hill)


func _get_ground_height(_x: float, _z: float) -> float:
	# Flat ground matching the visual grass plane at y=0
	return 0.0


func _spawn_kart() -> void:
	kart = Node3D.new()
	kart.set_script(preload("res://scripts/player_kart.gd"))
	kart.name = "PlayerKart"
	# Start on the right side of the figure-8
	var start_x = 18.0
	var start_z = 0.0
	var start_y = _get_ground_height(start_x, start_z)
	kart.position = Vector3(start_x, start_y, start_z)
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
