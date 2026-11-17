# Raytracing Spheres in Realtime in Godot

## 1. Overview

This Godot 4 project implements a simple ray tracer using a **compute shader**. The application provides the camera controls, scene data, textures, and GPU setup.

The core ray tracing functionality is implemeted in:

**`shaders/raytrace.glsl`**

For the most part, you should not need to modify the GDScript files or the scene setup.

## 2. Project Structure

| File | Purpose |
|---|---|
| `scenes/main.tscn` | Main scene containing the camera, ray tracer, and output display |
| `scripts/camera_rig.gd` | Handles mouse-based camera controls |
| `scripts/ray_tracer.gd` | Sets up GPU resources, sends scene and camera data, and runs the compute shader |
| `shaders/raytrace.glsl` | Compute shader containing the ray tracing implementation |
| `textures/` | Texture images to be used in the scene |

The ray tracer renders an image on the GPU and displays the result in a `TextureRect`.

## 3. Scene Data and GPU Inputs

The GDScript code prepares the data required by the compute shader. You should understand the following inputs, but do not need to implement their transfer to the GPU.

**Sphere data**

Sphere information is stored in a GPU storage buffer. Each sphere has:
- A 3D center position
- A radius
- A material/texture identifier

The current scene contains one active sphere. The data structure supports adding more spheres.

**Textures**

Four texture slots are provided to the shader. They are assigned through the `RayTracer` node's Inspector properties. The shader accesses them through the corresponding texture bindings.

The current sphere uses one of these textures. The remaining slots are available for extending the scene.

**Camera and rendering parameters**

Camera information and rendering parameters are sent to the shader using push constants. These include:

- Camera position
- Camera right, up, and forward directions
- Image width and height
- Image aspect ratio and field of view
- Number of active spheres
- rotation angle 

The rotation angle is currently used to rotate the active texture. It can also be used
to control additional transformations as long as the entire animation state is described 
by a single state variable. 

The GDScript code packages these values and sends them to the GPU each frame. The order and layout of these values must match the declarations in `raytrace.glsl`.

**Texture rotation**

Use the **Left** and **Right** arrow keys to rotate the sphere's texture around its polar axis. This does not rotate the sphere or the camera. Instead, the rotation angle is passed to the shader, which uses it to adjust the texture's horizontal (longitude) coordinate.

## 4. Controls

| Input | Action |
|---|---|
| Left mouse drag | Orbit the camera |
| Right/middle mouse drag | Pan the camera |
| Mouse wheel | Zoom in/out |
| Left arrow | Rotate texture left |
| Right arrow | Rotate texture right |

## 5. Simple Exploration Tasks

Launch the project in Godot 4 and ensure that it runs without any issues, and the 
controls are behaving as expected.

The provided GDScript and scene files handle:
- Camera interaction
- Sphere and texture data
- GPU resource creation and binding
- Passing camera and animation parameters
- Compute shader execution and image display

This project focuses on ray tracing algorithms and shader implementation. As a starting point, you can try some of the following tasks which should only require modifications to the
compute shader.

- Apply scaling and/or translation transformations to the sphere (in the compute shader). 
- Add additional textures to the texture slots in the Godot inspector; render the sphere with
  different textures.
- Change the background colour.

**Important:** Keep the existing shader interface, including its resource bindings and push-constant layout, unchanged. The provided application code depends on these declarations to communicate with the shader.