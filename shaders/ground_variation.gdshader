shader_type canvas_item;

// Ground variation shader with rolling hills effect
// Creates illusion of undulating terrain through shading

// Dark stone grey - cool tint to counteract any warm bleed
uniform vec4 base_color : source_color = vec4(0.15, 0.15, 0.17, 1.0);
uniform float world_scale : hint_range(0.0001, 0.01) = 0.001;
uniform float intensity : hint_range(0.0, 1.0) = 0.75;  // Fine texture strength
uniform float hill_intensity : hint_range(0.0, 1.0) = 0.6;  // Rolling hills strength
uniform float hill_scale : hint_range(0.00001, 0.001) = 0.00008;  // Size of hills

// Gradient noise (Perlin-style) - no grid artifacts
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    // Quintic interpolation
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // Gradient noise - dot products with random gradients
    float a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
    float b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

    // Bilinear interpolation
    return 0.5 + 0.5 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal brownian motion for more natural noise
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

void fragment() {
    // World position (using UV scaled to world coordinates)
    vec2 world_pos = UV / world_scale;

    // Start with base color
    vec3 color = base_color.rgb;

    // === ROLLING HILLS LAYER: Gradient noise for smooth organic terrain ===
    // Gradient noise produces smooth continuous hills without grid artifacts
    float elevation = fbm(world_pos * hill_scale, 5);
    float hill_height = (elevation - 0.5) * 3.0;  // Wider range for more contrast

    // Strong shading - hilltops lighter, valleys darker
    float hill_shade = hill_height * 0.25 * hill_intensity;
    color += vec3(hill_shade);

    // Directional shadow for depth (light from top-left)
    vec2 offset_pos = world_pos + vec2(800.0, 500.0);
    float slope = fbm(offset_pos * hill_scale * 0.9, 4);
    float ridge_shadow = (slope - 0.5) * 0.18 * hill_intensity;
    color += vec3(ridge_shadow);

    // Color temperature shift - warm hilltops, cool valleys
    color.r += hill_height * 0.05 * hill_intensity;
    color.b -= hill_height * 0.03 * hill_intensity;

    // === LAYER 1: Large-scale color variation ===
    float large_variation = fbm(world_pos * 0.00015, 3);
    color += (large_variation - 0.5) * vec3(0.025, 0.022, 0.020) * intensity;

    // === LAYER 2: Fine grain texture (subtle speckles) ===
    float fine_grain = noise(world_pos * 0.005);
    color += (fine_grain - 0.5) * 0.045 * intensity;

    // === LAYER 3: Medium noise patches ===
    float medium_noise = fbm(world_pos * 0.0008, 2);
    color += (medium_noise - 0.5) * vec3(0.035, 0.030, 0.028) * intensity;

    // === LAYER 4: Scattered darker specks (subtle dirt/pebbles) ===
    float speck_noise = noise(world_pos * 0.010);
    float specks = smoothstep(0.65, 0.80, speck_noise) * 0.03 * intensity;
    color -= specks;

    // === LAYER 5: Lighter dust/ash patches ===
    float dust_noise = fbm(world_pos * 0.0005 + vec2(100.0, 200.0), 2);
    float dust = smoothstep(0.50, 0.65, dust_noise) * 0.04 * intensity;
    color += dust;

    // Clamp to valid range (expanded for visible hill variation)
    color = clamp(color, base_color.rgb - vec3(0.15), base_color.rgb + vec3(0.15));

    COLOR = vec4(color, 1.0);
}
