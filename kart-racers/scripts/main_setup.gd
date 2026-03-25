extends Node3D

var karts: Array = []
var speedometers: Array = []
var lap_labels: Array = []
var oil_labels: Array = []
var menu_ui: Control
var player_count: int = 1
var split_containers: Array = []
var hud_nodes: Array = []
var oil_spills: Array = []

# Countdown state
var countdown_active: bool = false
var countdown_timer: float = 0.0
var countdown_phase: int = 0  # 0=wait, 1=red1, 2=red2, 3=green
var countdown_label: Label
var countdown_canvas: CanvasLayer
var gas_pressed_during_countdown: Dictionary = {}  # player_id -> when they pressed gas

const ARENA_SIZE = 200.0

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
	world_node = Node3D.new()
	world_node.name = "World"
	add_child(world_node)
	_build_world()
	_create_menu()
	get_tree().paused = true


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	# --- Countdown logic ---
	if countdown_active:
		countdown_timer += delta
		_update_countdown()
		# Check if players press gas during countdown (for turbo start)
		for kart in karts:
			var device = kart.player_id
			var gas = false
			if kart.player_id == 0 and Input.is_action_pressed("accelerate"):
				gas = true
			if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
				gas = true
			if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.3:
				gas = true
			if gas and kart.player_id not in gas_pressed_during_countdown:
				gas_pressed_during_countdown[kart.player_id] = countdown_timer
		return

	# --- Normal game HUD ---
	for i in range(karts.size()):
		if karts[i] and i < speedometers.size() and speedometers[i]:
			var spd = abs(karts[i].speed)
			speedometers[i].text = "%d km/h" % int(spd * 3.6)
		if karts[i] and i < lap_labels.size() and lap_labels[i]:
			lap_labels[i].text = "Lap %d" % karts[i].lap_count
		if karts[i] and i < oil_labels.size() and oil_labels[i]:
			oil_labels[i].text = "Oil: %d" % karts[i].oil_count

	_check_oil_collisions()
	_check_truck_collisions()


func _start_countdown() -> void:
	countdown_active = true
	countdown_timer = 0.0
	countdown_phase = 0
	gas_pressed_during_countdown.clear()

	# Countdown UI
	countdown_canvas = CanvasLayer.new()
	countdown_canvas.name = "CountdownLayer"
	countdown_canvas.layer = 8
	add_child(countdown_canvas)

	countdown_label = Label.new()
	countdown_label.text = ""
	countdown_label.add_theme_font_size_override("font_size", 72)
	countdown_label.add_theme_color_override("font_color", Color.RED)
	countdown_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	countdown_label.add_theme_constant_override("shadow_offset_x", 3)
	countdown_label.add_theme_constant_override("shadow_offset_y", 3)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	countdown_label.custom_minimum_size = Vector2(400, 100)
	countdown_canvas.add_child(countdown_label)

	# Block all kart input
	for kart in karts:
		kart.race_started = false


func _update_countdown() -> void:
	# Timeline: 0-1s = red, 1-2s = red, 2-3s = GREEN + GO!
	var old_phase = countdown_phase

	if countdown_timer < 1.0:
		countdown_phase = 1
		countdown_label.text = "3"
		countdown_label.add_theme_color_override("font_color", Color.RED)
	elif countdown_timer < 2.0:
		countdown_phase = 2
		countdown_label.text = "2"
		countdown_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	elif countdown_timer < 3.0:
		if countdown_phase < 3:
			countdown_phase = 3
			countdown_label.text = "GO!"
			countdown_label.add_theme_color_override("font_color", Color.GREEN)

			# Race starts — check for turbo start
			# Sweet spot: pressed gas between 1.8 and 2.2 (just before green)
			for kart in karts:
				kart.race_started = true
				var pid = kart.player_id
				if pid in gas_pressed_during_countdown:
					var press_time = gas_pressed_during_countdown[pid]
					if press_time >= 1.6 and press_time <= 2.3:
						# Perfect turbo start!
						kart.turbo_start()
					elif press_time < 1.6:
						# Pressed too early — stall/spin out
						kart.start_spinout()
	else:
		# Countdown done — remove UI
		countdown_active = false
		if countdown_canvas:
			countdown_canvas.queue_free()
			countdown_canvas = null


func _build_world() -> void:
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

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world_node.add_child(sun)

	_build_terrain_mesh()
	_build_walls()
	_build_start_finish_line()


func _start_game(num_players: int) -> void:
	player_count = num_players

	for k in karts:
		if k and k.get_parent():
			k.get_parent().remove_child(k)
			k.queue_free()
	karts.clear()
	speedometers.clear()
	lap_labels.clear()
	oil_labels.clear()

	for sc in split_containers:
		if sc and sc.get_parent():
			sc.get_parent().remove_child(sc)
			sc.queue_free()
	split_containers.clear()

	for h in hud_nodes:
		if h and h.get_parent():
			h.get_parent().remove_child(h)
			h.queue_free()
	hud_nodes.clear()

	# Clear oil spills
	for oil in oil_spills:
		if oil and oil.get_parent():
			oil.get_parent().remove_child(oil)
			oil.queue_free()
	oil_spills.clear()

	if player_count == 1:
		_start_single_player()
	else:
		_start_split_screen()

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Start the countdown
	_start_countdown()


func _start_single_player() -> void:
	var kart = _create_kart(0, Color(0.2, 0.35, 0.8))
	kart.position = Vector3(OVAL_RX, get_ground_height(OVAL_RX, 0) + 0.5, -5)
	kart.rotation.y = PI
	world_node.add_child(kart)
	kart.camera.current = true
	karts.append(kart)
	kart.connect("lap_completed", _on_lap_completed)
	kart.connect("drop_oil", _on_drop_oil)

	var canvas = CanvasLayer.new()
	canvas.name = "HUD_P1"
	add_child(canvas)
	hud_nodes.append(canvas)

	var speedo = _make_speedometer(Vector2(20, 660))
	canvas.add_child(speedo)
	speedometers.append(speedo)

	var lap_label = _make_lap_label(Vector2(20, 20))
	canvas.add_child(lap_label)
	lap_labels.append(lap_label)

	var oil_label = _make_oil_label(Vector2(20, 55))
	canvas.add_child(oil_label)
	oil_labels.append(oil_label)


func _start_split_screen() -> void:
	var win_size = get_viewport().get_visible_rect().size
	var screen_w = int(win_size.x)
	var half_h = int(win_size.y / 2)

	# Use a Control node as root for split containers (fills window)
	var root_control = Control.new()
	root_control.name = "SplitRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	hud_nodes.append(root_control)

	var colors = [Color(0.2, 0.35, 0.8), Color(0.8, 0.2, 0.2)]
	var start_positions = [
		Vector3(OVAL_RX, get_ground_height(OVAL_RX, 0) + 0.5, -5),
		Vector3(OVAL_RX, get_ground_height(OVAL_RX, 0) + 0.5, 5),
	]

	for i in range(2):
		var kart = _create_kart(i, colors[i])
		kart.position = start_positions[i]
		kart.rotation.y = PI
		world_node.add_child(kart)
		kart.camera.current = false
		karts.append(kart)
		kart.connect("lap_completed", _on_lap_completed)
		kart.connect("drop_oil", _on_drop_oil)

		var container = SubViewportContainer.new()
		container.name = "VP_P%d" % (i + 1)
		container.position = Vector2(0, i * half_h)
		container.size = Vector2(screen_w, half_h)
		container.stretch = true
		root_control.add_child(container)
		split_containers.append(container)

		var viewport = SubViewport.new()
		viewport.name = "Viewport_P%d" % (i + 1)
		viewport.size = Vector2i(screen_w, half_h)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_3d = get_viewport().world_3d
		container.add_child(viewport)

		var cam = Camera3D.new()
		cam.name = "ViewportCam_P%d" % (i + 1)
		cam.current = true
		viewport.add_child(cam)

	# HUD overlay
	var hud_canvas = CanvasLayer.new()
	hud_canvas.name = "SplitHUD"
	hud_canvas.layer = 5
	add_child(hud_canvas)
	hud_nodes.append(hud_canvas)

	# P1 HUD (top)
	speedometers.append(_make_speedometer(Vector2(20, half_h - 40)))
	hud_canvas.add_child(speedometers[0])
	lap_labels.append(_make_lap_label(Vector2(20, 10)))
	hud_canvas.add_child(lap_labels[0])
	oil_labels.append(_make_oil_label(Vector2(20, 45)))
	hud_canvas.add_child(oil_labels[0])

	# P2 HUD (bottom)
	speedometers.append(_make_speedometer(Vector2(20, half_h * 2 - 40)))
	hud_canvas.add_child(speedometers[1])
	lap_labels.append(_make_lap_label(Vector2(20, half_h + 10)))
	hud_canvas.add_child(lap_labels[1])
	oil_labels.append(_make_oil_label(Vector2(20, half_h + 45)))
	hud_canvas.add_child(oil_labels[1])

	# Divider
	var divider = ColorRect.new()
	divider.color = Color(0.3, 0.3, 0.3)
	divider.position = Vector2(0, half_h - 2)
	divider.size = Vector2(screen_w, 4)
	hud_canvas.add_child(divider)


func _physics_process(_delta: float) -> void:
	if player_count == 2:
		for i in range(min(karts.size(), split_containers.size())):
			var kart = karts[i]
			var container = split_containers[i]
			if kart and container:
				var viewport = container.get_child(0) as SubViewport
				if viewport and viewport.get_child_count() > 0:
					var cam = viewport.get_child(0) as Camera3D
					if cam:
						var offset = kart.transform.basis * Vector3(0, 5.5, 10)
						cam.global_position = kart.global_position + offset
						cam.look_at(kart.global_position + Vector3(0, 2, 0))


# === OIL SPILLS ===

func _on_drop_oil(_pid: int, pos: Vector3) -> void:
	# Place oil ON the terrain surface
	var terrain_y = get_ground_height(pos.x, pos.z)
	var oil = MeshInstance3D.new()
	oil.name = "OilSpill"
	var cyl = CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.0
	cyl.height = 0.05
	oil.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.08, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.8
	oil.material_override = mat
	oil.position = Vector3(pos.x, terrain_y + 0.15, pos.z)
	world_node.add_child(oil)
	oil_spills.append(oil)


func _check_oil_collisions() -> void:
	# Oil affects ALL players (including the one who placed it)
	var to_remove: Array = []
	for oil in oil_spills:
		if not oil or not is_instance_valid(oil):
			continue
		var oil_pos = oil.global_position
		for kart in karts:
			if not kart or kart.is_spinning_out:
				continue
			var dist = Vector2(kart.global_position.x - oil_pos.x, kart.global_position.z - oil_pos.z).length()
			if dist < 3.5:
				kart.start_spinout()
				# Oil is consumed on hit
				to_remove.append(oil)
				break
	for oil in to_remove:
		oil_spills.erase(oil)
		oil.queue_free()


func _check_truck_collisions() -> void:
	# Trucks push each other — can't drive through
	if karts.size() < 2:
		return
	for i in range(karts.size()):
		for j in range(i + 1, karts.size()):
			var a = karts[i]
			var b = karts[j]
			if not a or not b:
				continue
			var diff = Vector3(a.global_position.x - b.global_position.x, 0, a.global_position.z - b.global_position.z)
			var dist = diff.length()
			var push_radius = 3.5  # truck diameter
			if dist < push_radius and dist > 0.01:
				var push_dir = diff.normalized()
				var overlap = push_radius - dist
				var push_force = overlap * 0.5
				# Push both trucks apart
				a.global_position.x += push_dir.x * push_force
				a.global_position.z += push_dir.z * push_force
				b.global_position.x -= push_dir.x * push_force
				b.global_position.z -= push_dir.z * push_force
				# Transfer some speed on impact
				var speed_transfer = (a.speed - b.speed) * 0.15
				a.speed -= speed_transfer
				b.speed += speed_transfer


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


func _build_start_finish_line() -> void:
	# Finish line spans the full road width, perpendicular to the road
	# At x=OVAL_RX, z=0, the road runs in the Z direction (tangent to oval)
	# So the line goes across X (perpendicular to road direction)
	var center_x = OVAL_RX
	var line_y = get_ground_height(center_x, 0) + 0.2
	var line_width = ROAD_WIDTH + 2.0  # slightly wider than road
	var checks = 12
	var check_w = line_width / checks

	for i in range(checks):
		var checker = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(check_w * 0.98, 0.05, 3.0)
		checker.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.WHITE if i % 2 == 0 else Color(0.1, 0.1, 0.1)
		checker.material_override = mat
		# Center the line on the road
		var x_pos = center_x - line_width / 2.0 + check_w * (i + 0.5)
		checker.position = Vector3(x_pos, line_y, 0)
		world_node.add_child(checker)


func get_ground_height(x: float, z: float) -> float:
	var h = 0.0
	for hill in HILLS:
		var dx = x - hill[0]
		var dz = z - hill[1]
		var dist = sqrt(dx * dx + dz * dz)
		if dist < hill[3]:
			h += hill[2] * 0.5 * (1.0 + cos(PI * dist / hill[3]))
	return h


func _on_lap_completed(_pid: int, _lap: int) -> void:
	pass  # HUD updates in _process


func _make_speedometer(pos: Vector2) -> Label:
	var label = Label.new()
	label.text = "0 km/h"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = pos
	return label


func _make_lap_label(pos: Vector2) -> Label:
	var label = Label.new()
	label.text = "Lap 0"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = pos
	return label


func _make_oil_label(pos: Vector2) -> Label:
	var label = Label.new()
	label.text = "Oil: 2"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
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
