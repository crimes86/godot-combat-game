shader_type canvas_item;

// Forest ground shader - Dense forest floor with fallen leaves, moss, dark earth
// Missouri River basin aesthetic - darker, more organic than open grassland
// Uses world coordinates for proper scaling on Polygon2D

// Base forest floor colors
uniform vec4 earth_base : source_color = vec4(0.12, 0.10, 0.06, 1.0);      // Dark forest floor
uniform vec4 earth_dark : source_color = vec4(0.08, 0.06, 0.04, 1.0);      // Deep shadows
uniform vec4 moss_color : source_color = vec4(0.08, 0.14, 0.06, 1.0);      // Moss patches
uniform vec4 leaf_litter : source_color = vec4(0.18, 0.12, 0.06, 1.0);     // Fallen leaves (browns/oranges)
uniform vec4 pine_needle : source_color = vec4(0.10, 0.08, 0.04, 1.0);     // Pine needle carpet

uniform float patch_scale : hint_range(0.1, 5.0) = 1.0;
uniform float detail_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float moss_amount : hint_range(0.0, 0.5) = 0.2;
uniform float leaf_amount : hint_range(0.0, 0.5) = 0.25;

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
    vec3 color = earth_base.rgb;

    // Large-scale terrain variation
    float large_variation = fbm(world_pos * 0.0004 * patch_scale, 3);
    color += (large_variation - 0.5) * vec3(0.02, 0.015, 0.01) * detail_intensity;

    // Moss patches (damp areas)
    float moss_noise = fbm(world_pos * 0.0012 * patch_scale + vec2(100.0, 50.0), 3);
    float moss_mask = smoothstep(0.5, 0.7, moss_noise) * moss_amount;
    color = mix(color, moss_color.rgb, moss_mask);

    // Fallen leaf patches
    float leaf_noise = fbm(world_pos * 0.002 * patch_scale + vec2(300.0, 200.0), 2);
    float leaf_mask = smoothstep(0.45, 0.65, leaf_noise) * leaf_amount;
    color = mix(color, leaf_litter.rgb, leaf_mask);

    // Pine needle carpet areas
    float pine_noise = fbm(world_pos * 0.0015 * patch_scale + vec2(500.0, 100.0), 2);
    float pine_mask = smoothstep(0.55, 0.75, pine_noise) * 0.3;
    color = mix(color, pine_needle.rgb, pine_mask);

    // Deep shadow dappling (canopy shadows)
    float shadow_noise = fbm(world_pos * 0.0006 + vec2(1000.0, 500.0), 3);
    float shadow = smoothstep(0.4, 0.7, shadow_noise) * 0.08 * detail_intensity;
    color -= shadow;

    // Fine texture detail
    float fine_detail = noise(world_pos * 0.008) * 0.02 * detail_intensity;
    color += (fine_detail - 0.01);

    // Occasional dark patches (rotting material, deep shade)
    float dark_patch = fbm(world_pos * 0.001 + vec2(700.0, 300.0), 2);
    float dark_mask = smoothstep(0.65, 0.85, dark_patch) * 0.15;
    color = mix(color, earth_dark.rgb, dark_mask);

    color = clamp(color, vec3(0.02), vec3(0.3));

    COLOR = vec4(color, 1.0);
}
