#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;


// --------------------------------------------------
// GPU DATA
// --------------------------------------------------

struct Sphere {
    vec4 center_radius;
    vec4 material;
};

layout(set = 0, binding = 0, std430)

readonly buffer SphereBuffer {
    Sphere spheres[];
};


// Output image
layout(set = 0, binding = 1, rgba8)
uniform writeonly image2D output_image;


// Texture slots
layout(set = 0, binding = 2)
uniform sampler2D texture0;

layout(set = 0, binding = 3)
uniform sampler2D texture1;

layout(set = 0, binding = 4)
uniform sampler2D texture2;

layout(set = 0, binding = 5)
uniform sampler2D texture3;


// --------------------------------------------------
// CAMERA PARAMETERS
// --------------------------------------------------


layout(push_constant, std430) uniform CameraData {

    vec4 camera_origin;
    vec4 camera_right;
    vec4 camera_up;
    vec4 camera_forward;

    // Width, height, aspect ratio, tan(FOV/2).
    vec4 image_info;

    // Number of active spheres.
    vec4 scene_info;

    // Texture rotation angle in radians.
    vec4 texture_info;

} camera;


// --------------------------------------------------
// TEXTURE LOOKUP
// --------------------------------------------------

vec3 sample_material(int material_id, vec2 uv) {

    if (material_id == 0) {
        return texture(texture0, uv).rgb;
    }

    if (material_id == 1) {
        return texture(texture1, uv).rgb;
    }

    if (material_id == 2) {
        return texture(texture2, uv).rgb;
    }

    if (material_id == 3) {
        return texture(texture3, uv).rgb;
    }

    return vec3(1.0, 0.0, 1.0);
}


// --------------------------------------------------
// RAY-SPHERE INTERSECTION
// --------------------------------------------------

float intersect_sphere(
    vec3 ray_origin,
    vec3 ray_direction,
    vec3 sphere_center,
    float sphere_radius
) {

    vec3 oc = ray_origin - sphere_center;

    float b = dot(oc, ray_direction);
    float c = dot(oc, oc) - sphere_radius * sphere_radius;

    float discriminant = b * b - c;

    if (discriminant < 0.0) {
        return -1.0;
    }

    float t = -b - sqrt(discriminant);

    if (t < 0.0) {
        t = -b + sqrt(discriminant);
    }

    if (t < 0.0) {
        return -1.0;
    }

    return t;
}


// --------------------------------------------------
// SPHERICAL TEXTURE COORDINATES
// --------------------------------------------------


vec2 sphere_uv(vec3 normal, float rotation_angle) {

    // Calculate longitude.
    float u = atan(normal.z, normal.x) /
              (2.0 * 3.14159265) + 0.5;

    // Calculate latitude.
    float v = acos(
        clamp(normal.y, -1.0, 1.0)
    ) / 3.14159265;

    // Rotate texture around the polar axis.
    u += rotation_angle / (2.0 * 3.14159265);

    // Wrap texture coordinates.
    u = fract(u);

    return vec2(u, v);
}

// --------------------------------------------------
// MAIN COMPUTE FUNCTION
// --------------------------------------------------

void main() {

    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

    ivec2 image_size = imageSize(output_image);

    // Prevent out-of-bounds writes.
    if (pixel.x >= image_size.x ||
        pixel.y >= image_size.y) {
        return;
    }


    // --------------------------------------------------
    // GENERATE CAMERA RAY
    // --------------------------------------------------

    vec2 uv = (vec2(pixel) + vec2(0.5)) /
              vec2(image_size);

    vec2 ndc = uv * 2.0 - 1.0;

    // Flip Y axis to align the ray direction with the camera coordinates.
    ndc.y = -ndc.y;

    float aspect = camera.image_info.z;
    float tan_half_fov = camera.image_info.w;

    vec3 ray_origin = camera.camera_origin.xyz;

    vec3 ray_direction = normalize(
        camera.camera_forward.xyz
        + camera.camera_right.xyz * ndc.x * aspect * tan_half_fov
        + camera.camera_up.xyz * ndc.y * tan_half_fov
    );


    // --------------------------------------------------
    // INTERSECT ALL SPHERES
    // --------------------------------------------------

    
    
    // start with t at infinity
    float closest_t = 3e30;

    int closest_sphere = -1;
    int sphere_count = int(camera.scene_info.x);

    for (int i = 0; i < sphere_count; i++) {
        vec3 center = spheres[i].center_radius.xyz;
        float radius = spheres[i].center_radius.w;
        float t = intersect_sphere(
            ray_origin,
            ray_direction,
            center,
            radius
        );

        if (t > 0.0 && t < closest_t) {

            closest_t = t;
            closest_sphere = i;

        }
    }


    // --------------------------------------------------
    // SHADE
    // --------------------------------------------------

    vec3 color;

    if (closest_sphere >= 0) {

        Sphere sphere = spheres[closest_sphere];

        vec3 hit_position =
            ray_origin + closest_t * ray_direction;

        vec3 normal = normalize(
            hit_position - sphere.center_radius.xyz
        );

        float rotation_angle = camera.texture_info.x;
	  vec2 tex_uv = sphere_uv(normal, rotation_angle);

        int material_id = int(sphere.material.x);

        color = sample_material(material_id, tex_uv);

        // Simple directional lighting.
        vec3 light_direction = normalize(
            vec3(-1.0, 1.0, 2.0)
        );

        float diffuse = max(
            dot(normal, light_direction),
            0.0
        );

        float ambient = 0.2;

        color *= ambient + 0.8 * diffuse;

    }
    else {

        // Background gradient.
        float t = 0.5 * (ray_direction.y + 1.0);

        color = mix(
            vec3(0.05, 0.05, 0.08),
            vec3(0.25, 0.35, 0.5),
            t
        );

    }

    // Finally store the pixel to the image
    imageStore(
        output_image,
        pixel,
        vec4(color, 1.0)
    );
}

