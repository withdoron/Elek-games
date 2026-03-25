extends Node3D

var karts: Array = []
var speedometers: Array = []
var menu_ui: Control
var player_count: int = 1
var split_containers: Array = []

const ARENA_SIZE = 200.0

# Bigger hills — 50-80% taller with wider radii
const HILLS = [
	[0.0, -50.0, 20.0, 40.0],
	[80.0, 40.0, 14.0, 35.0],
	[-70.0, -30.0, 10.0, 28.0],
	[40.0, -100.0, 16.0, 30.0],
	[-50.0, 70.0, 8.0, 25.0],
	[160.0, 0.0, 15.0, 35.0],
	[-160.0, -40.0, 12.0, 28.0],
]

const OVAL_RX = 120.0
const OVAL_RZ = 80.0
const ROAD_WIDTH = 24.0

var world_node: Node3D


func _ready() -> void:
	# Build the world in a shared node
	world_node = Node3D.new()
	world_node.name = "World"
	add_child(world_node)
	_build_world()
	_create_menu()
	get_tree().paused = true


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	for i in range(karts.size()):
		if karts[i] and i < speedometers.size() and speedometers[i]:
			var spd = abs(karts[i].speed)
			speedometers[i].text = "%d km/h" % int(spd * 3.6)


func _build_world() -> void:
	# Sky
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
	world_node.add_child(env)

	# Sun
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world_node.add_child(sun)

	# Terrain
	_build_terrain_mesh()

	# Walls
	_build_walls()


func _start_game(num_players: int) -> void:
	player_count = num_players

	# Clean up any existing karts and viewports
	for k in karts:
		if k and k.get_parent():
			k.get_parent().remove_child(k)
			k.queue_free()
	karts.clear()
	speedometers.clear()

	for sc in split_containers:
		if sc and sc.get_parent():
			sc.get_parent().remove_child(sc)
			sc.queue_free()
	split_containers.clear()

	if player_count == 1:
		_start_single_player()
	else:
		_start_split_screen()

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _start_single_player() -> void:
	var kart = _create_kart(0, Color(0.2, 0.35, 0.8))
	kart.position = Vector3(OVAL_RX, get_ground_height(OVAL_RX, 0) + 0.5, 0)
	kart.rotation.y = PI
	world_node.add_child(kart)
	kart.camera.current = true
	karts.append(kart)

	# HUD
	var canvas = CanvasLayer.new()
	canvas.name = "HUD_P1"
	add_child(canvas)
	var speedo = _make_speedometer(Vector2(20, 660))
	canvas.add_child(speedo)
	speedometers.append(speedo)


func _start_split_screen() -> void:
	# Top/bottom split using SubViewportContainers
	var canvas = CanvasLayer.new()
	canvas.name = "SplitScreenLayer"
	canvas.layer = 0
	add_child(canvas)

	var colors = [Color(0.2, 0.35, 0.8), Color(0.8, 0.2, 0.2)]
	var start_positions = [
		Vector3(OVAL_RX, get_ground_height(OVAL_RX, 0) + 0.5, 0),
		Vector3(-OVAL_RX, get_ground_height(-OVAL_RX, 0) + 0.5, 0),
	]
	var start_rotations = [PI, 0.0]

	for i in range(2):
		# Create kart in the world
		var kart = _create_kart(i, colors[i])
		kart.position = start_positions[i]
		kart.rotation.y = start_rotations[i]
		world_node.add_child(kart)
		kart.camera.current = false  # viewports handle cameras
		karts.append(kart)

		# SubViewportContainer
		var container = SubViewportContainer.new()
		container.name = "ViewportContainer_P%d" % (i + 1)
		container.position = Vector2(0, i * 360)
		container.size = Vector2(1280, 360)
		container.stretch = true
		canvas.add_child(container)
		split_containers.append(container)

		# SubViewport
		var viewport = SubViewport.new()
		viewport.name = "Viewport_P%d" % (i + 1)
		viewport.size = Vector2i(1280, 360)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_3d = get_viewport().world_3d  # share the world
		container.add_child(viewport)

		# Camera inside the viewport that follows the kart
		var cam = Camera3D.new()
		cam.name = "ViewportCam_P%d" % (i + 1)
		cam.current = true
		viewport.add_child(cam)

		# Speedometer overlay per viewport
		var speedo_label = _make_speedometer(Vector2(10, 310))
		viewport.add_child(speedo_label)
		# Actually speedometer needs to be in a CanvasLayer inside the viewport
		# Let's use a simple label positioned in screen space
		speedometers.append(speedo_label)

	# Start a process to update viewport cameras to follow karts
	set_process(true)


func _physics_process(_delta: float) -> void:
	# Update viewport cameras to follow their karts
	if player_count == 2:
		for i in range(min(karts.size(), split_containers.size())):
			var kart = karts[i]
			var container = split_containers[i]
			if kart and container:
				var viewport = container.get_child(0) as SubViewport
				if viewport and viewport.get_child_count() > 0:
					var cam = viewport.get_child(0) as Camera3D
					if cam:
						# Follow kart — same offset as chase camera
						var offset = kart.transform.basis * Vector3(0, 5.5, 10)
						cam.global_position = kart.global_position + offset
						cam.look_at(kart.global_position + Vector3(0, 2, 0))


func _create_kart(id: int, color: Color) -> Node3D:
	var kart = Node3D.new()
	kart.set_script(preload("res://scripts/player_kart.gd"))
	kart.name = "Kart_P%d" % (id + 1)
	kart.set("player_id", id)
	kart.set("truck_color", color)
	return kart


func _build_terrain_mesh() -> void:
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

			st.set_color(c00)
			st.add_vertex(v00)
			st.set_color(c10)
			st.add_vertex(v10)
			st.set_color(c01)
			st.add_vertex(v01)

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
	world_node.add_child(mesh_inst)


func _get_surface_color(x: float, z: float, grass: Color, road: Color) -> Color:
	var nx = x / OVAL_RX
	var nz = z / OVAL_RZ
	var ellipse_dist = sqrt(nx * nx + nz * nz)
	var dist_from_curve = abs(ellipse_dist - 1.0)
	var avg_radius = (OVAL_RX + OVAL_RZ) / 2.0
	var world_dist = dist_from_curve * avg_radius
	var road_half_w = ROAD_WIDTH / 2.0

	if world_dist < road_half_w - 1.5:
		return road
	elif world_dist < road_half_w + 1.5:
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
		world_node.add_child(wall)


func get_ground_height(x: float, z: float) -> float:
	var h = 0.0
	for hill in HILLS:
		var dx = x - hill[0]
		var dz = z - hill[1]
		var dist = sqrt(dx * dx + dz * dz)
		if dist < hill[3]:
			h += hill[2] * 0.5 * (1.0 + cos(PI * dist / hill[3]))
	return h


func _make_speedometer(pos: Vector2) -> Label:
	var label = Label.new()
	label.name = "Speedometer"
	label.text = "0 km/h"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = pos
	return label


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

	menu_ui.connect("drive_pressed", _on_drive_1p)
	menu_ui.connect("drive_2p_pressed", _on_drive_2p)


func _on_drive_1p() -> void:
	menu_ui.visible = false
	_start_game(1)


func _on_drive_2p() -> void:
	menu_ui.visible = false
	_start_game(2)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not get_tree().paused:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if menu_ui:
				menu_ui.show_main_menu()
