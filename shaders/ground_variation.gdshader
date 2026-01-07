shader_type canvas_item;

// Ground variation shader with rolling hills effect
// Creates illusion of undulating terrain through shading

// Dark stone grey - cool tint to counteract any warm bleed
uniform vec4 base_color : source_color = vec4(0.15, 0.15, 0.17, 1.0);
uniform float world_scale : hint_range(0.0001, 0.01) = 0.001;
uniform float intensity : hint_range(0.0, 1.0) = 0.75;  // Fine texture strength
uniform float hill_intensity : hint_range(0.0, 1.0) = 0.6;  // Rolling hills strength
uniform float hill_scale : hint_range(0.00001, 0.001) = 0.00008;  // Size of hills

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

    // === ROLLING HILLS LAYER: Smooth organic elevation shading ===
    // Use multiple overlapping noise layers for organic feel (no grid)
    float elevation1 = fbm(world_pos * hill_scale, 6);  // Main hills
    float elevation2 = fbm(world_pos * hill_scale * 1.7 + vec2(1000.0, 500.0), 5);  // Medium detail
    float elevation3 = fbm(world_pos * hill_scale * 3.1 + vec2(2000.0, 1500.0), 4);  // Fine detail

    // Blend layers for smooth organic result
    float elevation = elevation1 * 0.5 + elevation2 * 0.3 + elevation3 * 0.2;
    float hill_height = (elevation - 0.5) * 2.0;

    // Hilltops are lighter, valleys are darker
    float hill_shade = hill_height * 0.14 * hill_intensity;
    color += vec3(hill_shade);

    // Add directional shadow for depth (light from top-left)
    vec2 offset_pos = world_pos + vec2(500.0, 300.0);
    float slope1 = fbm(offset_pos * hill_scale * 0.8, 5);
    float slope2 = fbm(offset_pos * hill_scale * 2.3 + vec2(800.0, 400.0), 4);
    float slope = (slope1 * 0.6 + slope2 * 0.4 - 0.5);
    float ridge_shadow = slope * 0.08 * hill_intensity;
    color += vec3(ridge_shadow);

    // Subtle warm tint on hilltops, cool tint in valleys
    color.r += hill_height * 0.025 * hill_intensity;
    color.b -= hill_height * 0.015 * hill_intensity;

    // === LAYER 1: Very subtle large-scale variation (barely visible) ===
    float large_variation = fbm(world_pos * 0.00015, 3);
    // Neutral grey variation - no warm tint
    color += (large_variation - 0.5) * vec3(0.006, 0.006, 0.006) * intensity;

    // === LAYER 2: Fine grain texture (small speckles) ===
    float fine_grain = noise(world_pos * 0.008);
    color += (fine_grain - 0.5) * 0.025 * intensity;

    // === LAYER 3: Medium noise for slight color shifts ===
    float medium_noise = fbm(world_pos * 0.0004, 2);
    // Neutral grey shifts - no warm tint
    color += (medium_noise - 0.5) * vec3(0.008, 0.008, 0.008) * intensity;

    // === LAYER 4: Tiny scattered darker specks (boosted) ===
    float speck_noise = noise(world_pos * 0.015);
    float specks = smoothstep(0.6, 0.75, speck_noise) * 0.035 * intensity;
    color -= specks;

    // === LAYER 5: Very faint lighter dust patches (reduced) ===
    float dust_noise = fbm(world_pos * 0.0003 + vec2(100.0, 200.0), 2);
    float dust = smoothstep(0.6, 0.7, dust_noise) * 0.008 * intensity;
    color += dust;

    // Clamp to valid range (expanded for visible hill variation)
    color = clamp(color, base_color.rgb - vec3(0.15), base_color.rgb + vec3(0.15));

    COLOR = vec4(color, 1.0);
}
