extends CharacterBody3D

var speed: float = 0.0
var steer_angle: float = 0.0
var visual_wheel_angle: float = 0.0
var kart_tilt: float = 0.0

# Node references
var body_mesh: Node3D
var wheels: Array = []  # [FL, FR, RL, RR]
var camera: Camera3D


func _ready() -> void:
	_build_kart()
	_setup_camera()


func _physics_process(delta: float) -> void:
	var s := Settings  # shorthand, reads every frame

	# --- Input ---
	var throttle := 0.0
	var brake_input := 0.0
	var steer_input := 0.0

	# Keyboard
	if Input.is_action_pressed("accelerate"):
		throttle = 1.0
	if Input.is_action_pressed("brake"):
		brake_input = 1.0

	# Gamepad analog triggers (device 0)
	var rt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
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
	var stick_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
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
		var direction_mult := 1.0 if speed >= 0.0 else -1.0
		var target_steer = steer_input * s.turn_speed * turn_reduction * direction_mult
		steer_angle = lerp(steer_angle, target_steer, s.drift_turn_boost * delta)
	else:
		steer_angle = move_toward(steer_angle, 0.0, s.return_to_center * delta)

	if abs(steer_input) < 0.1 and abs(speed) > 0.5:
		steer_angle = move_toward(steer_angle, 0.0, s.return_to_center * delta)

	# --- Apply rotation ---
	rotate_y(-steer_angle * delta)

	# --- Drift / lateral friction ---
	var forward_dir := -transform.basis.z.normalized()
	var current_vel := Vector3(velocity.x, 0, velocity.z)
	var forward_speed_component := current_vel.dot(forward_dir)
	var lateral_component := current_vel - forward_dir * forward_speed_component
	var drifted_vel := forward_dir * speed + lateral_component * s.drift_factor
	velocity.x = drifted_vel.x
	velocity.z = drifted_vel.z

	# --- Gravity and ground snap ---
	var ground_y := _get_ground_height(global_position.x, global_position.z)
	if global_position.y <= ground_y + 0.05:
		global_position.y = ground_y
		velocity.y = 0.0
	else:
		velocity.y -= s.gravity * delta

	move_and_slide()

	# Snap to ground after move
	ground_y = _get_ground_height(global_position.x, global_position.z)
	if global_position.y < ground_y:
		global_position.y = ground_y
		velocity.y = 0.0

	# --- Visuals ---
	_update_visuals(delta)


func _get_ground_height(x: float, z: float) -> float:
	# Gentle rolling hills using sine waves
	var h := 0.0
	h += sin(x * 0.02) * 1.5
	h += sin(z * 0.03) * 1.0
	h += sin(x * 0.05 + z * 0.04) * 0.5
	return h


func _update_visuals(delta: float) -> void:
	# Wheel steering visual
	var target_visual = clamp(steer_angle * 0.4, -0.6, 0.6)
	visual_wheel_angle = lerp(visual_wheel_angle, target_visual, 10.0 * delta)

	# Spin all wheels based on speed
	var spin_rate := speed * 2.0 * delta
	for i in range(4):
		if wheels[i]:
			wheels[i].rotate_x(spin_rate)
			# Front wheels turn with steering
			if i < 2:
				wheels[i].rotation.y = visual_wheel_angle

	# Kart body tilt into turns
	var target_tilt := -steer_angle * 0.05
	kart_tilt = lerp(kart_tilt, target_tilt, 5.0 * delta)
	if body_mesh:
		body_mesh.rotation.z = kart_tilt


func _build_kart() -> void:
	body_mesh = Node3D.new()
	body_mesh.name = "BodyMesh"
	add_child(body_mesh)

	# Main body - blue
	var body_box := _make_box(Vector3(2.0, 0.7, 3.0), Color(0.2, 0.35, 0.8))
	body_box.position = Vector3(0, 0.55, 0)
	body_mesh.add_child(body_box)

	# Cockpit/seat - white
	var seat := _make_box(Vector3(1.2, 0.5, 1.0), Color(0.9, 0.9, 0.9))
	seat.position = Vector3(0, 1.05, 0.2)
	body_mesh.add_child(seat)

	# Nose wedge - darker blue
	var nose := _make_box(Vector3(1.6, 0.4, 0.8), Color(0.15, 0.25, 0.6))
	nose.position = Vector3(0, 0.45, -1.4)
	body_mesh.add_child(nose)

	# Rear bumper
	var bumper := _make_box(Vector3(2.2, 0.35, 0.3), Color(0.3, 0.3, 0.3))
	bumper.position = Vector3(0, 0.45, 1.6)
	body_mesh.add_child(bumper)

	# Wheels
	var wheel_positions := [
		Vector3(-1.1, 0.35, -1.0),  # FL
		Vector3(1.1, 0.35, -1.0),   # FR
		Vector3(-1.1, 0.35, 1.0),   # RL
		Vector3(1.1, 0.35, 1.0),    # RR
	]
	wheels = []
	for pos in wheel_positions:
		var wheel := _make_wheel(0.35, 0.25)
		wheel.position = pos
		body_mesh.add_child(wheel)
		wheels.append(wheel)

	# Collision shape
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
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
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	return mesh_inst


func _make_wheel(radius: float, width: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	mesh_inst.mesh = cyl
	mesh_inst.rotation_degrees = Vector3(0, 0, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15)
	mesh_inst.material_override = mat
	return mesh_inst
