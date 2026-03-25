extends Node3D

var kart: Node3D
var speedometer: Label
var menu_ui: Control

# Arena boundary
const ARENA_SIZE = 200.0

# Hill definitions: [center_x, center_z, height, radius]
const HILLS = [
	[0.0, -50.0, 12.0, 30.0],
	[80.0, 40.0, 8.0, 25.0],
	[-70.0, -30.0, 6.0, 20.0],
	[40.0, -100.0, 10.0, 22.0],
	[-50.0, 70.0, 5.0, 18.0],
]

# Oval road parameters
const OVAL_RX = 120.0
const OVAL_RZ = 80.0
const ROAD_WIDTH = 24.0
const ROAD_SEGMENTS = 400


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

	# --- Terrain mesh (high-res, smooth normals) ---
	_build_terrain_mesh()

	# --- Oval road mesh ---
	_build_oval_road()

	# --- Arena walls ---
	_build_walls()


func _build_terrain_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.55, 0.2)
	st.set_material(mat)

	var extent = ARENA_SIZE + 10.0
	# 200x200 grid = ~2.1m per cell — smooth enough to match the math function
	var steps = 200
	var step_size = (extent * 2.0) / steps

	for zi in range(steps):
		for xi in range(steps):
			var x0 = -extent + xi * step_size
			var x1 = x0 + step_size
			var z0 = -extent + zi * step_size
			var z1 = z0 + step_size

			var v00 = Vector3(x0, get_ground_height(x0, z0), z0)
			var v10 = Vector3(x1, get_ground_height(x1, z0), z0)
			var v01 = Vector3(x0, get_ground_height(x0, z1), z1)
			var v11 = Vector3(x1, get_ground_height(x1, z1), z1)

			# Tri 1
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v01)

			# Tri 2
			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v01)

	# Generate smooth normals and deduplicate vertices
	st.generate_normals()
	st.index()

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.name = "Terrain"
	add_child(mesh_inst)


func _build_oval_road() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.35, 0.22)
	st.set_material(mat)

	var road_half_w = ROAD_WIDTH / 2.0
	# Road sits clearly above terrain — 0.5 prevents grass bleed on steep slopes
	var road_lift = 0.5

	for i in range(ROAD_SEGMENTS):
		var t0 = (float(i) / ROAD_SEGMENTS) * TAU
		var t1 = (float(i + 1) / ROAD_SEGMENTS) * TAU

		var cx0 = cos(t0) * OVAL_RX
		var cz0 = sin(t0) * OVAL_RZ
		var cx1 = cos(t1) * OVAL_RX
		var cz1 = sin(t1) * OVAL_RZ

		# Normal perpendicular to tangent
		var tx0 = -sin(t0) * OVAL_RX
		var tz0 = cos(t0) * OVAL_RZ
		var len0 = sqrt(tx0 * tx0 + tz0 * tz0)
		var nx0 = tz0 / len0
		var nz0 = -tx0 / len0

		var tx1 = -sin(t1) * OVAL_RX
		var tz1 = cos(t1) * OVAL_RZ
		var len1 = sqrt(tx1 * tx1 + tz1 * tz1)
		var nx1 = tz1 / len1
		var nz1 = -tx1 / len1

		var lx0 = cx0 - nx0 * road_half_w
		var lz0 = cz0 - nz0 * road_half_w
		var rx0 = cx0 + nx0 * road_half_w
		var rz0 = cz0 + nz0 * road_half_w

		var lx1 = cx1 - nx1 * road_half_w
		var lz1 = cz1 - nz1 * road_half_w
		var rx1 = cx1 + nx1 * road_half_w
		var rz1 = cz1 + nz1 * road_half_w

		# Sample height at each road edge point
		var y_l0 = get_ground_height(lx0, lz0) + road_lift
		var y_r0 = get_ground_height(rx0, rz0) + road_lift
		var y_l1 = get_ground_height(lx1, lz1) + road_lift
		var y_r1 = get_ground_height(rx1, rz1) + road_lift

		var v_l0 = Vector3(lx0, y_l0, lz0)
		var v_r0 = Vector3(rx0, y_r0, rz0)
		var v_l1 = Vector3(lx1, y_l1, lz1)
		var v_r1 = Vector3(rx1, y_r1, rz1)

		st.add_vertex(v_l0)
		st.add_vertex(v_r0)
		st.add_vertex(v_l1)

		st.add_vertex(v_r0)
		st.add_vertex(v_r1)
		st.add_vertex(v_l1)

	st.generate_normals()
	st.index()

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.name = "Road"
	add_child(mesh_inst)


func _build_walls() -> void:
	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.35, 0.35, 0.38)
	wall_mat.roughness = 0.9

	var wall_height = 15.0
	var wall_thickness = 3.0
	var s = ARENA_SIZE

	var walls = [
		[Vector3(0, wall_height / 2.0, -s), Vector3(s * 2.0 + wall_thickness * 2, wall_height, wall_thickness)],
		[Vector3(0, wall_height / 2.0, s), Vector3(s * 2.0 + wall_thickness * 2, wall_height, wall_thickness)],
		[Vector3(-s, wall_height / 2.0, 0), Vector3(wall_thickness, wall_height, s * 2.0)],
		[Vector3(s, wall_height / 2.0, 0), Vector3(wall_thickness, wall_height, s * 2.0)],
	]

	for w in walls:
		var wall = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = w[1]
		wall.mesh = box
		wall.material_override = wall_mat
		wall.position = w[0]
		add_child(wall)


func get_ground_height(x: float, z: float) -> float:
	var h = 0.0
	for hill in HILLS:
		var dx = x - hill[0]
		var dz = z - hill[1]
		var dist = sqrt(dx * dx + dz * dz)
		if dist < hill[3]:
			h += hill[2] * 0.5 * (1.0 + cos(PI * dist / hill[3]))
	return h


func _spawn_kart() -> void:
	kart = Node3D.new()
	kart.set_script(preload("res://scripts/player_kart.gd"))
	kart.name = "PlayerKart"
	var start_x = OVAL_RX
	var start_z = 0.0
	var start_y = get_ground_height(start_x, start_z)
	kart.position = Vector3(start_x, start_y, start_z)
	kart.rotation.y = PI
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
