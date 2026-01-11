shader_type canvas_item;

// Enhanced ground shader - cracked scorched earth with color variation
// Creates visually interesting terrain for Dreadland

uniform vec4 base_color : source_color = vec4(0.15, 0.15, 0.17, 1.0);
uniform float world_scale : hint_range(0.0001, 0.01) = 0.001;
uniform float intensity : hint_range(0.0, 1.0) = 0.7;
uniform float hill_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float hill_scale : hint_range(0.00001, 0.001) = 0.00006;
uniform float crack_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float stone_intensity : hint_range(0.0, 1.0) = 0.3;

// Hash functions for noise
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float hash1(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Gradient noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
    float b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

    return 0.5 + 0.5 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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

// Voronoi for cracks - returns distance to edge (for cracks) and cell id
vec3 voronoi_cracks(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    float min_dist = 1.0;
    float second_dist = 1.0;
    vec2 min_id = vec2(0.0);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = hash2(i + neighbor) * 0.5 + 0.5;
            vec2 diff = neighbor + point - f;
            float dist = length(diff);

            if (dist < min_dist) {
                second_dist = min_dist;
                min_dist = dist;
                min_id = i + neighbor;
            } else if (dist < second_dist) {
                second_dist = dist;
            }
        }
    }

    return vec3(min_dist, second_dist - min_dist, hash1(min_id));
}

// Domain warp for organic distortion
vec2 warp_domain(vec2 p, float amount) {
    float n1 = noise(p * 1.5);
    float n2 = noise(p * 1.5 + vec2(50.0, 80.0));
    return p + vec2(n1 - 0.5, n2 - 0.5) * amount;
}

// Multi-layer crack pattern for realistic dried earth
// Returns vec2: x = crack darkness, y = raised edge amount
vec2 cracked_earth_detailed(vec2 p) {
    float cracks = 0.0;
    float raised_edges = 0.0;

    // Layer 1: Large primary cracks (dominant pattern)
    vec2 p1 = warp_domain(p * 0.8, 0.4);
    vec3 v1 = voronoi_cracks(p1);
    float crack1 = 1.0 - smoothstep(0.0, 0.02, v1.y);
    float edge1 = smoothstep(0.02, 0.06, v1.y) * (1.0 - smoothstep(0.06, 0.12, v1.y));
    cracks += crack1 * 0.8;
    raised_edges += edge1 * 0.6;

    // Layer 2: Medium secondary cracks (fills in gaps)
    vec2 p2 = warp_domain(p * 2.0 + vec2(100.0, 50.0), 0.3);
    vec3 v2 = voronoi_cracks(p2);
    float crack2 = 1.0 - smoothstep(0.0, 0.018, v2.y);
    float edge2 = smoothstep(0.018, 0.05, v2.y) * (1.0 - smoothstep(0.05, 0.09, v2.y));
    cracks += crack2 * 0.5;
    raised_edges += edge2 * 0.4;

    // Layer 3: Fine hairline cracks - much softer, subtle
    vec2 p3 = warp_domain(p * 3.5 + vec2(200.0, 150.0), 0.2);
    vec3 v3 = voronoi_cracks(p3);
    float crack3 = 1.0 - smoothstep(0.0, 0.02, v3.y);
    cracks += crack3 * 0.15;

    return vec2(clamp(cracks, 0.0, 1.0), clamp(raised_edges, 0.0, 1.0));
}

// Surface texture within cells (dried mud texture) - softened
float dried_surface(vec2 p) {
    float texture = 0.0;

    // Gentle surface variation (reduced intensity)
    texture += (noise(p * 6.0) - 0.5) * 0.25;
    texture += (noise(p * 10.0 + vec2(30.0)) - 0.5) * 0.15;

    // Very subtle pitting
    float pits = noise(p * 8.0 + vec2(50.0, 70.0));
    texture -= smoothstep(0.7, 0.85, pits) * 0.15;

    return texture;
}

// Get cell variation for subtle color differences
float cell_variation(vec2 p) {
    vec2 warped = warp_domain(p * 0.8, 0.4);
    vec3 v = voronoi_cracks(warped);
    return v.z;
}

// Stone/pebble pattern
float stonePattern(vec2 p) {
    vec3 v = voronoi_cracks(p);
    float edge = smoothstep(0.0, 0.08, v.y);
    return edge;
}

void fragment() {
    vec2 world_pos = UV / world_scale;

    // Start with base color
    vec3 color = base_color.rgb;

    // === COLOR TEMPERATURE REGIONS ===
    float temp_noise = fbm(world_pos * 0.00008, 3);
    float warm_zone = smoothstep(0.4, 0.6, temp_noise);

    // Warm areas (browns/tans) vs cool areas (grey/blue-grey)
    vec3 warm_tint = vec3(0.04, 0.02, -0.01);
    vec3 cool_tint = vec3(-0.02, -0.01, 0.02);
    color += mix(cool_tint, warm_tint, warm_zone) * intensity;

    // === ROLLING HILLS (enhanced contrast) ===
    float elevation = fbm(world_pos * hill_scale, 5);
    float hill_height = (elevation - 0.5) * 4.0;

    float hill_shade = hill_height * 0.08 * hill_intensity;
    color += vec3(hill_shade);

    vec2 offset_pos = world_pos + vec2(800.0, 500.0);
    float slope = fbm(offset_pos * hill_scale * 0.9, 3);
    float ridge_shadow = (slope - 0.5) * 0.06 * hill_intensity;
    color += vec3(ridge_shadow);

    color.r += hill_height * 0.025 * hill_intensity;
    color.b -= hill_height * 0.015 * hill_intensity;

    // === CRACKED EARTH (multi-layer realistic cracks) ===
    vec2 crack_base = world_pos * 0.002;
    vec2 crack_data = cracked_earth_detailed(crack_base);
    float cracks = crack_data.x;
    float raised = crack_data.y;

    // Dark cracks (depth)
    color -= cracks * 0.18 * crack_intensity;

    // Raised edges (dried mud curling up catches light)
    color += raised * 0.06 * crack_intensity;

    // Cell color variation (each dried mud piece slightly different)
    float cell_var = cell_variation(crack_base);
    color += (cell_var - 0.5) * 0.04 * crack_intensity;

    // Surface texture within cells (subtle micro-roughness)
    float surface = dried_surface(crack_base);
    color += surface * 0.018 * crack_intensity;

    // Debris/pebbles near crack edges
    float debris_noise = noise(world_pos * 0.015);
    float near_crack = smoothstep(0.0, 0.3, cracks) * (1.0 - smoothstep(0.3, 0.6, cracks));
    float debris = smoothstep(0.6, 0.8, debris_noise) * near_crack;
    color -= debris * 0.04 * crack_intensity;

    // === STONE/PEBBLE TEXTURE ===
    float stone = stonePattern(world_pos * 0.008);
    color += (stone - 0.5) * 0.05 * stone_intensity;

    float big_stones = stonePattern(world_pos * 0.002);
    float stone_mask = smoothstep(0.3, 0.5, fbm(world_pos * 0.0003, 2));
    color += (big_stones - 0.5) * 0.04 * stone_intensity * stone_mask;

    // === DUST AND ASH PATCHES ===
    float dust_noise = fbm(world_pos * 0.0004 + vec2(100.0, 200.0), 3);
    float dust = smoothstep(0.45, 0.60, dust_noise);
    color += dust * vec3(0.03, 0.025, 0.02) * intensity;

    // === SCORCHED/DARK PATCHES ===
    float scorch_noise = fbm(world_pos * 0.0003 + vec2(500.0, 300.0), 2);
    float scorch = smoothstep(0.55, 0.70, scorch_noise);
    color -= scorch * vec3(0.03, 0.025, 0.03) * intensity;

    // === FINE GRAIN TEXTURE ===
    float fine_grain = noise(world_pos * 0.006);
    color += (fine_grain - 0.5) * 0.05 * intensity;

    // === SPECKS (dirt/pebbles) ===
    float speck_noise = noise(world_pos * 0.012);
    float specks = smoothstep(0.75, 0.90, speck_noise) * 0.03 * intensity;
    color -= specks;

    float light_specks = smoothstep(0.78, 0.92, noise(world_pos * 0.015 + vec2(50.0)));
    color += light_specks * 0.04 * intensity;

    // === SCATTERED SMALL ROCKS ===
    // Random dark spots across the surface like small rocks/pebbles
    float rock_noise = noise(world_pos * 0.025 + vec2(300.0, 400.0));
    float rocks = smoothstep(0.82, 0.88, rock_noise);
    color -= rocks * 0.08 * intensity;

    // Slightly larger scattered rocks (sparser)
    float big_rock_noise = noise(world_pos * 0.01 + vec2(600.0, 200.0));
    float big_rocks = smoothstep(0.88, 0.93, big_rock_noise);
    color -= big_rocks * 0.1 * intensity;

    // Clamp to valid range (wider range for more contrast)
    color = clamp(color, base_color.rgb - vec3(0.22), base_color.rgb + vec3(0.22));

    COLOR = vec4(color, 1.0);
}
