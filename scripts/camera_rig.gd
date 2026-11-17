
extends Node3D

@export var target := Vector3.ZERO
@export var distance := 8.0

@export var min_distance := 2.0
@export var max_distance := 30.0

@export var orbit_sensitivity := 0.005
@export var zoom_sensitivity := 0.8
@export var pan_sensitivity := 0.01

@onready var camera: Camera3D = $Camera3D

var yaw := 0.0
var pitch := 0.0

var rotating := false
var panning := false

var last_mouse_position := Vector2.ZERO


func _ready():
	pitch = 0.25
	update_camera()


func _unhandled_input(event):

	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_LEFT:
			rotating = event.pressed

		if event.button_index == MOUSE_BUTTON_RIGHT:
			panning = event.pressed

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed

		if event.pressed:

			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				distance -= zoom_sensitivity
				distance = max(distance, min_distance)
				update_camera()

			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				distance += zoom_sensitivity
				distance = min(distance, max_distance)
				update_camera()

		last_mouse_position = event.position


	elif event is InputEventMouseMotion:

		var delta = event.position - last_mouse_position

		if rotating:

			yaw -= delta.x * orbit_sensitivity
			pitch -= delta.y * orbit_sensitivity

			pitch = clamp(
				pitch,
				-1.5,
				1.5
			)

			update_camera()

		elif panning:

			var right = camera.global_transform.basis.x
			var up = camera.global_transform.basis.y

			target -= right * delta.x * pan_sensitivity
			target += up * delta.y * pan_sensitivity

			update_camera()

		last_mouse_position = event.position


func update_camera():

	var direction = Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	)

	camera.position = target + direction * distance
	camera.look_at(target, Vector3.UP)
