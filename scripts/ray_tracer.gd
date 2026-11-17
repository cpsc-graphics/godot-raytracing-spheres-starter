
extends Node
const COMPUTE_SHADER_PATH = "res://shaders/raytrace.glsl"


# starting image dimensions
const WIDTH = 1024
const HEIGHT = 1024

# Typical workgroups consits of 8x8 thread blocks
const WORKGROUP_SIZE = 8

# Texture slots are exposed in the inspector
@export var texture_slots: Array[Texture2D] = []
@export var camera_path: NodePath = ^"../CameraRig/Camera3D"
@export var display_path: NodePath = \
    "../CanvasLayer/TextureRect"

# The animation is controlled by a single state variable that
# is manipulated via keyboard controls.
var rotation_radians := 0.0
@export var rotation_speed := 1.5

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var uniform_set: RID

var output_texture: RID
var sphere_buffer: RID
var sampler: RID

var gpu_textures: Array[RID] = []
var display_texture: ImageTexture

var camera: Camera3D
var display: TextureRect

var initialized := false


# --------------------------------------------------
# SPHERE DATA
# --------------------------------------------------

# Each sphere has:
# Center XYZ, radius, material ID
#
# Sphere data is pused to the compute shader

var sphere_data = [
	{
		"center": Vector3(0.0, 0.0, 0.0),
		"radius": 1.5,
		"material": 0
	}
	# add additional spheres as needed
	#,
	#{
	#	"center": Vector3(0.0, 0.0, 0.0),
	#	"radius": 1.0,
	#	"material": 1
	#},
	#{
	#	"center": Vector3(1.8, 0.0, 0.0),
	#	"radius": 1.0,
	#	"material": 2
	#},
	#{
	#	"center": Vector3(0.0, 2.0, -1.0),
	#	"radius": 0.65,
	#	"material": 3
	#}
]


# --------------------------------------------------
# INITIALIZATION
# --------------------------------------------------

func _ready():

	camera = get_node(camera_path)
	display = get_node(display_path)

	rd = RenderingServer.create_local_rendering_device()

	if rd == null:
		push_error("Could not create RenderingDevice.")
		return

	create_compute_shader()
	create_output_texture()
	create_sphere_buffer()
	create_sampler()
	create_input_textures()
	create_uniform_set()

	display_texture = ImageTexture.create_from_image(
		Image.create(
			WIDTH,
			HEIGHT,
			false,
			Image.FORMAT_RGBA8
		)
	)

	display.texture = display_texture
	initialized = true


# --------------------------------------------------
# CREATE COMPUTE SHADER
# --------------------------------------------------

func create_compute_shader():
	var shader_file = load(COMPUTE_SHADER_PATH) as RDShaderFile

	if shader_file == null:
		push_error("Could not load compute shader.")
		return

	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)


# --------------------------------------------------
# CREATE OUTPUT STORAGE IMAGE
# --------------------------------------------------

func create_output_texture():
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D

	format.width = WIDTH
	format.height = HEIGHT

	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1

	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	output_texture = rd.texture_create(
		format,
		RDTextureView.new()
	)


# --------------------------------------------------
# CREATE SPHERE STORAGE BUFFER
# --------------------------------------------------

func create_sphere_buffer():
	var data := PackedFloat32Array()

	for sphere in sphere_data:
		var center: Vector3 = sphere["center"]
		var radius: float = sphere["radius"]
		var material: int = sphere["material"]

		# First vec4: center.xyz, radius.
		data.append(center.x)
		data.append(center.y)
		data.append(center.z)
		data.append(radius)

		# Second vec4: material ID, padding.
		data.append(float(material))
		data.append(0.0)
		data.append(0.0)
		data.append(0.0)

	var bytes = data.to_byte_array()

	sphere_buffer = rd.storage_buffer_create(
		bytes.size(),
		bytes
	)


# --------------------------------------------------
# CREATE SAMPLER FOR TEXTURE(s)
# --------------------------------------------------

func create_sampler():
	var sampler_state := RDSamplerState.new()

	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR

	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT

	sampler = rd.sampler_create(sampler_state)


# --------------------------------------------------
# CREATE A FALLBACK TEXTURE
# --------------------------------------------------

func create_fallback_texture() -> Texture2D:

	var image := Image.create(
		2,
		2,
		false,
		Image.FORMAT_RGBA8
	)

	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


# --------------------------------------------------
# LOAD TEXTURES INTO RENDERINGDEVICE
# --------------------------------------------------

func create_input_textures():

	for i in range(4):
		var source_texture: Texture2D

		if i < texture_slots.size() and texture_slots[i] != null:
			source_texture = texture_slots[i]
		else:
			source_texture = create_fallback_texture()

		var image := source_texture.get_image()

		image.convert(Image.FORMAT_RGBA8)
		var format := RDTextureFormat.new()

		format.texture_type = RenderingDevice.TEXTURE_TYPE_2D

		format.width = image.get_width()
		format.height = image.get_height()

		format.depth = 1
		format.array_layers = 1
		format.mipmaps = 1

		format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM

		format.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		)

		var texture_rid = rd.texture_create(
			format,
			RDTextureView.new(),
			[image.get_data()]
		)

		gpu_textures.append(texture_rid)


# --------------------------------------------------
# CREATE UNIFORM SET. 
# Uniform buffers will be sent to the shader
# --------------------------------------------------

func create_uniform_set():
	var uniforms: Array[RDUniform] = []
	
	# Binding 0: Sphere buffer.

	var sphere_uniform := RDUniform.new()
	sphere_uniform.uniform_type = \
		RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER

	sphere_uniform.binding = 0
	sphere_uniform.add_id(sphere_buffer)

	uniforms.append(sphere_uniform)


	# Binding 1: Output storage image.

	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = \
		RenderingDevice.UNIFORM_TYPE_IMAGE

	output_uniform.binding = 1
	output_uniform.add_id(output_texture)

	uniforms.append(output_uniform)

	# Bindings 2-5: Texture slots.
	for i in range(4):
		var texture_uniform := RDUniform.new()

		texture_uniform.uniform_type = \
			RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE

		texture_uniform.binding = i + 2
		texture_uniform.add_id(sampler)
		texture_uniform.add_id(gpu_textures[i])

		uniforms.append(texture_uniform)


	uniform_set = rd.uniform_set_create(
		uniforms,
		shader,
		0
	)


# --------------------------------------------------
# CAMERA PUSH CONSTANTS
# Camera parameters are better sent as push constants
# as camera parameters can change on a per frame basis. 
# --------------------------------------------------

func get_camera_data() -> PackedByteArray:

	var transform = camera.global_transform
	var origin = transform.origin
	var right = transform.basis.x.normalized()
	var up = transform.basis.y.normalized()
	var forward = -transform.basis.z.normalized()
	var aspect = float(WIDTH) / float(HEIGHT)

	var tan_half_fov = tan(
		deg_to_rad(camera.fov) * 0.5
	)

	var data := PackedFloat32Array()
	
	# Camera origin.
	data.append_array(PackedFloat32Array([
		origin.x, origin.y, origin.z, 0.0
	]))

	# Camera right.
	data.append_array(PackedFloat32Array([
		right.x, right.y, right.z, 0.0
	]))

	# Camera up.
	data.append_array(PackedFloat32Array([
		up.x, up.y, up.z, 0.0
	]))

	# Camera forward.
	data.append_array(PackedFloat32Array([
		forward.x, forward.y, forward.z, 0.0
	]))

	# Image information.
	data.append_array(PackedFloat32Array([
		float(WIDTH),
		float(HEIGHT),
		aspect,
		tan_half_fov
	]))

	# Scene information.
	data.append_array(PackedFloat32Array([
		float(sphere_data.size()),
		0.0,
		0.0,
		0.0
	]))
	
	# Rotation information / animation state
	data.append_array(PackedFloat32Array([
		rotation_radians,
		0.0,
		0.0,
		0.0
	]))

	return data.to_byte_array()


# --------------------------------------------------
# DISPATCH COMPUTE SHADER
# --------------------------------------------------

func render_frame():

	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(
		compute_list,
		pipeline
	)

	rd.compute_list_bind_uniform_set(
		compute_list,
		uniform_set,
		0
	)

	var camera_bytes = get_camera_data()

	rd.compute_list_set_push_constant(
		compute_list,
		camera_bytes,
		camera_bytes.size()
	)

	var groups_x = ceili(float(WIDTH) / WORKGROUP_SIZE)

	var groups_y = ceili(float(HEIGHT) / WORKGROUP_SIZE)

	rd.compute_list_dispatch(
		compute_list,
		groups_x,
		groups_y,
		1
	)

	rd.compute_list_end()

	# Execute and synchronize.

	rd.submit()
	rd.sync()

	# Read the resulting image.

	var image_data = rd.texture_get_data(
		output_texture,
		0
	)

	var image := Image.create_from_data(
		WIDTH,
		HEIGHT,
		false,
		Image.FORMAT_RGBA8,
		image_data
	)

	display_texture.update(image)


# --------------------------------------------------
# UPDATE
# --------------------------------------------------

func _process(delta):
	if not initialized:
		return

	# Rotate using keyboard input.
	if Input.is_action_pressed("rotate_left"):
		rotation_radians -= rotation_speed * delta

	if Input.is_action_pressed("rotate_right"):
		rotation_radians += rotation_speed * delta

	render_frame()




# --------------------------------------------------
# CLEANUP
# --------------------------------------------------

func _exit_tree():

	if rd == null:
		return

	if uniform_set.is_valid():
		rd.free_rid(uniform_set)

	if pipeline.is_valid():
		rd.free_rid(pipeline)

	if shader.is_valid():
		rd.free_rid(shader)

	if sphere_buffer.is_valid():
		rd.free_rid(sphere_buffer)

	if output_texture.is_valid():
		rd.free_rid(output_texture)

	if sampler.is_valid():
		rd.free_rid(sampler)

	for texture_rid in gpu_textures:
		if texture_rid.is_valid():
			rd.free_rid(texture_rid)
