extends CharacterBody3D

var speed: float = 0.0
var steer_angle: float = 0.0
var kart_tilt: float = 0.0

# Node references
var body_mesh: Node3D
var front_pivots: Array = []  # [FL_pivot, FR_pivot] — rotate Y for steering
var wheel_meshes: Array = []  # [FL, FR, RL, RR] — rotate X for spin
var camera: Camera3D
var ground_ray: RayCast3D


func _ready() -> void:
	_build_kart()
	_setup_camera()
	_setup_ground_ray()


func _setup_ground_ray() -> void:
	ground_ray = RayCast3D.new()
	ground_ray.target_position = Vector3(0, -10, 0)
	ground_ray.enabled = true
	add_child(ground_ray)


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

	# Gamepad face buttons as fallback
	if Input.is_joy_button_pressed(0, JOY_BUTTON_A):
		throttle = max(throttle, 1.0)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_B):
		brake_input = max(brake_input, 1.0)

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
	var current_vel = Vector3(velocity.x, 0, velocity.z)
	var forward_speed_component = current_vel.dot(forward_dir)
	var lateral_component = current_vel - forward_dir * forward_speed_component
	var drifted_vel = forward_dir * speed + lateral_component * s.drift_factor
	velocity.x = drifted_vel.x
	velocity.z = drifted_vel.z

	# --- Gravity and ground detection ---
	var ground_y = _get_ground_height(global_position.x, global_position.z)
	var on_ground = global_position.y <= ground_y + 0.6

	if on_ground:
		velocity.y = 0
		global_position.y = ground_y + 0.5
	else:
		velocity.y -= s.gravity * delta

	move_and_slide()

	# --- Hard ground clamp after move_and_slide ---
	# Raycast method: detect actual collision surfaces
	if ground_ray and ground_ray.is_colliding():
		var ground_point = ground_ray.get_collision_point()
		if global_position.y < ground_point.y + 0.5:
			global_position.y = ground_point.y + 0.5
			if velocity.y < 0:
				velocity.y = 0
	else:
		# Fallback: sine wave height function
		ground_y = _get_ground_height(global_position.x, global_position.z)
		var min_y = ground_y + 0.5
		if global_position.y < min_y:
			global_position.y = min_y
			velocity.y = max(velocity.y, 0)

	# --- Visuals ---
	_update_visuals(delta, steer_input)


func _get_ground_height(x: float, z: float) -> float:
	# Gentle rolling hills using sine waves
	var h = 0.0
	h += sin(x * 0.02) * 1.5
	h += sin(z * 0.03) * 1.0
	h += sin(x * 0.05 + z * 0.04) * 0.5
	return h


func _update_visuals(delta: float, steer_input: float) -> void:
	# --- Front wheel steering ---
	# Pivot nodes rotate on Y for steering visual
	var visual_steer = steer_input * 0.5  # Max ~28 degrees
	for pivot in front_pivots:
		if pivot:
			pivot.rotation.y = lerp(pivot.rotation.y, visual_steer, delta * 10.0)

	# --- Spin all wheels based on speed ---
	var spin_rate = speed * 2.0 * delta
	for i in range(wheel_meshes.size()):
		if wheel_meshes[i]:
			wheel_meshes[i].rotate_x(spin_rate)

	# --- Kart body tilt into turns ---
	var target_tilt = -steer_angle * 0.05
	kart_tilt = lerp(kart_tilt, target_tilt, 5.0 * delta)
	if body_mesh:
		body_mesh.rotation.z = kart_tilt


func _build_kart() -> void:
	body_mesh = Node3D.new()
	body_mesh.name = "BodyMesh"
	add_child(body_mesh)

	# Main body - blue
	var body_box = _make_box(Vector3(2.0, 0.7, 3.0), Color(0.2, 0.35, 0.8))
	body_box.position = Vector3(0, 0.55, 0)
	body_mesh.add_child(body_box)

	# Cockpit/seat - white
	var seat = _make_box(Vector3(1.2, 0.5, 1.0), Color(0.9, 0.9, 0.9))
	seat.position = Vector3(0, 1.05, 0.2)
	body_mesh.add_child(seat)

	# Nose wedge - darker blue
	var nose = _make_box(Vector3(1.6, 0.4, 0.8), Color(0.15, 0.25, 0.6))
	nose.position = Vector3(0, 0.45, -1.4)
	body_mesh.add_child(nose)

	# Rear bumper
	var bumper = _make_box(Vector3(2.2, 0.35, 0.3), Color(0.3, 0.3, 0.3))
	bumper.position = Vector3(0, 0.45, 1.6)
	body_mesh.add_child(bumper)

	# Wheel positions: [FL, FR, RL, RR]
	var wheel_positions = [
		Vector3(-1.1, 0.35, -1.0),  # FL
		Vector3(1.1, 0.35, -1.0),   # FR
		Vector3(-1.1, 0.35, 1.0),   # RL
		Vector3(1.1, 0.35, 1.0),    # RR
	]

	front_pivots = []
	wheel_meshes = []

	for i in range(4):
		var is_front = i < 2
		var wheel = _make_wheel(0.35, 0.25)

		if is_front:
			# Front wheels: pivot node for steering, wheel mesh as child for spin
			var pivot = Node3D.new()
			pivot.name = "WheelPivot_%d" % i
			pivot.position = wheel_positions[i]
			body_mesh.add_child(pivot)

			wheel.position = Vector3.ZERO  # local to pivot
			pivot.add_child(wheel)

			front_pivots.append(pivot)
			wheel_meshes.append(wheel)
		else:
			# Rear wheels: directly on body, only spin
			wheel.position = wheel_positions[i]
			body_mesh.add_child(wheel)
			wheel_meshes.append(wheel)

	# Collision shape
	var col = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(2.0, 0.8, 3.0)
	col.shape = box_shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.position = Vector3(0, 4, 8)
	camera.rotation_degrees = Vector3(-20, 0, 0)
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


func _make_wheel(radius: float, width: float) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	mesh_inst.mesh = cyl
	mesh_inst.rotation_degrees = Vector3(0, 0, 90)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15)
	mesh_inst.material_override = mat
	return mesh_inst
