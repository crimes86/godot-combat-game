shader_type canvas_item;

// 1800s cart road shader - dirt road with wheel ruts and worn texture
// Creates a weathered dirt road appearance for paths through the wasteland

uniform vec4 road_color : source_color = vec4(0.08, 0.07, 0.065, 1.0);
uniform vec4 rut_color : source_color = vec4(0.04, 0.035, 0.03, 1.0);
uniform float rut_width : hint_range(0.01, 0.15) = 0.06;
uniform float rut_spacing : hint_range(0.2, 0.6) = 0.38;
uniform float rut_intensity : hint_range(0.0, 1.0) = 0.7;
uniform float noise_scale : hint_range(1.0, 50.0) = 15.0;
uniform float wear_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float edge_roughness : hint_range(0.0, 0.3) = 0.12;

// Hash for noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Value noise
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

// Fractal noise
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 uv = UV;

    // Road runs along X axis (U direction), width is Y (V direction)
    // V = 0.0 is one edge, V = 1.0 is the other edge, V = 0.5 is center
    float center_dist = abs(uv.y - 0.5) * 2.0;  // 0 at center, 1 at edges

    // Base road color with subtle variation
    vec3 base = road_color.rgb;
    float road_noise = fbm(uv * noise_scale, 3);
    base += (road_noise - 0.5) * 0.03 * wear_intensity;

    // Wheel ruts - two parallel tracks
    float rut_pos_left = 0.5 - rut_spacing / 2.0;
    float rut_pos_right = 0.5 + rut_spacing / 2.0;

    // Add waviness to rut positions (wheels wobble)
    float wobble = sin(uv.x * 8.0) * 0.015 + sin(uv.x * 23.0) * 0.008;
    float rut_left = smoothstep(rut_width, 0.0, abs(uv.y - rut_pos_left + wobble));
    float rut_right = smoothstep(rut_width, 0.0, abs(uv.y - rut_pos_right - wobble));

    // Combine ruts with noise for worn appearance
    float rut_noise = noise(uv * vec2(40.0, 10.0));
    float rut_mask = max(rut_left, rut_right) * (0.7 + rut_noise * 0.3);

    // Darken ruts
    base = mix(base, rut_color.rgb, rut_mask * rut_intensity);

    // Center worn area (between ruts) - slightly lighter/compacted
    float center_strip = smoothstep(rut_spacing / 2.0 + 0.05, 0.0, abs(uv.y - 0.5));
    float center_wear = center_strip * (0.6 + noise(uv * 20.0) * 0.4);
    base += center_wear * 0.015 * wear_intensity;  // Slightly lighter from wear

    // Edge areas - darker, more debris
    float edge_fade = smoothstep(0.35, 0.5, center_dist);
    float edge_noise = fbm(uv * vec2(25.0, 8.0), 2);
    base -= edge_fade * edge_noise * 0.04 * wear_intensity;

    // Pebbles/stones scattered on road
    float pebble_noise = noise(uv * 80.0);
    float pebbles = smoothstep(0.75, 0.85, pebble_noise);
    base -= pebbles * 0.05;

    // Occasional lighter stones
    float light_stones = smoothstep(0.82, 0.88, noise(uv * 60.0 + vec2(50.0)));
    base += light_stones * 0.04;

    // Dust patches (lighter areas)
    float dust = fbm(uv * vec2(8.0, 3.0) + vec2(100.0), 2);
    dust = smoothstep(0.55, 0.7, dust);
    base += dust * 0.02;

    // Edge roughness - organic irregular edges
    float edge_alpha = 1.0;
    if (edge_roughness > 0.0) {
        float edge_noise_val = fbm(uv * vec2(20.0, 5.0), 3);
        float rough_edge = center_dist + (edge_noise_val - 0.5) * edge_roughness;
        edge_alpha = 1.0 - smoothstep(0.85, 1.0, rough_edge);
    }

    // Final color
    COLOR = vec4(base, road_color.a * edge_alpha);
}
