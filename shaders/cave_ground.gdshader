shader_type canvas_item;

// Cave ground shader for Polygon2D nodes
// Uses FRAGCOORD (screen position) for consistent texture across polygons

uniform vec4 base_color : source_color = vec4(0.12, 0.11, 0.10, 1.0);
uniform float world_scale : hint_range(0.00001, 0.001) = 0.0001;
uniform float intensity : hint_range(0.0, 1.0) = 0.75;

// Noise functions
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
    // Use screen position for consistent texture across all polygons
    vec2 screen_pos = FRAGCOORD.xy * world_scale;

    // Start with base color
    vec3 color = base_color.rgb;

    // === LAYER 1: Large-scale variation ===
    float large_variation = fbm(screen_pos * 0.15, 3);
    // Warm brown variation for cave
    color += (large_variation - 0.5) * vec3(0.008, 0.007, 0.006) * intensity;

    // === LAYER 2: Fine grain texture (small speckles) ===
    float fine_grain = noise(screen_pos * 0.8);
    color += (fine_grain - 0.5) * 0.03 * intensity;

    // === LAYER 3: Medium noise for color shifts ===
    float medium_noise = fbm(screen_pos * 0.4, 2);
    // Warm brown shifts
    color += (medium_noise - 0.5) * vec3(0.01, 0.009, 0.008) * intensity;

    // === LAYER 4: Scattered darker specks ===
    float speck_noise = noise(screen_pos * 1.5);
    float specks = smoothstep(0.55, 0.75, speck_noise) * 0.04 * intensity;
    color -= specks;

    // === LAYER 5: Faint lighter dust patches ===
    float dust_noise = fbm(screen_pos * 0.3 + vec2(100.0, 200.0), 2);
    float dust = smoothstep(0.55, 0.7, dust_noise) * 0.015 * intensity;
    color += dust;

    // Clamp to valid range
    color = clamp(color, base_color.rgb - vec3(0.06), base_color.rgb + vec3(0.04));

    COLOR = vec4(color, 1.0);
}
