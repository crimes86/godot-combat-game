shader_type canvas_item;

// Ground variation shader - SUBTLE visual interest without additional nodes
// Designed to be barely noticeable but add texture to flat ground

uniform vec4 base_color : source_color = vec4(0.09, 0.085, 0.08, 1.0);
uniform float world_scale : hint_range(0.0001, 0.01) = 0.001;
uniform float intensity : hint_range(0.0, 1.0) = 0.3;  // Overall effect strength

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
    // World position (using UV scaled to world coordinates)
    vec2 world_pos = UV / world_scale;

    // Start with base color
    vec3 color = base_color.rgb;

    // === LAYER 1: Very subtle large-scale variation (barely visible) ===
    float large_variation = fbm(world_pos * 0.00015, 3);
    color += (large_variation - 0.5) * vec3(0.008, 0.006, 0.003) * intensity;

    // === LAYER 2: Fine grain texture (small speckles) ===
    float fine_grain = noise(world_pos * 0.008);
    color += (fine_grain - 0.5) * 0.025 * intensity;

    // === LAYER 3: Medium noise for slight color shifts ===
    float medium_noise = fbm(world_pos * 0.0004, 2);
    color += (medium_noise - 0.5) * vec3(0.012, 0.008, 0.004) * intensity;

    // === LAYER 4: Tiny scattered darker specks ===
    float speck_noise = noise(world_pos * 0.015);
    float specks = smoothstep(0.7, 0.8, speck_noise) * 0.02 * intensity;
    color -= specks;

    // === LAYER 5: Very faint lighter dust patches ===
    float dust_noise = fbm(world_pos * 0.0003 + vec2(100.0, 200.0), 2);
    float dust = smoothstep(0.55, 0.65, dust_noise) * 0.015 * intensity;
    color += dust;

    // Clamp to valid range (keep close to base color)
    color = clamp(color, base_color.rgb - vec3(0.03), base_color.rgb + vec3(0.04));

    COLOR = vec4(color, 1.0);
}
