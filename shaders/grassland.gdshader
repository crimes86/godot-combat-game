shader_type canvas_item;

// Grassland shader - Procedural variation for natural-looking grass
// Inspired by classic MMO grasslands (EQ Commonlands, etc.)
// Creates patchy, varied grass without being a flat blob
// Uses world coordinates for proper scaling on Polygon2D

// Base grass colors
uniform vec4 grass_base : source_color = vec4(0.18, 0.35, 0.12, 1.0);     // Medium green
uniform vec4 grass_dark : source_color = vec4(0.10, 0.25, 0.08, 1.0);     // Dark patches (shadows, thick growth)
uniform vec4 grass_light : source_color = vec4(0.28, 0.45, 0.18, 1.0);    // Light patches (sun-bleached)
uniform vec4 grass_yellow : source_color = vec4(0.35, 0.40, 0.15, 1.0);   // Dry/dead patches
uniform vec4 dirt_color : source_color = vec4(0.25, 0.20, 0.12, 1.0);     // Exposed dirt patches

uniform float patch_scale : hint_range(0.1, 5.0) = 1.0;                    // Scale of color patches
uniform float detail_intensity : hint_range(0.0, 1.0) = 0.7;               // Fine detail strength
uniform float patch_intensity : hint_range(0.0, 1.0) = 0.8;                // Large patch variation
uniform float dirt_amount : hint_range(0.0, 0.3) = 0.08;                   // Amount of exposed dirt

// World coordinates from vertex shader
varying vec2 world_pos;

// Noise functions
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Voronoi for organic patches
float voronoi(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    float min_dist = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 cell_pos = neighbor + hash(i + neighbor) * 0.8 + 0.1;
            float dist = length(cell_pos - f);
            min_dist = min(min_dist, dist);
        }
    }
    return min_dist;
}

// Fractal brownian motion
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

void vertex() {
    // Get world position from model matrix for proper scaling on Polygon2D
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // Use world coordinates passed from vertex shader
    // NO VORONOI - just smooth FBM noise like cave shader

    // Start with base green
    vec3 color = grass_base.rgb;

    // === LAYER 1: Large-scale subtle variation (reduced color drift) ===
    float large_variation = fbm(world_pos * 0.0005, 3);
    color += (large_variation - 0.5) * vec3(0.003, 0.005, 0.002) * detail_intensity;

    // === LAYER 2: Medium variation for color shifts (reduced) ===
    float medium_noise = fbm(world_pos * 0.0016, 2);
    color += (medium_noise - 0.5) * vec3(0.004, 0.006, 0.003) * detail_intensity;

    // === LAYER 3: Grass clump patterns (reduced) ===
    float clump_noise = fbm(world_pos * 0.003, 3);
    float clump_variation = (clump_noise - 0.5) * 0.015 * detail_intensity;
    color += clump_variation;

    // === LAYER 4: Fine grain texture (reduced) ===
    float grass_texture = noise(world_pos * 0.012);
    float fine_detail = (grass_texture - 0.5) * 0.01 * detail_intensity;
    color += fine_detail;

    // === LAYER 5: Tiny specks (reduced) ===
    float speck = noise(world_pos * 0.04);
    float specks = smoothstep(0.6, 0.9, speck) * 0.008 * detail_intensity;
    color -= specks;

    // === LAYER 6: Soft dirt hints (reduced) ===
    float dirt_noise = fbm(world_pos * 0.0024 + vec2(200.0, 100.0), 2);
    float dirt_mask = smoothstep(0.55, 0.75, dirt_noise) * dirt_amount;
    color = mix(color, dirt_color.rgb, dirt_mask * 0.15);

    // === LAYER 7: Shadow dappling (reduced) ===
    float shadow_noise = fbm(world_pos * 0.0008 + vec2(1000.0, 500.0), 2);
    float shadow = smoothstep(0.5, 0.8, shadow_noise) * 0.012;
    color -= shadow;

    // Clamp to reasonable range
    color = clamp(color, vec3(0.02), vec3(0.5));

    COLOR = vec4(color, 1.0);
}
