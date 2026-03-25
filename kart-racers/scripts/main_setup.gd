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
	[160.0, 0.0, 9.0, 25.0],
	[-160.0, -40.0, 7.0, 20.0],
]

# Oval road parameters
const OVAL_RX = 120.0
const OVAL_RZ = 80.0
const ROAD_WIDTH = 24.0


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

	# --- Single unified terrain mesh with vertex colors ---
	_build_terrain_mesh()

	# --- Arena walls ---
	_build_walls()


func _build_terrain_mesh() -> void:
	# One mesh for everything — vertex colors distinguish road from grass
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	st.set_material(mat)

	var grass_color = Color(0.25, 0.55, 0.2)
	var road_color = Color(0.45, 0.35, 0.22)

	var extent = ARENA_SIZE + 10.0
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

			var c00 = _get_surface_color(x0, z0, grass_color, road_color)
			var c10 = _get_surface_color(x1, z0, grass_color, road_color)
			var c01 = _get_surface_color(x0, z1, grass_color, road_color)
			var c11 = _get_surface_color(x1, z1, grass_color, road_color)

			# Tri 1
			st.set_color(c00)
			st.add_vertex(v00)
			st.set_color(c10)
			st.add_vertex(v10)
			st.set_color(c01)
			st.add_vertex(v01)

			# Tri 2
			st.set_color(c10)
			st.add_vertex(v10)
			st.set_color(c11)
			st.add_vertex(v11)
			st.set_color(c01)
			st.add_vertex(v01)

	st.generate_normals()
	st.index()

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.name = "Terrain"
	add_child(mesh_inst)


func _get_surface_color(x: float, z: float, grass: Color, road: Color) -> Color:
	# How far is this point from the oval road centerline?
	# Ellipse: (x/RX)^2 + (z/RZ)^2 = 1
	# Normalized distance from ellipse: < 1 inside, > 1 outside, = 1 on it
	var nx = x / OVAL_RX
	var nz = z / OVAL_RZ
	var ellipse_dist = sqrt(nx * nx + nz * nz)

	# Distance from the ellipse curve (in normalized space)
	var dist_from_curve = abs(ellipse_dist - 1.0)

	# Convert to world-space approximate distance
	# The gradient of the ellipse at a point gives the direction to the nearest curve point
	# Approximate: multiply by average radius
	var avg_radius = (OVAL_RX + OVAL_RZ) / 2.0
	var world_dist = dist_from_curve * avg_radius

	var road_half_w = ROAD_WIDTH / 2.0

	if world_dist < road_half_w - 1.5:
		return road
	elif world_dist < road_half_w + 1.5:
		# Smooth blend at road edges
		var t = (world_dist - (road_half_w - 1.5)) / 3.0
		return road.lerp(grass, t)
	else:
		return grass


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
	var start_y = get_ground_height(start_x, start_z) + 0.3
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
