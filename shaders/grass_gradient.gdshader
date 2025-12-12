shader_type canvas_item;

// Grass gradient shader - darkens near cave entrance, brighter in open field
// Gradient from Y=-5500 (dark) to Y=-6500 (25% lighter)

uniform vec4 base_color : source_color = vec4(0.009, 0.032, 0.004, 1.0);  // Darkened 50% total
uniform float brightness_boost : hint_range(1.0, 2.0) = 1.25;
uniform float gradient_start_y : hint_range(-10000.0, 0.0) = -5500.0;
uniform float gradient_end_y : hint_range(-15000.0, -5000.0) = -6500.0;

varying vec2 world_pos;

void vertex() {
    // Transform vertex to world space for smooth interpolation
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // Calculate gradient factor based on world Y position
    // 0.0 = at or below gradient_start_y (near cave, dark)
    // 1.0 = at or above gradient_end_y (open field, bright)
    float t = clamp((world_pos.y - gradient_start_y) / (gradient_end_y - gradient_start_y), 0.0, 1.0);

    // Smooth the transition with smoothstep for less banding
    t = smoothstep(0.0, 1.0, t);

    // Interpolate brightness
    float brightness = mix(1.0, brightness_boost, t);

    // Apply brightness to base color
    vec3 final_color = base_color.rgb * brightness;

    COLOR = vec4(final_color, base_color.a);
}
