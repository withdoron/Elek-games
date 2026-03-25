extends Node3D

var karts: Array = []
var speedometers: Array = []
var lap_labels: Array = []
var item_labels: Array = []
var menu_ui: Control
var player_count: int = 1
var split_containers: Array = []
var hud_nodes: Array = []
var oil_spills: Array = []  # dropped oil spots
var missiles: Array = []    # active homing missiles
var mystery_boxes: Array = []  # item box meshes on the track

# Countdown
var countdown_active: bool = false
var countdown_timer: float = 0.0
var countdown_phase: int = 0
var countdown_label: Label
var countdown_canvas: CanvasLayer
var gas_pressed_during_countdown: Dictionary = {}
var race_finished: bool = false
var winner_id: int = -1
const LAPS_TO_WIN = 3

# 3x bigger track
const ARENA_SIZE = 600.0
const OVAL_RX = 360.0
const OVAL_RZ = 240.0
const ROAD_WIDTH = 48.0
const MOUNTAIN_RADIUS = 150.0
const MOUNTAIN_HEIGHT = 540.0  # 9x taller — impossibly steep

const HILLS = [
	[250.0, 120.0, 20.0, 50.0],
	[-200.0, -100.0, 16.0, 45.0],
	[100.0, -250.0, 14.0, 40.0],
	[-300.0, 50.0, 18.0, 50.0],
	[400.0, -50.0, 12.0, 35.0],
	[-150.0, 200.0, 10.0, 30.0],
	[50.0, 300.0, 15.0, 40.0],
]

const BOULDERS = [
	[340.0, -120.0, 6.0],
	[-350.0, 80.0, 7.0],
	[200.0, 220.0, 5.0],
	[-100.0, -230.0, 6.0],
	[380.0, 100.0, 5.0],
	[-280.0, -180.0, 7.0],
	[360.0, -30.0, 5.0],
	[-360.0, -60.0, 6.0],
	[150.0, -240.0, 5.0],
	[-250.0, 160.0, 6.0],
	[300.0, 200.0, 5.0],
	[-180.0, -200.0, 7.0],
	[50.0, 240.0, 5.0],
	[-320.0, -120.0, 6.0],
]

const MUD_ZONES = [
	[340.0, -120.0, 30.0],
	[-350.0, 80.0, 35.0],
	[200.0, 220.0, 28.0],
	[-100.0, -230.0, 32.0],
	[380.0, 100.0, 28.0],
	[-280.0, -180.0, 35.0],
	[360.0, -30.0, 25.0],
	[-360.0, -60.0, 30.0],
	[150.0, -240.0, 25.0],
	[-250.0, 160.0, 28.0],
	[300.0, 200.0, 25.0],
	[-180.0, -200.0, 30.0],
	[50.0, 240.0, 25.0],
	[-320.0, -120.0, 28.0],
]

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

	if countdown_active:
		countdown_timer += delta
		_update_countdown()
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

	if race_finished:
		return

	for i in range(karts.size()):
		if karts[i] and i < speedometers.size() and speedometers[i]:
			speedometers[i].text = "%d km/h" % int(abs(karts[i].speed) * 3.6)
		if karts[i] and i < lap_labels.size() and lap_labels[i]:
			lap_labels[i].text = "Lap %d/%d" % [karts[i].lap_count, LAPS_TO_WIN]
		if karts[i] and i < item_labels.size() and item_labels[i]:
			var item_name = karts[i].held_item if karts[i].held_item != "" else "---"
			item_labels[i].text = "Item: %s" % item_name.to_upper()

		# Check win condition
		if karts[i] and karts[i].lap_count >= LAPS_TO_WIN and not race_finished:
			race_finished = true
			winner_id = i
			_show_winner(i)

	_check_oil_collisions()
	_check_truck_collisions()
	_check_mystery_box_collisions(delta)
	_update_missiles(delta)


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
	_build_boulders()
	_build_mystery_boxes()


# === COUNTDOWN ===

func _start_countdown() -> void:
	countdown_active = true
	countdown_timer = 0.0
	countdown_phase = 0
	gas_pressed_during_countdown.clear()

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

	for kart in karts:
		kart.race_started = false


func _update_countdown() -> void:
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
			for kart in karts:
				kart.race_started = true
				var pid = kart.player_id
				if pid in gas_pressed_during_countdown:
					var press_time = gas_pressed_during_countdown[pid]
					if press_time >= 1.6 and press_time <= 2.3:
						kart.turbo_start()
					elif press_time < 1.6:
						kart.start_spinout()
	else:
		countdown_active = false
		if countdown_canvas:
			countdown_canvas.queue_free()
			countdown_canvas = null


# === GAME START ===

func _start_game(num_players: int) -> void:
	player_count = num_players
	race_finished = false
	winner_id = -1

	for k in karts:
		if k and k.get_parent():
			k.get_parent().remove_child(k)
			k.queue_free()
	karts.clear()
	speedometers.clear()
	lap_labels.clear()
	item_labels.clear()

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

	for oil in oil_spills:
		if oil and oil.get_parent():
			oil.get_parent().remove_child(oil)
			oil.queue_free()
	oil_spills.clear()
	for m in missiles:
		if m and m.get_parent():
			m.get_parent().remove_child(m)
			m.queue_free()
	missiles.clear()

	if player_count == 1:
		_start_single_player()
	else:
		_start_split_screen()

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_start_countdown()


func _start_single_player() -> void:
	var kart = _create_kart(0, Color(0.2, 0.35, 0.8))
	kart.position = Vector3(OVAL_RX, get_ground_height(OVAL_RX, 0) + 0.5, -5)
	kart.rotation.y = PI
	world_node.add_child(kart)
	kart.camera.current = true
	karts.append(kart)
	kart.connect("lap_completed", _on_lap_completed)
	kart.connect("use_item", _on_use_item)

	var canvas = CanvasLayer.new()
	canvas.name = "HUD_P1"
	add_child(canvas)
	hud_nodes.append(canvas)

	var speedo = _make_label(Vector2(20, 660), 24, Color.WHITE, "0 km/h")
	canvas.add_child(speedo)
	speedometers.append(speedo)
	var lap = _make_label(Vector2(20, 20), 28, Color(1.0, 0.85, 0.3), "Lap 0/3")
	canvas.add_child(lap)
	lap_labels.append(lap)
	var item = _make_label(Vector2(20, 55), 20, Color(0.7, 0.7, 0.8), "Item: ---")
	canvas.add_child(item)
	item_labels.append(item)


func _start_split_screen() -> void:
	var win_size = get_viewport().get_visible_rect().size
	var screen_w = int(win_size.x)
	var half_h = int(win_size.y / 2)

	var root_control = Control.new()
	root_control.name = "SplitRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	hud_nodes.append(root_control)

	var colors = [Color(0.2, 0.35, 0.8), Color(0.8, 0.2, 0.2)]
	var offsets = [-8, 8]

	for i in range(2):
		var kart = _create_kart(i, colors[i])
		kart.position = Vector3(OVAL_RX, get_ground_height(OVAL_RX, 0) + 0.5, offsets[i])
		kart.rotation.y = PI
		world_node.add_child(kart)
		kart.camera.current = false
		karts.append(kart)
		kart.connect("lap_completed", _on_lap_completed)
		kart.connect("use_item", _on_use_item)

		var container = SubViewportContainer.new()
		container.position = Vector2(0, i * half_h)
		container.size = Vector2(screen_w, half_h)
		container.stretch = true
		root_control.add_child(container)
		split_containers.append(container)

		var viewport = SubViewport.new()
		viewport.size = Vector2i(screen_w, half_h)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_3d = get_viewport().world_3d
		container.add_child(viewport)

		var cam = Camera3D.new()
		cam.current = true
		viewport.add_child(cam)

	var hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	hud_nodes.append(hud)

	for i in range(2):
		var y_base = i * half_h
		speedometers.append(_make_label(Vector2(20, y_base + half_h - 40), 24, Color.WHITE, "0 km/h"))
		hud.add_child(speedometers[i])
		lap_labels.append(_make_label(Vector2(20, y_base + 10), 28, Color(1.0, 0.85, 0.3), "Lap 0/3"))
		hud.add_child(lap_labels[i])
		item_labels.append(_make_label(Vector2(20, y_base + 45), 20, Color(0.7, 0.7, 0.8), "Item: ---"))
		hud.add_child(item_labels[i])

	var div = ColorRect.new()
	div.color = Color(0.3, 0.3, 0.3)
	div.position = Vector2(0, half_h - 2)
	div.size = Vector2(screen_w, 4)
	hud.add_child(div)


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


# === COLLISIONS ===

func _on_use_item(pid: int, item: String, pos: Vector3, fwd: Vector3) -> void:
	if item == "oil":
		# Drop oil behind truck
		var drop = pos + fwd * -4.0  # behind
		var ty = get_ground_height(drop.x, drop.z)
		var oil = MeshInstance3D.new()
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
		oil.position = Vector3(drop.x, ty + 0.15, drop.z)
		world_node.add_child(oil)
		oil_spills.append(oil)

	elif item == "missile":
		# Fire a homing missile forward
		var missile = MeshInstance3D.new()
		missile.name = "Missile"
		var box = BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 1.5)
		missile.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.1, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.1)
		mat.emission_energy_multiplier = 2.0
		missile.material_override = mat
		missile.position = pos + fwd * 3.0 + Vector3(0, 1.5, 0)
		missile.set_meta("owner_id", pid)
		missile.set_meta("velocity", fwd * 80.0)  # fast
		missile.set_meta("lifetime", 5.0)
		world_node.add_child(missile)
		missiles.append(missile)
	# "boost" is handled directly in player_kart.gd


func _check_oil_collisions() -> void:
	var to_remove: Array = []
	for oil in oil_spills:
		if not oil or not is_instance_valid(oil):
			continue
		for kart in karts:
			if not kart or kart.is_spinning_out:
				continue
			var d = Vector2(kart.global_position.x - oil.global_position.x, kart.global_position.z - oil.global_position.z).length()
			if d < 3.5:
				kart.start_spinout()
				to_remove.append(oil)
				break
	for oil in to_remove:
		oil_spills.erase(oil)
		oil.queue_free()


func _check_truck_collisions() -> void:
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
			if dist < 3.5 and dist > 0.01:
				var push_dir = diff.normalized()
				var overlap = 3.5 - dist
				a.global_position.x += push_dir.x * overlap * 0.5
				a.global_position.z += push_dir.z * overlap * 0.5
				b.global_position.x -= push_dir.x * overlap * 0.5
				b.global_position.z -= push_dir.z * overlap * 0.5
				var transfer = (a.speed - b.speed) * 0.15
				a.speed -= transfer
				b.speed += transfer


func _create_kart(id: int, color: Color) -> Node3D:
	var kart = Node3D.new()
	kart.set_script(preload("res://scripts/player_kart.gd"))
	kart.name = "Kart_P%d" % (id + 1)
	kart.set("player_id", id)
	kart.set("truck_color", color)
	return kart


# === TERRAIN ===

func _build_terrain_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	st.set_material(mat)

	var grass = Color(0.25, 0.55, 0.2)
	var road = Color(0.45, 0.35, 0.22)
	var mud_color = Color(0.3, 0.2, 0.1)

	var extent = ARENA_SIZE + 10.0
	# Larger area needs more steps but cap for performance
	var steps = 250
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

			var c00 = _get_color(x0, z0, grass, road, mud_color)
			var c10 = _get_color(x1, z0, grass, road, mud_color)
			var c01 = _get_color(x0, z1, grass, road, mud_color)
			var c11 = _get_color(x1, z1, grass, road, mud_color)

			st.set_color(c00); st.add_vertex(v00)
			st.set_color(c10); st.add_vertex(v10)
			st.set_color(c01); st.add_vertex(v01)
			st.set_color(c10); st.add_vertex(v10)
			st.set_color(c11); st.add_vertex(v11)
			st.set_color(c01); st.add_vertex(v01)

	st.generate_normals()
	st.index()
	var m = MeshInstance3D.new()
	m.mesh = st.commit()
	m.name = "Terrain"
	world_node.add_child(m)


func _get_color(x: float, z: float, grass: Color, road: Color, mud: Color) -> Color:
	var canyon_rock = Color(0.45, 0.35, 0.28)

	# Check mud zones first
	for mz in MUD_ZONES:
		var dx = x - mz[0]
		var dz = z - mz[1]
		if sqrt(dx * dx + dz * dz) < mz[2]:
			return mud

	# Road check
	var nx = x / OVAL_RX
	var nz = z / OVAL_RZ
	var ed = sqrt(nx * nx + nz * nz)
	var dfc = abs(ed - 1.0)
	var wd = dfc * (OVAL_RX + OVAL_RZ) / 2.0
	var rhw = ROAD_WIDTH / 2.0

	# Check if near the road (canyon zone)
	var near_road = wd < rhw + 50.0  # canyon extends 50 past road edge
	var track_angle = atan2(z, x)
	var depth_factor = 0.3 + 0.7 * (1.0 - cos(track_angle)) / 2.0

	if wd < rhw - 2.0:
		# On road — darken in deep canyon sections
		return road.darkened(depth_factor * 0.15)
	elif wd < rhw + 2.0:
		var base = canyon_rock if near_road and depth_factor > 0.2 else grass
		return road.lerp(base, (wd - (rhw - 2.0)) / 4.0)

	# Canyon walls get rocky color based on depth
	if near_road and depth_factor > 0.1:
		return grass.lerp(canyon_rock, clamp(depth_factor * 1.5, 0.0, 1.0))

	return grass


func _build_walls() -> void:
	var wm = StandardMaterial3D.new()
	wm.albedo_color = Color(0.35, 0.35, 0.38)
	wm.roughness = 0.9
	var wh = 20.0
	var wt = 4.0
	var s = ARENA_SIZE
	for w in [
		[Vector3(0, wh/2, -s), Vector3(s*2+wt*2, wh, wt)],
		[Vector3(0, wh/2, s), Vector3(s*2+wt*2, wh, wt)],
		[Vector3(-s, wh/2, 0), Vector3(wt, wh, s*2)],
		[Vector3(s, wh/2, 0), Vector3(wt, wh, s*2)],
	]:
		var wall = MeshInstance3D.new()
		var b = BoxMesh.new()
		b.size = w[1]
		wall.mesh = b
		wall.material_override = wm
		wall.position = w[0]
		world_node.add_child(wall)


func _build_start_finish_line() -> void:
	var y = get_ground_height(OVAL_RX, 0) + 0.2
	var w = ROAD_WIDTH + 4.0
	var checks = 16
	var cw = w / checks
	for i in range(checks):
		var c = MeshInstance3D.new()
		var b = BoxMesh.new()
		b.size = Vector3(cw * 0.98, 0.05, 4.0)
		c.mesh = b
		var m = StandardMaterial3D.new()
		m.albedo_color = Color.WHITE if i % 2 == 0 else Color(0.1, 0.1, 0.1)
		c.material_override = m
		c.position = Vector3(OVAL_RX - w/2 + cw * (i + 0.5), y, 0)
		world_node.add_child(c)


func _build_boulders() -> void:
	var boulder_mat = StandardMaterial3D.new()
	boulder_mat.albedo_color = Color(0.4, 0.38, 0.35)
	boulder_mat.roughness = 1.0

	for b in BOULDERS:
		var boulder = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = b[2]
		sphere.height = b[2] * 2.0
		boulder.mesh = sphere
		boulder.material_override = boulder_mat
		var by = get_ground_height(b[0], b[1])
		boulder.position = Vector3(b[0], by + b[2] * 0.6, b[1])
		world_node.add_child(boulder)


func _build_mystery_boxes() -> void:
	# Row of mystery boxes at one section of track (left side of oval, angle ~PI)
	# Place them across the road at x = -OVAL_RX, z = 0
	var box_x = -OVAL_RX
	var box_z = 0.0
	var box_y = get_ground_height(box_x, box_z) + 3.0
	var box_count = 5
	var spacing = ROAD_WIDTH / (box_count + 1)

	for i in range(box_count):
		var bx = MeshInstance3D.new()
		bx.name = "MysteryBox_%d" % i
		var mesh = BoxMesh.new()
		mesh.size = Vector3(3.0, 3.0, 3.0)
		bx.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.0, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.9, 0.3)
		mat.emission_energy_multiplier = 1.5
		bx.material_override = mat
		# Position across the road width
		var offset_z = -ROAD_WIDTH / 2.0 + spacing * (i + 1)
		bx.position = Vector3(box_x, box_y, box_z + offset_z)
		bx.set_meta("active", true)
		bx.set_meta("respawn_timer", 0.0)
		world_node.add_child(bx)
		mystery_boxes.append(bx)


func _check_mystery_box_collisions(delta: float) -> void:
	for box in mystery_boxes:
		if not box or not is_instance_valid(box):
			continue

		# Respawn timer
		if not box.get_meta("active"):
			var timer = box.get_meta("respawn_timer") - delta
			if timer <= 0:
				box.set_meta("active", true)
				box.visible = true
			else:
				box.set_meta("respawn_timer", timer)
			continue

		# Rotate the box for visual effect
		box.rotate_y(2.0 * delta)

		# Check kart collision
		for kart in karts:
			if not kart or kart.held_item != "":
				continue  # already has an item
			var d = kart.global_position.distance_to(box.global_position)
			if d < 4.0:
				# Give random item
				var items = ["missile", "oil", "boost"]
				kart.held_item = items[randi() % items.size()]
				# Deactivate box for 8 seconds
				box.set_meta("active", false)
				box.set_meta("respawn_timer", 8.0)
				box.visible = false
				break


func _update_missiles(delta: float) -> void:
	var to_remove: Array = []
	for missile in missiles:
		if not missile or not is_instance_valid(missile):
			continue

		var lifetime = missile.get_meta("lifetime") - delta
		missile.set_meta("lifetime", lifetime)
		if lifetime <= 0:
			to_remove.append(missile)
			continue

		var vel = missile.get_meta("velocity") as Vector3
		var owner_id = missile.get_meta("owner_id") as int

		# Home toward nearest opponent
		var nearest_dist = 9999.0
		var nearest_kart = null
		for kart in karts:
			if not kart or kart.player_id == owner_id:
				continue
			var d = missile.global_position.distance_to(kart.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_kart = kart

		if nearest_kart:
			var to_target = (nearest_kart.global_position + Vector3(0, 1.5, 0) - missile.global_position).normalized()
			vel = vel.normalized().lerp(to_target, 3.0 * delta) * vel.length()
			missile.set_meta("velocity", vel)
			missile.look_at(missile.global_position + vel)

		missile.global_position += vel * delta

		# Keep missile above ground
		var gy = get_ground_height(missile.global_position.x, missile.global_position.z) + 1.5
		if missile.global_position.y < gy:
			missile.global_position.y = gy

		# Hit detection
		for kart in karts:
			if not kart or kart.player_id == owner_id or kart.is_spinning_out:
				continue
			if missile.global_position.distance_to(kart.global_position) < 4.0:
				kart.start_spinout()
				to_remove.append(missile)
				break

		# Wall check
		if abs(missile.global_position.x) > ARENA_SIZE or abs(missile.global_position.z) > ARENA_SIZE:
			to_remove.append(missile)

	for m in to_remove:
		missiles.erase(m)
		m.queue_free()


func get_ground_height(x: float, z: float) -> float:
	var h = 0.0

	# Center mountain
	var md = sqrt(x * x + z * z)
	if md < MOUNTAIN_RADIUS:
		h += MOUNTAIN_HEIGHT * 0.5 * (1.0 + cos(PI * md / MOUNTAIN_RADIUS))

	# Hills
	for hill in HILLS:
		var dx = x - hill[0]
		var dz = z - hill[1]
		var dist = sqrt(dx * dx + dz * dz)
		if dist < hill[3]:
			h += hill[2] * 0.5 * (1.0 + cos(PI * dist / hill[3]))

	# Canyon along entire oval — must match player_kart.gd exactly
	var nx = x / OVAL_RX
	var nz = z / OVAL_RZ
	var ed = sqrt(nx * nx + nz * nz)
	var dist_from_road = abs(ed - 1.0) * (OVAL_RX + OVAL_RZ) / 2.0

	var track_angle = atan2(z, x)
	var depth_factor = 0.3 + 0.7 * (1.0 - cos(track_angle)) / 2.0
	var canyon_depth = 30.0 * depth_factor

	var road_zone = ROAD_WIDTH * 0.8
	var canyon_width = road_zone + 50.0
	if dist_from_road < canyon_width:
		if dist_from_road < road_zone:
			h -= canyon_depth
		else:
			var wall_blend = clamp((dist_from_road - road_zone) / 50.0, 0.0, 1.0)
			h -= canyon_depth * (1.0 - wall_blend)

	return h


func _on_lap_completed(_pid: int, _lap: int) -> void:
	pass


func _show_winner(pid: int) -> void:
	var win_canvas = CanvasLayer.new()
	win_canvas.name = "WinScreen"
	win_canvas.layer = 9
	add_child(win_canvas)
	hud_nodes.append(win_canvas)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_canvas.add_child(bg)

	var player_name = "PLAYER %d" % (pid + 1)
	var color_name = "BLUE" if pid == 0 else "RED"

	var label = Label.new()
	label.text = "%s WINS!" % player_name if player_count > 1 else "RACE COMPLETE!"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.custom_minimum_size = Vector2(600, 80)
	win_canvas.add_child(label)

	var sub = Label.new()
	sub.text = "Press ESC to return to menu"
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color.WHITE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.grow_vertical = Control.GROW_DIRECTION_BOTH
	sub.custom_minimum_size = Vector2(400, 40)
	sub.position.y = 60
	win_canvas.add_child(sub)

	# Freeze all karts
	for kart in karts:
		kart.race_started = false


func _make_label(pos: Vector2, size: int, color: Color, text: String) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	return l


func _create_menu() -> void:
	var canvas = CanvasLayer.new()
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
