extends Node3D

var speed: float = 0.0
var steer_angle: float = 0.0
var kart_tilt: float = 0.0
var move_velocity: Vector3 = Vector3.ZERO
var vertical_velocity: float = 0.0
var on_ground: bool = true

# MK64-style powerslide
var is_drifting: bool = false
var drift_charge: int = 0
var drift_charge_timer: float = 0.0
var drift_direction: float = 0.0
var drift_boost_timer: float = 0.0
const DRIFT_BOOST_SPEED = 15.0
const DRIFT_BOOST_DURATION = 0.6

# Spinout
var is_spinning_out: bool = false
var spinout_timer: float = 0.0
const SPINOUT_DURATION = 1.5

# Oil spill weapon
var oil_count: int = 2
signal drop_oil(player_id: int, pos: Vector3)

# Lap tracking
var lap_count: int = 0
var last_half: int = 0
signal lap_completed(player_id: int, lap: int)

# Race state
var race_started: bool = false

# Set by main_setup
var player_id: int = 0
var truck_color: Color = Color(0.2, 0.35, 0.8)

const RIDE_HEIGHT = 0.3
const GRAVITY = 40.0

# Track dimensions — 3x bigger
const OVAL_RX = 360.0
const OVAL_RZ = 240.0
const ROAD_WIDTH = 48.0
const ARENA_SIZE = 600.0

# Center mountain — blocks shortcuts through the middle
const MOUNTAIN_RADIUS = 150.0
const MOUNTAIN_HEIGHT = 60.0

# Hills on/near the track
const HILLS = [
	[250.0, 120.0, 20.0, 50.0],
	[-200.0, -100.0, 16.0, 45.0],
	[100.0, -250.0, 14.0, 40.0],
	[-300.0, 50.0, 18.0, 50.0],
	[400.0, -50.0, 12.0, 35.0],
	[-150.0, 200.0, 10.0, 30.0],
	[50.0, 300.0, 15.0, 40.0],
]

# Boulders: [x, z, radius] — obstacles on the road
const BOULDERS = [
	[340.0, -120.0, 6.0],
	[-350.0, 80.0, 7.0],
	[200.0, 220.0, 5.0],
	[-100.0, -230.0, 6.0],
	[380.0, 100.0, 5.0],
	[-280.0, -180.0, 7.0],
]

# Mud zones around boulders — [x, z, radius]
const MUD_ZONES = [
	[340.0, -120.0, 20.0],
	[-350.0, 80.0, 22.0],
	[200.0, 220.0, 18.0],
	[-100.0, -230.0, 20.0],
	[380.0, 100.0, 18.0],
	[-280.0, -180.0, 22.0],
]

var body_mesh: Node3D
var truck_body: MeshInstance3D
var front_pivots: Array = []
var wheel_meshes: Array = []
var camera: Camera3D
var dirt_particles: Array = []
var engine_audio: AudioStreamPlayer
var drift_sparks: CPUParticles3D


func _ready() -> void:
	_build_truck()
	_setup_camera()
	_setup_dirt_particles()
	_setup_drift_sparks()
	_setup_engine_audio()


func _physics_process(delta: float) -> void:
	var s = Settings
	var device = player_id

	# --- SPINOUT ---
	if is_spinning_out:
		spinout_timer -= delta
		var brake_recover = false
		if player_id == 0 and Input.is_action_pressed("brake"):
			brake_recover = true
		if Input.is_joy_button_pressed(device, JOY_BUTTON_X):
			brake_recover = true
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.3:
			brake_recover = true
		if brake_recover:
			spinout_timer -= delta * 2.0

		if spinout_timer <= 0:
			is_spinning_out = false
			if body_mesh:
				body_mesh.rotation.y = 0.0
		else:
			if body_mesh:
				body_mesh.rotate_y(12.0 * delta)
			speed = move_toward(speed, 0.0, 20.0 * delta)
			var fwd = -transform.basis.z.normalized()
			global_position += fwd * speed * delta
			global_position.x = clamp(global_position.x, -(ARENA_SIZE - 2), ARENA_SIZE - 2)
			global_position.z = clamp(global_position.z, -(ARENA_SIZE - 2), ARENA_SIZE - 2)
			global_position.y = _get_ground_height(global_position.x, global_position.z) + RIDE_HEIGHT
			_update_visuals(delta, 0.0, false, false)
			return

	# --- Wait for race start ---
	if not race_started:
		_update_visuals(delta, 0.0, false, false)
		return

	# --- Input ---
	var throttle = 0.0
	var brake_input = 0.0
	var steer_input = 0.0

	if player_id == 0:
		if Input.is_action_pressed("accelerate"):
			throttle = 1.0
		if Input.is_action_pressed("brake"):
			brake_input = 1.0
		if Input.is_action_pressed("steer_left"):
			steer_input -= 1.0
		if Input.is_action_pressed("steer_right"):
			steer_input += 1.0

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

	var drift_button = Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	if player_id == 0 and Input.is_key_pressed(KEY_SPACE):
		drift_button = true

	var oil_button = Input.is_joy_button_pressed(device, JOY_BUTTON_Y)
	if player_id == 0 and Input.is_key_pressed(KEY_E):
		oil_button = true

	# --- Oil drop ---
	if oil_button and oil_count > 0 and on_ground:
		oil_count -= 1
		var drop_pos = global_position + transform.basis.z * 3.0
		emit_signal("drop_oil", player_id, drop_pos)

	# --- MK64 Powerslide ---
	if drift_button and on_ground and abs(speed) > 8.0:
		if not is_drifting:
			is_drifting = true
			drift_direction = sign(steer_input) if abs(steer_input) > 0.1 else 0.0
			drift_charge = 1
			drift_charge_timer = 0.0
			vertical_velocity = 4.0
			on_ground = false
		else:
			drift_charge_timer += delta
			if drift_charge_timer > 0.4 and drift_charge < 2:
				drift_charge = 2
			if drift_charge_timer > 0.8 and drift_charge < 3:
				drift_charge = 3
	elif is_drifting and not drift_button:
		is_drifting = false
		if drift_charge >= 2:
			drift_boost_timer = DRIFT_BOOST_DURATION * (0.5 if drift_charge == 2 else 1.0)
		drift_charge = 0
		drift_direction = 0.0

	# --- Surface detection ---
	var on_road = _is_on_road(global_position.x, global_position.z)
	var in_mud = _is_in_mud(global_position.x, global_position.z)

	var surface_max = s.max_speed
	if in_mud:
		surface_max *= 0.55  # mud: 45% speed reduction
	elif not on_road:
		surface_max *= 0.85  # grass: 15% reduction

	if drift_boost_timer > 0:
		drift_boost_timer -= delta
		surface_max += DRIFT_BOOST_SPEED

	# --- Speed ---
	if throttle > 0.0 and speed >= 0.0:
		var accel = s.acceleration
		if in_mud:
			accel *= 0.5  # slower acceleration in mud
		speed = move_toward(speed, surface_max * throttle, accel * throttle * delta)
	elif brake_input > 0.0:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, s.brake_force * brake_input * delta)
		else:
			speed = move_toward(speed, -s.reverse_speed * brake_input, s.acceleration * brake_input * delta)
	else:
		speed = move_toward(speed, 0.0, s.coast_decel * delta)

	if drift_boost_timer <= 0 and speed > surface_max:
		speed = move_toward(speed, surface_max, 5.0 * delta)

	# Slope physics
	if on_ground and abs(speed) > 0.5:
		var fwd = -transform.basis.z.normalized()
		var d = 2.0
		var h_front = _get_ground_height(global_position.x + fwd.x * d, global_position.z + fwd.z * d)
		var h_back = _get_ground_height(global_position.x - fwd.x * d, global_position.z - fwd.z * d)
		var slope = (h_front - h_back) / (d * 2.0)
		speed -= slope * GRAVITY * 0.3 * delta

	# --- Steering ---
	var speed_ratio = clamp(abs(speed) / max(s.max_speed, 0.01), 0.0, 1.0)
	var turn_reduction = lerp(1.0, s.turn_speed_factor, speed_ratio)

	# Mud makes steering sluggish
	var steer_mult = 0.4 if in_mud else 1.0

	if abs(speed) > 0.5:
		var direction_mult = 1.0 if speed >= 0.0 else -1.0
		var target_steer = steer_input * s.turn_speed * turn_reduction * direction_mult * steer_mult
		if is_drifting:
			target_steer += drift_direction * 1.5
		steer_angle = lerp(steer_angle, target_steer, s.drift_turn_boost * delta)
	else:
		steer_angle = move_toward(steer_angle, 0.0, s.return_to_center * delta)

	if abs(steer_input) < 0.1 and abs(speed) > 0.5 and not is_drifting:
		steer_angle = move_toward(steer_angle, 0.0, s.return_to_center * delta)

	rotate_y(-steer_angle * delta)

	# --- Drift / Sliding ---
	var forward_dir = -transform.basis.z.normalized()
	var forward_vel = forward_dir * speed
	var lateral = move_velocity - forward_dir * move_velocity.dot(forward_dir)

	if is_drifting:
		move_velocity = forward_vel + lateral * 0.96
	elif in_mud:
		# Mud: very low grip, truck slides around
		move_velocity = forward_vel + lateral * 0.97
	else:
		var speed_slide = clamp(abs(speed) / max(s.max_speed, 1.0), 0.0, 1.0)
		var effective_grip = lerp(s.drift_factor * 0.5, s.drift_factor, 1.0 - speed_slide * 0.4)
		move_velocity = forward_vel + lateral * effective_grip

	move_velocity.y = 0

	# Horizontal movement
	global_position.x += move_velocity.x * delta
	global_position.z += move_velocity.z * delta

	# Boulder collision — push away from boulders
	for b in BOULDERS:
		var dx = global_position.x - b[0]
		var dz = global_position.z - b[1]
		var dist = sqrt(dx * dx + dz * dz)
		var min_dist = b[2] + 2.0  # boulder radius + truck radius
		if dist < min_dist and dist > 0.01:
			var push = (min_dist - dist) / dist
			global_position.x += dx * push
			global_position.z += dz * push
			speed *= 0.7  # lose speed on boulder hit

	# Wall clamping
	var wall_limit = ARENA_SIZE - 2.0
	global_position.x = clamp(global_position.x, -wall_limit, wall_limit)
	global_position.z = clamp(global_position.z, -wall_limit, wall_limit)
	if abs(global_position.x) >= wall_limit or abs(global_position.z) >= wall_limit:
		speed *= 0.9

	# Vertical physics
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

	# Lap tracking
	var current_half = 0 if global_position.x > 0 else 1
	if current_half != last_half:
		if last_half == 1 and current_half == 0 and global_position.z < 0:
			lap_count += 1
			emit_signal("lap_completed", player_id, lap_count)
		last_half = current_half

	_align_to_terrain(delta)
	_update_audio(on_road, in_mud)
	_update_visuals(delta, steer_input, on_road, in_mud)


func turbo_start() -> void:
	speed = Settings.max_speed * 0.8
	drift_boost_timer = 1.0


func start_spinout() -> void:
	is_spinning_out = true
	spinout_timer = SPINOUT_DURATION


func _is_on_road(x: float, z: float) -> bool:
	var nx = x / OVAL_RX
	var nz = z / OVAL_RZ
	var ellipse_dist = sqrt(nx * nx + nz * nz)
	var dist_from_curve = abs(ellipse_dist - 1.0)
	var avg_radius = (OVAL_RX + OVAL_RZ) / 2.0
	var world_dist = dist_from_curve * avg_radius
	return world_dist < ROAD_WIDTH / 2.0


func _is_in_mud(x: float, z: float) -> bool:
	for mz in MUD_ZONES:
		var dx = x - mz[0]
		var dz = z - mz[1]
		if sqrt(dx * dx + dz * dz) < mz[2]:
			return true
	return false


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

	var max_tilt = deg_to_rad(35.0)
	target_pitch = clamp(target_pitch, -max_tilt, max_tilt)
	target_roll = clamp(target_roll, -max_tilt, max_tilt)

	if body_mesh:
		var t = 8.0 * delta if on_ground else 3.0 * delta
		body_mesh.rotation.x = lerp(body_mesh.rotation.x, target_pitch, t)
		body_mesh.rotation.z = lerp(body_mesh.rotation.z, target_roll, t)


func _get_ground_height(x: float, z: float) -> float:
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
	return h


# === AUDIO ===

func _setup_engine_audio() -> void:
	engine_audio = AudioStreamPlayer.new()
	engine_audio.name = "EngineAudio"

	# Generate a more engine-like sound with multiple dissonant harmonics
	var sample_rate = 22050
	var duration = 0.02  # very short loop
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false
	audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	audio.loop_begin = 0
	audio.loop_end = samples

	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		# Engine: sawtooth-like with harmonics for a raspy growl
		var wave = 0.0
		# Fundamental + odd harmonics = more buzz/rasp than pure sine
		wave += sin(t * 55.0 * TAU) * 0.3  # low rumble
		wave += sin(t * 110.0 * TAU) * 0.25  # main tone
		wave += sin(t * 220.0 * TAU) * 0.15  # 2nd harmonic
		wave += sin(t * 330.0 * TAU) * 0.1   # 3rd harmonic
		wave += sin(t * 440.0 * TAU) * 0.08  # 4th
		# Clipping for a harder, more mechanical sound
		wave = clamp(wave * 1.5, -0.8, 0.8)
		var sample_val = int(wave * 20000)
		data.encode_s16(i * 2, sample_val)

	audio.data = data
	engine_audio.stream = audio
	engine_audio.volume_db = -4.0
	add_child(engine_audio)
	engine_audio.play()


func _update_audio(on_road: bool, in_mud: bool) -> void:
	if not engine_audio:
		return
	var spd_ratio = clamp(abs(speed) / max(Settings.max_speed, 1.0), 0.0, 1.0)
	# Engine pitch: idle at 0.4, revving up to 2.5
	engine_audio.pitch_scale = 0.4 + spd_ratio * 2.1
	engine_audio.volume_db = -8.0 + spd_ratio * 8.0
	if drift_boost_timer > 0:
		engine_audio.pitch_scale += 0.4
	# Mud: lower pitch, like bogging down
	if in_mud:
		engine_audio.pitch_scale *= 0.7


# === DRIFT SPARKS ===

func _setup_drift_sparks() -> void:
	drift_sparks = CPUParticles3D.new()
	drift_sparks.name = "DriftSparks"
	drift_sparks.position = Vector3(0, 0.2, 1.5)
	drift_sparks.emitting = false
	drift_sparks.amount = 15
	drift_sparks.lifetime = 0.3
	drift_sparks.speed_scale = 2.0
	drift_sparks.direction = Vector3(0, 1, 0)
	drift_sparks.spread = 45.0
	drift_sparks.initial_velocity_min = 3.0
	drift_sparks.initial_velocity_max = 6.0
	drift_sparks.gravity = Vector3(0, -5, 0)
	drift_sparks.scale_amount_min = 0.05
	drift_sparks.scale_amount_max = 0.12
	drift_sparks.color = Color(1.0, 0.8, 0.2)
	var spark_mesh = SphereMesh.new()
	spark_mesh.radius = 0.05
	spark_mesh.height = 0.1
	drift_sparks.mesh = spark_mesh
	add_child(drift_sparks)


# === PARTICLES ===

func _setup_dirt_particles() -> void:
	for pos in [Vector3(-1.4, 0.3, 1.8), Vector3(1.4, 0.3, 1.8)]:
		var p = CPUParticles3D.new()
		p.name = "DirtParticles"
		p.position = pos
		p.emitting = false
		p.amount = 20
		p.lifetime = 0.8
		p.speed_scale = 1.5
		p.explosiveness = 0.1
		p.direction = Vector3(0, 1, 1)
		p.spread = 25.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0, -8, 0)
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.4
		p.color = Color(0.3, 0.5, 0.2, 0.8)
		var mesh = SphereMesh.new()
		mesh.radius = 0.1
		mesh.height = 0.2
		p.mesh = mesh
		body_mesh.add_child(p)
		dirt_particles.append(p)


func _update_visuals(delta: float, steer_input: float, on_road: bool, in_mud: bool) -> void:
	var visual_steer = -steer_input * 0.5
	for pivot in front_pivots:
		if pivot:
			pivot.rotation.y = lerp(pivot.rotation.y, visual_steer, delta * 10.0)

	var spin_rate = speed * 2.0 * delta
	for i in range(wheel_meshes.size()):
		if wheel_meshes[i]:
			wheel_meshes[i].rotate_x(spin_rate)

	var spd_ratio = clamp(abs(speed) / max(Settings.max_speed, 1.0), 0.0, 1.0)
	for p in dirt_particles:
		if spd_ratio > 0.1 and on_ground:
			p.emitting = true
			p.initial_velocity_min = 2.0 + spd_ratio * 6.0
			p.initial_velocity_max = 5.0 + spd_ratio * 10.0
			p.amount = int(10 + spd_ratio * 30)
			if in_mud:
				p.color = Color(0.35, 0.25, 0.12, 0.9)  # dark mud
			elif on_road:
				p.color = Color(0.45, 0.35, 0.22, 0.8)
			else:
				p.color = Color(0.3, 0.55, 0.2, 0.8)
		else:
			p.emitting = false

	if drift_sparks:
		if is_drifting and on_ground:
			drift_sparks.emitting = true
			if drift_charge >= 3:
				drift_sparks.color = Color(1.0, 0.4, 0.1)
			elif drift_charge >= 2:
				drift_sparks.color = Color(1.0, 0.9, 0.2)
			else:
				drift_sparks.color = Color(0.8, 0.8, 0.8)
		else:
			drift_sparks.emitting = false


# === TRUCK BUILD ===

func _build_truck() -> void:
	var primary_color = truck_color
	var chrome = Color(0.6, 0.6, 0.65)
	var dark_grey = Color(0.15, 0.15, 0.15)
	body_mesh = Node3D.new()
	body_mesh.name = "BodyMesh"
	add_child(body_mesh)

	body_mesh.add_child(_pos(_make_box(Vector3(2.2, 0.2, 3.5), dark_grey), Vector3(0, 1.0, 0)))
	truck_body = _make_box_metallic(Vector3(2.0, 0.8, 3.2), primary_color, 0.4)
	truck_body.position = Vector3(0, 1.5, 0)
	body_mesh.add_child(truck_body)
	body_mesh.add_child(_pos(_make_box_metallic(Vector3(1.8, 0.7, 1.4), primary_color.darkened(0.15), 0.4), Vector3(0, 2.2, -0.3)))

	var ws = _make_box(Vector3(1.6, 0.5, 0.08), Color(0.5, 0.7, 1.0, 0.4))
	ws.position = Vector3(0, 2.2, -1.0)
	ws.rotation.x = deg_to_rad(-15)
	(ws.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mesh.add_child(ws)

	var rw = _make_box(Vector3(1.6, 0.45, 0.08), Color(0.5, 0.7, 1.0, 0.4))
	rw.position = Vector3(0, 2.2, 0.4)
	(rw.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mesh.add_child(rw)

	body_mesh.add_child(_pos(_make_box_metallic(Vector3(2.0, 0.5, 1.2), primary_color, 0.4), Vector3(0, 1.3, 1.3)))
	body_mesh.add_child(_pos(_make_box_metallic(Vector3(1.8, 0.5, 0.1), chrome, 0.7), Vector3(0, 1.5, -1.65)))
	body_mesh.add_child(_pos(_make_box_metallic(Vector3(2.2, 0.2, 0.15), chrome, 0.7), Vector3(0, 1.1, -1.7)))
	body_mesh.add_child(_pos(_make_box_metallic(Vector3(2.2, 0.2, 0.15), chrome, 0.7), Vector3(0, 1.1, 1.85)))

	for x_pos in [-0.6, 0.6]:
		var hl = _make_box(Vector3(0.3, 0.2, 0.05), Color(1.0, 0.9, 0.3))
		hl.position = Vector3(x_pos, 1.6, -1.66)
		var hm = hl.material_override as StandardMaterial3D
		hm.emission_enabled = true
		hm.emission = Color(1.0, 0.9, 0.3)
		hm.emission_energy_multiplier = 2.0
		body_mesh.add_child(hl)

	var wp = [Vector3(-1.4, 0.8, -1.1), Vector3(1.4, 0.8, -1.1), Vector3(-1.4, 0.8, 1.1), Vector3(1.4, 0.8, 1.1)]
	front_pivots = []
	wheel_meshes = []
	for i in range(4):
		var wheel = _make_monster_wheel()
		if i < 2:
			var pivot = Node3D.new()
			pivot.position = wp[i]
			body_mesh.add_child(pivot)
			pivot.add_child(wheel)
			front_pivots.append(pivot)
		else:
			wheel.position = wp[i]
			body_mesh.add_child(wheel)
		wheel_meshes.append(wheel)

	for w in wp:
		body_mesh.add_child(_pos(_make_cylinder(0.06, 0.8, dark_grey), Vector3(w.x * 0.7, 0.9, w.z)))
	for x in [-0.5, 0.5]:
		body_mesh.add_child(_pos(_make_cylinder(0.06, 0.5, Color(0.2, 0.2, 0.22)), Vector3(x, 1.8, 1.5)))


func _pos(node: Node3D, p: Vector3) -> Node3D:
	node.position = p
	return node


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.position = Vector3(0, 5.5, 10)
	camera.rotation.x = deg_to_rad(-12)
	camera.current = (player_id == 0)
	add_child(camera)


func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var m = MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	(m.mesh as BoxMesh).size = size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	return m

func _make_box_metallic(size: Vector3, color: Color, metallic: float) -> MeshInstance3D:
	var m = _make_box(size, color)
	(m.material_override as StandardMaterial3D).metallic = metallic
	return m

func _make_cylinder(radius: float, height: float, color: Color) -> MeshInstance3D:
	var m = MeshInstance3D.new()
	var c = CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	m.mesh = c
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	return m

func _make_monster_wheel() -> Node3D:
	var w = Node3D.new()
	var t = MeshInstance3D.new()
	var tc = CylinderMesh.new()
	tc.top_radius = 0.8; tc.bottom_radius = 0.8; tc.height = 0.6
	t.mesh = tc; t.rotation_degrees = Vector3(0, 0, 90)
	var tm = StandardMaterial3D.new()
	tm.albedo_color = Color(0.1, 0.1, 0.1); tm.roughness = 1.0
	t.material_override = tm; w.add_child(t)
	var r = MeshInstance3D.new()
	var rc = CylinderMesh.new()
	rc.top_radius = 0.35; rc.bottom_radius = 0.35; rc.height = 0.62
	r.mesh = rc; r.rotation_degrees = Vector3(0, 0, 90)
	var rm = StandardMaterial3D.new()
	rm.albedo_color = Color(0.5, 0.5, 0.55); rm.metallic = 0.6
	r.material_override = rm; w.add_child(r)
	return w
