extends Node3D

var speed: float = 0.0
var steer_angle: float = 0.0
var kart_tilt: float = 0.0
var move_velocity: Vector3 = Vector3.ZERO  # manual velocity tracking for drift

# Truck origin offset above ground (wheels already at correct height in model)
const GROUND_OFFSET = 0.0

# Node references
var body_mesh: Node3D
var truck_body: MeshInstance3D  # main body mesh for future color changes
var front_pivots: Array = []  # [FL_pivot, FR_pivot] — rotate Y for steering
var wheel_meshes: Array = []  # [FL, FR, RL, RR] — rotate X for spin
var camera: Camera3D
var dirt_particles: Array = []  # [left_particles, right_particles]


func _ready() -> void:
	_build_truck()
	_setup_camera()
	_setup_dirt_particles()


func _physics_process(delta: float) -> void:
	var s = Settings  # shorthand, reads every frame

	# --- Input ---
	var throttle = 0.0
	var brake_input = 0.0
	var steer_input = 0.0

	# Keyboard
	if Input.is_action_pressed("accelerate"):
		throttle = 1.0
	if Input.is_action_pressed("brake"):
		brake_input = 1.0

	# Gamepad analog triggers (device 0)
	var rt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	var lt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if rt > s.deadzone:
		throttle = max(throttle, rt)
	if lt > s.deadzone:
		brake_input = max(brake_input, lt)

	# Steering: keyboard
	if Input.is_action_pressed("steer_left"):
		steer_input -= 1.0
	if Input.is_action_pressed("steer_right"):
		steer_input += 1.0

	# Steering: gamepad left stick
	var stick_x = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if abs(stick_x) > s.deadzone:
		steer_input = clamp(steer_input + stick_x * s.stick_sensitivity, -1.0, 1.0)

	# Gamepad face buttons: A = gas, X = brake/reverse
	if Input.is_joy_button_pressed(0, JOY_BUTTON_A):
		throttle = max(throttle, 1.0)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_X):
		brake_input = max(brake_input, 1.0)

	# Bumpers reserved for jump/powerslide (LB / RB)
	# var lb_pressed = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	# var rb_pressed = Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)

	# --- Speed ---
	if throttle > 0.0 and speed >= 0.0:
		speed = move_toward(speed, s.max_speed * throttle, s.acceleration * throttle * delta)
	elif brake_input > 0.0:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, s.brake_force * brake_input * delta)
		else:
			speed = move_toward(speed, -s.reverse_speed * brake_input, s.acceleration * brake_input * delta)
	else:
		speed = move_toward(speed, 0.0, s.coast_decel * delta)

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

	# --- Drift / lateral friction ---
	var forward_dir = -transform.basis.z.normalized()
	var forward_vel = forward_dir * speed
	var lateral = move_velocity - forward_dir * move_velocity.dot(forward_dir)
	move_velocity = forward_vel + lateral * s.drift_factor
	move_velocity.y = 0

	# --- Move manually (no move_and_slide, no physics fighting) ---
	global_position += move_velocity * delta

	# --- Arena wall clamping ---
	var wall_limit = 198.0
	global_position.x = clamp(global_position.x, -wall_limit, wall_limit)
	global_position.z = clamp(global_position.z, -wall_limit, wall_limit)
	# Kill speed if hitting a wall
	if abs(global_position.x) >= wall_limit or abs(global_position.z) >= wall_limit:
		speed *= 0.9

	# --- ALWAYS snap Y to ground. Every frame. No exceptions. ---
	global_position.y = _get_ground_height(global_position.x, global_position.z) + GROUND_OFFSET

	# --- Tilt truck to match terrain slope ---
	_align_to_terrain(delta)

	# --- Visuals ---
	_update_visuals(delta, steer_input)


func _align_to_terrain(delta: float) -> void:
	# Sample ground at 4 points around the truck to get slope
	var d = 1.5
	var pos = global_position
	var fwd = -transform.basis.z.normalized()
	var right_dir = transform.basis.x.normalized()

	var h_front = _get_ground_height(pos.x + fwd.x * d, pos.z + fwd.z * d)
	var h_back = _get_ground_height(pos.x - fwd.x * d, pos.z - fwd.z * d)
	var h_left = _get_ground_height(pos.x - right_dir.x * d, pos.z - right_dir.z * d)
	var h_right = _get_ground_height(pos.x + right_dir.x * d, pos.z + right_dir.z * d)

	# Pitch (forward/back tilt) and roll (left/right tilt)
	var target_pitch = atan2(h_front - h_back, d * 2.0)
	var target_roll = atan2(h_right - h_left, d * 2.0)

	# All visual tilt on body_mesh — root stays flat for steering math
	if body_mesh:
		var t = 8.0 * delta
		body_mesh.rotation.x = lerp(body_mesh.rotation.x, target_pitch, t)
		body_mesh.rotation.z = lerp(body_mesh.rotation.z, target_roll, t)


func _get_ground_height(x: float, z: float) -> float:
	# Must match main_setup.gd HILLS array
	var hills = [
		[0.0, -50.0, 12.0, 30.0],
		[80.0, 40.0, 8.0, 25.0],
		[-70.0, -30.0, 6.0, 20.0],
		[40.0, -100.0, 10.0, 22.0],
		[-50.0, 70.0, 5.0, 18.0],
	]
	var h = 0.0
	for hill in hills:
		var dx = x - hill[0]
		var dz = z - hill[1]
		var dist = sqrt(dx * dx + dz * dz)
		if dist < hill[3]:
			h += hill[2] * 0.5 * (1.0 + cos(PI * dist / hill[3]))
	return h


func _setup_dirt_particles() -> void:
	# CPUParticles3D behind each rear wheel for dirt kick-up
	var rear_positions = [
		Vector3(-1.4, 0.3, 1.8),  # behind left rear
		Vector3(1.4, 0.3, 1.8),   # behind right rear
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

		# Direction: spray backward and up
		particles.direction = Vector3(0, 1, 1)
		particles.spread = 25.0
		particles.initial_velocity_min = 2.0
		particles.initial_velocity_max = 5.0
		particles.gravity = Vector3(0, -8, 0)

		# Size
		particles.scale_amount_min = 0.15
		particles.scale_amount_max = 0.4

		# Color: brown dirt fading out
		particles.color = Color(0.45, 0.35, 0.2, 0.8)
		var color_ramp = Gradient.new()
		color_ramp.set_color(0, Color(0.5, 0.4, 0.25, 0.9))
		color_ramp.set_color(1, Color(0.4, 0.3, 0.2, 0.0))
		particles.color_ramp = color_ramp

		# Mesh for each particle — small sphere
		var particle_mesh = SphereMesh.new()
		particle_mesh.radius = 0.1
		particle_mesh.height = 0.2
		particles.mesh = particle_mesh

		body_mesh.add_child(particles)
		dirt_particles.append(particles)


func _update_visuals(delta: float, steer_input: float) -> void:
	# --- Front wheel steering ---
	var visual_steer = -steer_input * 0.5
	for pivot in front_pivots:
		if pivot:
			pivot.rotation.y = lerp(pivot.rotation.y, visual_steer, delta * 10.0)

	# --- Spin all wheels based on speed ---
	var spin_rate = speed * 2.0 * delta
	for i in range(wheel_meshes.size()):
		if wheel_meshes[i]:
			wheel_meshes[i].rotate_x(spin_rate)

	# --- Dirt kick-up particles proportional to speed ---
	var spd_ratio = clamp(abs(speed) / max(Settings.max_speed, 1.0), 0.0, 1.0)
	for p in dirt_particles:
		if spd_ratio > 0.1:
			p.emitting = true
			p.initial_velocity_min = 2.0 + spd_ratio * 6.0
			p.initial_velocity_max = 5.0 + spd_ratio * 10.0
			p.amount = int(10 + spd_ratio * 30)
		else:
			p.emitting = false

	# Body tilt is handled by _align_to_terrain


func _build_truck() -> void:
	var primary_color = Color(0.2, 0.35, 0.8)
	var chrome = Color(0.6, 0.6, 0.65)
	var dark_grey = Color(0.15, 0.15, 0.15)

	body_mesh = Node3D.new()
	body_mesh.name = "BodyMesh"
	add_child(body_mesh)

	# --- 1. FRAME / CHASSIS ---
	var frame = _make_box(Vector3(2.2, 0.2, 3.5), dark_grey)
	frame.position = Vector3(0, 1.0, 0)
	body_mesh.add_child(frame)

	# --- 2. TRUCK CAB ---
	# Lower body (hood + bed)
	truck_body = _make_box_metallic(Vector3(2.0, 0.8, 3.2), primary_color, 0.4)
	truck_body.position = Vector3(0, 1.5, 0)
	body_mesh.add_child(truck_body)

	# Cab (windowed part)
	var cab = _make_box_metallic(Vector3(1.8, 0.7, 1.4), primary_color.darkened(0.15), 0.4)
	cab.position = Vector3(0, 2.2, -0.3)
	body_mesh.add_child(cab)

	# Windshield
	var windshield = _make_box(Vector3(1.6, 0.5, 0.08), Color(0.5, 0.7, 1.0, 0.4))
	windshield.position = Vector3(0, 2.2, -1.0)
	windshield.rotation.x = deg_to_rad(-15)
	# Make windshield transparent
	var ws_mat = windshield.material_override as StandardMaterial3D
	ws_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mesh.add_child(windshield)

	# Rear window
	var rear_window = _make_box(Vector3(1.6, 0.45, 0.08), Color(0.5, 0.7, 1.0, 0.4))
	rear_window.position = Vector3(0, 2.2, 0.4)
	var rw_mat = rear_window.material_override as StandardMaterial3D
	rw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mesh.add_child(rear_window)

	# Truck bed (open back)
	var bed = _make_box_metallic(Vector3(2.0, 0.5, 1.2), primary_color, 0.4)
	bed.position = Vector3(0, 1.3, 1.3)
	body_mesh.add_child(bed)

	# --- 3. FRONT GRILLE ---
	var grille = _make_box_metallic(Vector3(1.8, 0.5, 0.1), chrome, 0.7)
	grille.position = Vector3(0, 1.5, -1.65)
	body_mesh.add_child(grille)

	# --- 4. BUMPERS ---
	var front_bumper = _make_box_metallic(Vector3(2.2, 0.2, 0.15), chrome, 0.7)
	front_bumper.position = Vector3(0, 1.1, -1.7)
	body_mesh.add_child(front_bumper)

	var rear_bumper = _make_box_metallic(Vector3(2.2, 0.2, 0.15), chrome, 0.7)
	rear_bumper.position = Vector3(0, 1.1, 1.85)
	body_mesh.add_child(rear_bumper)

	# --- 5. HEADLIGHTS ---
	var hl_color = Color(1.0, 0.9, 0.3)
	for x_pos in [-0.6, 0.6]:
		var hl = _make_box(Vector3(0.3, 0.2, 0.05), hl_color)
		hl.position = Vector3(x_pos, 1.6, -1.66)
		var hl_mat = hl.material_override as StandardMaterial3D
		hl_mat.emission_enabled = true
		hl_mat.emission = hl_color
		hl_mat.emission_energy_multiplier = 2.0
		body_mesh.add_child(hl)

	# --- 6. MONSTER WHEELS ---
	var wheel_positions = [
		Vector3(-1.4, 0.8, -1.1),  # FL
		Vector3(1.4, 0.8, -1.1),   # FR
		Vector3(-1.4, 0.8, 1.1),   # RL
		Vector3(1.4, 0.8, 1.1),    # RR
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

	# --- 7. SUSPENSION STRUTS ---
	for wp in wheel_positions:
		var strut = _make_cylinder(0.06, 0.8, dark_grey)
		strut.position = Vector3(wp.x * 0.7, 0.9, wp.z)
		body_mesh.add_child(strut)

	# --- 8. EXHAUST PIPES ---
	var exhaust_color = Color(0.2, 0.2, 0.22)
	for x_pos in [-0.5, 0.5]:
		var exhaust = _make_cylinder_metallic(0.06, 0.5, exhaust_color, 0.5)
		exhaust.position = Vector3(x_pos, 1.8, 1.5)
		body_mesh.add_child(exhaust)

	# No collision shape needed — we use math-based ground clamping


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.position = Vector3(0, 5.5, 10)
	camera.rotation.x = deg_to_rad(-12)
	camera.current = true
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
	# Parent node that gets rotate_x for spin
	var wheel_node = Node3D.new()

	# Tire (outer)
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

	# Rim (inner)
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
