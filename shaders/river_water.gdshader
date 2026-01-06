shader_type canvas_item;

// River water shader - Flowing river with current, ripples, and depth
// Missouri River aesthetic - muddy browns with blue-green hints
// Procedural, no texture needed

// Water colors
uniform vec4 water_shallow : source_color = vec4(0.15, 0.20, 0.18, 1.0);    // Shallow edge
uniform vec4 water_deep : source_color = vec4(0.08, 0.12, 0.14, 1.0);       // Deep center
uniform vec4 water_murky : source_color = vec4(0.12, 0.10, 0.08, 1.0);      // Muddy undertone
uniform vec4 foam_color : source_color = vec4(0.35, 0.38, 0.35, 1.0);       // Foam/rapids

uniform float flow_speed : hint_range(0.1, 2.0) = 0.5;                       // Current speed
uniform float wave_intensity : hint_range(0.0, 1.0) = 0.6;                   // Wave visibility
uniform float foam_amount : hint_range(0.0, 0.3) = 0.1;                      // Foam on surface
uniform float depth_variation : hint_range(0.0, 1.0) = 0.7;                  // Shallow/deep variation

varying vec2 world_pos;

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
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // Flowing offset - river flows east (positive X)
    vec2 flow_offset = vec2(TIME * flow_speed * 100.0, 0.0);

    // Base water color - blend shallow to deep based on Y position within river
    // Assume river runs roughly horizontal, deeper in center
    float depth_noise = fbm(world_pos * 0.0003, 2);
    float depth = depth_noise * depth_variation;
    vec3 color = mix(water_shallow.rgb, water_deep.rgb, depth);

    // Add muddy undertone
    float murk_noise = fbm(world_pos * 0.0005 + vec2(200.0, 100.0), 2);
    color = mix(color, water_murky.rgb, murk_noise * 0.3);

    // Flowing wave patterns
    vec2 wave_pos = world_pos + flow_offset;
    float wave1 = sin(wave_pos.x * 0.008 + wave_pos.y * 0.003) * 0.5 + 0.5;
    float wave2 = sin(wave_pos.x * 0.012 - wave_pos.y * 0.005 + 1.5) * 0.5 + 0.5;
    float waves = (wave1 * wave2) * wave_intensity * 0.06;
    color += waves;

    // Surface ripples
    float ripple_pos_x = world_pos.x + TIME * flow_speed * 80.0;
    float ripple1 = noise(vec2(ripple_pos_x * 0.02, world_pos.y * 0.02));
    float ripple2 = noise(vec2(ripple_pos_x * 0.03 + 100.0, world_pos.y * 0.025 + 50.0));
    float ripples = (ripple1 + ripple2) * 0.5 * wave_intensity * 0.04;
    color += ripples - 0.02;

    // Foam/froth patches
    float foam_noise = fbm(vec2(world_pos.x + TIME * flow_speed * 60.0, world_pos.y) * 0.003, 3);
    float foam_mask = smoothstep(0.6, 0.8, foam_noise) * foam_amount;
    color = mix(color, foam_color.rgb, foam_mask);

    // Caustic light dancing
    float caustic1 = sin((wave_pos.x + wave_pos.y) * 0.015 + TIME * 1.5);
    float caustic2 = sin((wave_pos.x - wave_pos.y) * 0.012 - TIME * 1.2);
    float caustics = (caustic1 * caustic2 + 1.0) * 0.5;
    caustics = smoothstep(0.5, 0.9, caustics) * 0.03;
    color += caustics;

    // Darken near edges (shoreline depth)
    // This creates gradient from shore to center
    float edge_dark = smoothstep(0.0, 0.3, depth) * 0.05;
    color -= edge_dark * (1.0 - depth);

    color = clamp(color, vec3(0.03), vec3(0.45));

    COLOR = vec4(color, 0.95);  // Slight transparency
}
