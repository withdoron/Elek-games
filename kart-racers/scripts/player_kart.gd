extends Node3D

var speed: float = 0.0
var steer_angle: float = 0.0
var kart_tilt: float = 0.0
var move_velocity: Vector3 = Vector3.ZERO
var vertical_velocity: float = 0.0
var on_ground: bool = true

# Powerslide state
var is_powersliding: bool = false
var powerslide_direction: float = 0.0  # -1 left, +1 right

# Lap tracking
var lap_count: int = 0
var last_half: int = 0  # 0 = right side (x>0), 1 = left side (x<0)
signal lap_completed(player_id: int, lap: int)

# Set by main_setup when spawning
var player_id: int = 0
var truck_color: Color = Color(0.2, 0.35, 0.8)

const RIDE_HEIGHT = 0.3
const GRAVITY = 40.0

# Oval road params — must match main_setup.gd
const OVAL_RX = 120.0
const OVAL_RZ = 80.0
const ROAD_WIDTH = 24.0

# Hill definitions — must match main_setup.gd
const HILLS = [
	[0.0, -50.0, 20.0, 40.0],
	[80.0, 40.0, 14.0, 35.0],
	[-70.0, -30.0, 10.0, 28.0],
	[40.0, -100.0, 16.0, 30.0],
	[-50.0, 70.0, 8.0, 25.0],
	[160.0, 0.0, 15.0, 35.0],
	[-160.0, -40.0, 12.0, 28.0],
]

# Node references
var body_mesh: Node3D
var truck_body: MeshInstance3D
var front_pivots: Array = []
var wheel_meshes: Array = []
var camera: Camera3D
var dirt_particles: Array = []
var engine_audio: AudioStreamPlayer3D
var surface_audio: AudioStreamPlayer3D


func _ready() -> void:
	_build_truck()
	_setup_camera()
	_setup_dirt_particles()
	_setup_engine_audio()


func _physics_process(delta: float) -> void:
	var s = Settings

	# --- Input (per player_id) ---
	var throttle = 0.0
	var brake_input = 0.0
	var steer_input = 0.0
	var device = player_id  # gamepad device matches player_id

	# Keyboard (P1 only)
	if player_id == 0:
		if Input.is_action_pressed("accelerate"):
			throttle = 1.0
		if Input.is_action_pressed("brake"):
			brake_input = 1.0
		if Input.is_action_pressed("steer_left"):
			steer_input -= 1.0
		if Input.is_action_pressed("steer_right"):
			steer_input += 1.0

	# Gamepad (both players — device = player_id)
	var rt = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	var lt = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	if rt > s.deadzone:
		throttle = max(throttle, rt)
	if lt > s.deadzone:
		brake_input = max(brake_input, lt)

	var stick_x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	if abs(stick_x) > s.deadzone:
		steer_input = clamp(steer_input + stick_x * s.stick_sensitivity, -1.0, 1.0)

	if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
		throttle = max(throttle, 1.0)
	if Input.is_joy_button_pressed(device, JOY_BUTTON_X):
		brake_input = max(brake_input, 1.0)

	# Bumpers: jump + powerslide
	var bumper_pressed = Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	# Keyboard: Space for P1
	if player_id == 0 and Input.is_key_pressed(KEY_SPACE):
		bumper_pressed = true

	if bumper_pressed and on_ground and not is_powersliding:
		# Start powerslide — small jump + begin sliding
		vertical_velocity = 5.0
		on_ground = false
		is_powersliding = true
		powerslide_direction = sign(steer_input) if abs(steer_input) > 0.1 else 0.0
	elif bumper_pressed and is_powersliding:
		# Continue powersliding — maintain slide
		pass
	elif not bumper_pressed and is_powersliding:
		# Release — end powerslide
		is_powersliding = false
		powerslide_direction = 0.0

	# --- Surface detection ---
	var on_road = _is_on_road(global_position.x, global_position.z)
	var surface_max_speed = s.max_speed if on_road else s.max_speed * 0.85

	# --- Speed ---
	if throttle > 0.0 and speed >= 0.0:
		speed = move_toward(speed, surface_max_speed * throttle, s.acceleration * throttle * delta)
	elif brake_input > 0.0:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, s.brake_force * brake_input * delta)
		else:
			speed = move_toward(speed, -s.reverse_speed * brake_input, s.acceleration * brake_input * delta)
	else:
		speed = move_toward(speed, 0.0, s.coast_decel * delta)

	# Clamp to surface max
	if speed > surface_max_speed:
		speed = move_toward(speed, surface_max_speed, 5.0 * delta)

	# --- Slope physics (when on ground) ---
	if on_ground and abs(speed) > 0.5:
		var fwd = -transform.basis.z.normalized()
		var d = 2.0
		var h_front = _get_ground_height(global_position.x + fwd.x * d, global_position.z + fwd.z * d)
		var h_back = _get_ground_height(global_position.x - fwd.x * d, global_position.z - fwd.z * d)
		var slope = (h_front - h_back) / (d * 2.0)
		# Uphill slows, downhill speeds up
		speed -= slope * GRAVITY * 0.3 * delta

	# --- Steering ---
	var speed_ratio = clamp(abs(speed) / max(s.max_speed, 0.01), 0.0, 1.0)
	var turn_reduction = lerp(1.0, s.turn_speed_factor, speed_ratio)

	if abs(speed) > 0.5:
		var direction_mult = 1.0 if speed >= 0.0 else -1.0
		var target_steer = steer_input * s.turn_speed * turn_reduction * direction_mult
		steer_angle = lerp(steer_angle, target_steer, s.drift_turn_boost * delta)
	else:
		steer_angle = move_toward(steer_angle, 0.0, s.return_to_center * delta)

	if abs(steer_input) < 0.1 and abs(speed) > 0.5:
		steer_angle = move_toward(steer_angle, 0.0, s.return_to_center * delta)

	# --- Apply rotation ---
	rotate_y(-steer_angle * delta)

	# --- Drift / Sliding ---
	var forward_dir = -transform.basis.z.normalized()
	var forward_vel = forward_dir * speed
	var lateral = move_velocity - forward_dir * move_velocity.dot(forward_dir)

	# Speed-dependent sliding: faster = more slide on turns
	var base_grip = s.drift_factor  # 0.92 default
	if is_powersliding:
		# Powerslide: much more slidey, extra turn boost
		var slide_grip = 0.97  # high lateral persistence = big slide
		move_velocity = forward_vel + lateral * slide_grip
		# Extra rotation during powerslide
		var ps_turn = (steer_input if abs(steer_input) > 0.1 else powerslide_direction) * 3.0
		rotate_y(-ps_turn * delta)
	else:
		# Normal: grip decreases at high speed (more sliding in fast corners)
		var speed_slide = clamp(abs(speed) / max(s.max_speed, 1.0), 0.0, 1.0)
		var effective_grip = lerp(base_grip * 0.5, base_grip, 1.0 - speed_slide * 0.4)
		move_velocity = forward_vel + lateral * effective_grip

	move_velocity.y = 0

	# --- Horizontal movement ---
	global_position.x += move_velocity.x * delta
	global_position.z += move_velocity.z * delta

	# --- Wall clamping ---
	var wall_limit = 198.0
	global_position.x = clamp(global_position.x, -wall_limit, wall_limit)
	global_position.z = clamp(global_position.z, -wall_limit, wall_limit)
	if abs(global_position.x) >= wall_limit or abs(global_position.z) >= wall_limit:
		speed *= 0.9

	# --- Vertical physics ---
	var ground_y = _get_ground_height(global_position.x, global_position.z) + RIDE_HEIGHT
	vertical_velocity -= GRAVITY * delta
	global_position.y += vertical_velocity * delta

	if global_position.y <= ground_y:
		global_position.y = ground_y
		if vertical_velocity < -15.0:
			vertical_velocity = -vertical_velocity * 0.15
		else:
			vertical_velocity = 0.0
		on_ground = true

		# Hill crest launch
		var look_ahead = 2.0
		var fwd_x = global_position.x + forward_dir.x * look_ahead
		var fwd_z = global_position.z + forward_dir.z * look_ahead
		var ground_ahead = _get_ground_height(fwd_x, fwd_z) + RIDE_HEIGHT
		var ground_slope = (ground_ahead - ground_y) / look_ahead

		if ground_slope < -0.15 and abs(speed) > 10.0:
			var launch_power = abs(speed) * abs(ground_slope) * 0.5
			vertical_velocity = clamp(launch_power, 0.0, 12.0)
			on_ground = false
	else:
		on_ground = false

	# --- Lap tracking ---
	# Track which half of the oval the truck is in (x>0 = right, x<0 = left)
	# A lap = crossing from right to left (through z<0) then back to right (through z>0)
	var current_half = 0 if global_position.x > 0 else 1
	if current_half != last_half:
		# Crossed from one half to the other
		if last_half == 1 and current_half == 0 and global_position.z < 0:
			# Completed a lap (crossed back to right side on the bottom)
			lap_count += 1
			emit_signal("lap_completed", player_id, lap_count)
		last_half = current_half

	# --- Terrain alignment ---
	_align_to_terrain(delta)

	# --- Audio ---
	_update_audio(on_road)

	# --- Visuals ---
	_update_visuals(delta, steer_input, on_road)


func _is_on_road(x: float, z: float) -> bool:
	var nx = x / OVAL_RX
	var nz = z / OVAL_RZ
	var ellipse_dist = sqrt(nx * nx + nz * nz)
	var dist_from_curve = abs(ellipse_dist - 1.0)
	var avg_radius = (OVAL_RX + OVAL_RZ) / 2.0
	var world_dist = dist_from_curve * avg_radius
	return world_dist < ROAD_WIDTH / 2.0


func _align_to_terrain(delta: float) -> void:
	var target_pitch = 0.0
	var target_roll = 0.0

	if on_ground:
		var d = 1.5
		var pos = global_position
		var fwd = -transform.basis.z.normalized()
		var right_dir = transform.basis.x.normalized()

		var h_front = _get_ground_height(pos.x + fwd.x * d, pos.z + fwd.z * d)
		var h_back = _get_ground_height(pos.x - fwd.x * d, pos.z - fwd.z * d)
		var h_left = _get_ground_height(pos.x - right_dir.x * d, pos.z - right_dir.z * d)
		var h_right = _get_ground_height(pos.x + right_dir.x * d, pos.z + right_dir.z * d)

		target_pitch = atan2(h_front - h_back, d * 2.0)
		target_roll = atan2(h_right - h_left, d * 2.0)
	else:
		target_pitch = clamp(vertical_velocity * 0.02, deg_to_rad(-20), deg_to_rad(15))
		target_roll = 0.0

	var max_tilt = deg_to_rad(35.0)
	target_pitch = clamp(target_pitch, -max_tilt, max_tilt)
	target_roll = clamp(target_roll, -max_tilt, max_tilt)

	if body_mesh:
		var t = 8.0 * delta if on_ground else 3.0 * delta
		body_mesh.rotation.x = lerp(body_mesh.rotation.x, target_pitch, t)
		body_mesh.rotation.z = lerp(body_mesh.rotation.z, target_roll, t)


func _get_ground_height(x: float, z: float) -> float:
	var h = 0.0
	for hill in HILLS:
		var dx = x - hill[0]
		var dz = z - hill[1]
		var dist = sqrt(dx * dx + dz * dz)
		if dist < hill[3]:
			h += hill[2] * 0.5 * (1.0 + cos(PI * dist / hill[3]))
	return h


# === AUDIO ===

func _setup_engine_audio() -> void:
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.name = "EngineAudio"
	engine_audio.max_distance = 100.0
	engine_audio.bus = "Master"

	# Generate a short looping engine tone
	var sample_rate = 22050
	var duration = 0.1  # short loop
	var samples = int(sample_rate * duration)
	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false
	audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	audio.loop_end = samples

	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		# Mix two frequencies for a rough engine sound
		var wave = sin(t * 80.0 * TAU) * 0.4 + sin(t * 160.0 * TAU) * 0.2 + sin(t * 40.0 * TAU) * 0.3
		var sample_val = int(clamp(wave, -1.0, 1.0) * 16000)
		data[i * 2] = sample_val & 0xFF
		data[i * 2 + 1] = (sample_val >> 8) & 0xFF

	audio.data = data
	engine_audio.stream = audio
	engine_audio.volume_db = -10.0
	add_child(engine_audio)
	engine_audio.play()

	# Surface audio layer (for grass rustling)
	surface_audio = AudioStreamPlayer3D.new()
	surface_audio.name = "SurfaceAudio"
	surface_audio.max_distance = 50.0
	surface_audio.bus = "Master"

	var surf_audio = AudioStreamWAV.new()
	surf_audio.format = AudioStreamWAV.FORMAT_16_BITS
	surf_audio.mix_rate = sample_rate
	surf_audio.stereo = false
	surf_audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	surf_audio.loop_end = samples

	var surf_data = PackedByteArray()
	surf_data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		# Higher frequency noise-like sound for grass
		var wave = sin(t * 300.0 * TAU) * 0.15 + sin(t * 470.0 * TAU) * 0.1
		var sample_val = int(clamp(wave, -1.0, 1.0) * 8000)
		surf_data[i * 2] = sample_val & 0xFF
		surf_data[i * 2 + 1] = (sample_val >> 8) & 0xFF

	surf_audio.data = surf_data
	surface_audio.stream = surf_audio
	surface_audio.volume_db = -20.0
	add_child(surface_audio)
	surface_audio.play()


func _update_audio(on_road: bool) -> void:
	if not engine_audio:
		return
	var spd_ratio = clamp(abs(speed) / max(Settings.max_speed, 1.0), 0.0, 1.0)

	# Engine pitch: low idle → high at speed
	engine_audio.pitch_scale = 0.5 + spd_ratio * 1.5
	engine_audio.volume_db = -12.0 + spd_ratio * 6.0  # louder at speed

	# Surface audio: grass rustling when off-road
	if surface_audio:
		if not on_road and spd_ratio > 0.1:
			surface_audio.volume_db = -18.0 + spd_ratio * 8.0
			surface_audio.pitch_scale = 0.8 + spd_ratio * 0.6
		else:
			surface_audio.volume_db = -40.0  # silent on road


# === VISUALS ===

func _setup_dirt_particles() -> void:
	var rear_positions = [
		Vector3(-1.4, 0.3, 1.8),
		Vector3(1.4, 0.3, 1.8),
	]
	for pos in rear_positions:
		var particles = CPUParticles3D.new()
		particles.name = "DirtParticles"
		particles.position = pos
		particles.emitting = false
		particles.amount = 20
		particles.lifetime = 0.8
		particles.speed_scale = 1.5
		particles.explosiveness = 0.1
		particles.direction = Vector3(0, 1, 1)
		particles.spread = 25.0
		particles.initial_velocity_min = 2.0
		particles.initial_velocity_max = 5.0
		particles.gravity = Vector3(0, -8, 0)
		particles.scale_amount_min = 0.15
		particles.scale_amount_max = 0.4

		particles.color = Color(0.3, 0.5, 0.2, 0.8)
		var color_ramp = Gradient.new()
		color_ramp.set_color(0, Color(0.3, 0.55, 0.2, 0.9))
		color_ramp.set_color(1, Color(0.25, 0.45, 0.18, 0.0))
		particles.color_ramp = color_ramp

		var particle_mesh = SphereMesh.new()
		particle_mesh.radius = 0.1
		particle_mesh.height = 0.2
		particles.mesh = particle_mesh

		body_mesh.add_child(particles)
		dirt_particles.append(particles)


func _update_visuals(delta: float, steer_input: float, on_road: bool) -> void:
	# Front wheel steering
	var visual_steer = -steer_input * 0.5
	for pivot in front_pivots:
		if pivot:
			pivot.rotation.y = lerp(pivot.rotation.y, visual_steer, delta * 10.0)

	# Wheel spin
	var spin_rate = speed * 2.0 * delta
	for i in range(wheel_meshes.size()):
		if wheel_meshes[i]:
			wheel_meshes[i].rotate_x(spin_rate)

	# Dirt particles — color and intensity by surface
	var spd_ratio = clamp(abs(speed) / max(Settings.max_speed, 1.0), 0.0, 1.0)
	for p in dirt_particles:
		if spd_ratio > 0.1 and on_ground:
			p.emitting = true
			p.initial_velocity_min = 2.0 + spd_ratio * 6.0
			p.initial_velocity_max = 5.0 + spd_ratio * 10.0
			p.amount = int(10 + spd_ratio * 30)
			# Color by surface
			if on_road:
				p.color = Color(0.45, 0.35, 0.22, 0.8)
			else:
				p.color = Color(0.3, 0.55, 0.2, 0.8)
		else:
			p.emitting = false


# === TRUCK BUILD ===

func _build_truck() -> void:
	var primary_color = truck_color
	var chrome = Color(0.6, 0.6, 0.65)
	var dark_grey = Color(0.15, 0.15, 0.15)

	body_mesh = Node3D.new()
	body_mesh.name = "BodyMesh"
	add_child(body_mesh)

	var frame = _make_box(Vector3(2.2, 0.2, 3.5), dark_grey)
	frame.position = Vector3(0, 1.0, 0)
	body_mesh.add_child(frame)

	truck_body = _make_box_metallic(Vector3(2.0, 0.8, 3.2), primary_color, 0.4)
	truck_body.position = Vector3(0, 1.5, 0)
	body_mesh.add_child(truck_body)

	var cab = _make_box_metallic(Vector3(1.8, 0.7, 1.4), primary_color.darkened(0.15), 0.4)
	cab.position = Vector3(0, 2.2, -0.3)
	body_mesh.add_child(cab)

	var windshield = _make_box(Vector3(1.6, 0.5, 0.08), Color(0.5, 0.7, 1.0, 0.4))
	windshield.position = Vector3(0, 2.2, -1.0)
	windshield.rotation.x = deg_to_rad(-15)
	var ws_mat = windshield.material_override as StandardMaterial3D
	ws_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mesh.add_child(windshield)

	var rear_window = _make_box(Vector3(1.6, 0.45, 0.08), Color(0.5, 0.7, 1.0, 0.4))
	rear_window.position = Vector3(0, 2.2, 0.4)
	var rw_mat = rear_window.material_override as StandardMaterial3D
	rw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mesh.add_child(rear_window)

	var bed = _make_box_metallic(Vector3(2.0, 0.5, 1.2), primary_color, 0.4)
	bed.position = Vector3(0, 1.3, 1.3)
	body_mesh.add_child(bed)

	var grille = _make_box_metallic(Vector3(1.8, 0.5, 0.1), chrome, 0.7)
	grille.position = Vector3(0, 1.5, -1.65)
	body_mesh.add_child(grille)

	var front_bumper = _make_box_metallic(Vector3(2.2, 0.2, 0.15), chrome, 0.7)
	front_bumper.position = Vector3(0, 1.1, -1.7)
	body_mesh.add_child(front_bumper)

	var rear_bumper = _make_box_metallic(Vector3(2.2, 0.2, 0.15), chrome, 0.7)
	rear_bumper.position = Vector3(0, 1.1, 1.85)
	body_mesh.add_child(rear_bumper)

	var hl_color = Color(1.0, 0.9, 0.3)
	for x_pos in [-0.6, 0.6]:
		var hl = _make_box(Vector3(0.3, 0.2, 0.05), hl_color)
		hl.position = Vector3(x_pos, 1.6, -1.66)
		var hl_mat = hl.material_override as StandardMaterial3D
		hl_mat.emission_enabled = true
		hl_mat.emission = hl_color
		hl_mat.emission_energy_multiplier = 2.0
		body_mesh.add_child(hl)

	var wheel_positions = [
		Vector3(-1.4, 0.8, -1.1),
		Vector3(1.4, 0.8, -1.1),
		Vector3(-1.4, 0.8, 1.1),
		Vector3(1.4, 0.8, 1.1),
	]

	front_pivots = []
	wheel_meshes = []

	for i in range(4):
		var is_front = i < 2
		var wheel_assembly = _make_monster_wheel()

		if is_front:
			var pivot = Node3D.new()
			pivot.name = "WheelPivot_%d" % i
			pivot.position = wheel_positions[i]
			body_mesh.add_child(pivot)
			wheel_assembly.position = Vector3.ZERO
			pivot.add_child(wheel_assembly)
			front_pivots.append(pivot)
			wheel_meshes.append(wheel_assembly)
		else:
			wheel_assembly.position = wheel_positions[i]
			body_mesh.add_child(wheel_assembly)
			wheel_meshes.append(wheel_assembly)

	for wp in wheel_positions:
		var strut = _make_cylinder(0.06, 0.8, dark_grey)
		strut.position = Vector3(wp.x * 0.7, 0.9, wp.z)
		body_mesh.add_child(strut)

	var exhaust_color = Color(0.2, 0.2, 0.22)
	for x_pos in [-0.5, 0.5]:
		var exhaust = _make_cylinder_metallic(0.06, 0.5, exhaust_color, 0.5)
		exhaust.position = Vector3(x_pos, 1.8, 1.5)
		body_mesh.add_child(exhaust)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.position = Vector3(0, 5.5, 10)
	camera.rotation.x = deg_to_rad(-12)
	camera.current = (player_id == 0)  # only P1 camera active by default
	add_child(camera)


func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	return mesh_inst


func _make_box_metallic(size: Vector3, color: Color, metallic: float) -> MeshInstance3D:
	var mesh_inst = _make_box(size, color)
	var mat = mesh_inst.material_override as StandardMaterial3D
	mat.metallic = metallic
	return mesh_inst


func _make_cylinder(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh_inst.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	return mesh_inst


func _make_cylinder_metallic(radius: float, height: float, color: Color, metallic: float) -> MeshInstance3D:
	var mesh_inst = _make_cylinder(radius, height, color)
	var mat = mesh_inst.material_override as StandardMaterial3D
	mat.metallic = metallic
	return mesh_inst


func _make_monster_wheel() -> Node3D:
	var wheel_node = Node3D.new()

	var tire = MeshInstance3D.new()
	var tire_cyl = CylinderMesh.new()
	tire_cyl.top_radius = 0.8
	tire_cyl.bottom_radius = 0.8
	tire_cyl.height = 0.6
	tire.mesh = tire_cyl
	tire.rotation_degrees = Vector3(0, 0, 90)
	var tire_mat = StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.1, 0.1, 0.1)
	tire_mat.roughness = 1.0
	tire.material_override = tire_mat
	wheel_node.add_child(tire)

	var rim = MeshInstance3D.new()
	var rim_cyl = CylinderMesh.new()
	rim_cyl.top_radius = 0.35
	rim_cyl.bottom_radius = 0.35
	rim_cyl.height = 0.62
	rim.mesh = rim_cyl
	rim.rotation_degrees = Vector3(0, 0, 90)
	var rim_mat = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.5, 0.5, 0.55)
	rim_mat.metallic = 0.6
	rim.material_override = rim_mat
	wheel_node.add_child(rim)

	return wheel_node
