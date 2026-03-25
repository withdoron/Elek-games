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

	# --- Ground terrain (one smooth mesh covering everything) ---
	_build_terrain_mesh()

	# --- Road (smooth mesh on top of terrain) ---
	_build_road_mesh()


func _build_terrain_mesh() -> void:
	# Build a single smooth mesh for the entire ground using SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.55, 0.2)
	st.set_material(mat)

	var x_min = -150.0
	var x_max = 150.0
	var z_min = -130.0
	var z_max = 80.0
	var x_steps = 60
	var z_steps = 80

	var x_step = (x_max - x_min) / x_steps
	var z_step = (z_max - z_min) / z_steps

	for zi in range(z_steps):
		for xi in range(x_steps):
			var x0 = x_min + xi * x_step
			var x1 = x0 + x_step
			var z0 = z_min + zi * z_step
			var z1 = z0 + z_step

			var y00 = get_ground_height(x0, z0)
			var y10 = get_ground_height(x1, z0)
			var y01 = get_ground_height(x0, z1)
			var y11 = get_ground_height(x1, z1)

			var v00 = Vector3(x0, y00, z0)
			var v10 = Vector3(x1, y10, z0)
			var v01 = Vector3(x0, y01, z1)
			var v11 = Vector3(x1, y11, z1)

			# Triangle 1
			st.set_normal(_calc_normal(v00, v10, v01))
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v01)

			# Triangle 2
			st.set_normal(_calc_normal(v10, v11, v01))
			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v01)

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.name = "Terrain"
	add_child(mesh_inst)


func _build_road_mesh() -> void:
	# Build a smooth road strip using SurfaceTool — sits slightly above terrain
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.35, 0.22)
	st.set_material(mat)

	var road_half_w = 5.0
	var z_min = -130.0
	var z_max = 80.0
	var z_steps = 200
	var z_step = (z_max - z_min) / z_steps
	var road_lift = 0.05  # just enough above terrain to prevent z-fighting

	for zi in range(z_steps):
		var z0 = z_min + zi * z_step
		var z1 = z0 + z_step

		var y0 = get_ground_height(0, z0) + road_lift
		var y1 = get_ground_height(0, z1) + road_lift

		var v_l0 = Vector3(-road_half_w, y0, z0)
		var v_r0 = Vector3(road_half_w, y0, z0)
		var v_l1 = Vector3(-road_half_w, y1, z1)
		var v_r1 = Vector3(road_half_w, y1, z1)

		# Triangle 1
		st.set_normal(_calc_normal(v_l0, v_r0, v_l1))
		st.add_vertex(v_l0)
		st.add_vertex(v_r0)
		st.add_vertex(v_l1)

		# Triangle 2
		st.set_normal(_calc_normal(v_r0, v_r1, v_l1))
		st.add_vertex(v_r0)
		st.add_vertex(v_r1)
		st.add_vertex(v_l1)

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.name = "Road"
	add_child(mesh_inst)


func _calc_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()


func get_ground_height(_x: float, z: float) -> float:
	var dist = abs(z - HILL_CENTER_Z)
	if dist >= HILL_HALF_WIDTH:
		return 0.0
	return HILL_HEIGHT * 0.5 * (1.0 + cos(PI * dist / HILL_HALF_WIDTH))


func _spawn_kart() -> void:
	kart = Node3D.new()
	kart.set_script(preload("res://scripts/player_kart.gd"))
	kart.name = "PlayerKart"
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
