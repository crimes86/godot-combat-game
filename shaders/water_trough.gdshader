shader_type canvas_item;

uniform float wave_speed : hint_range(0.5, 3.0) = 0.8;
uniform float wave_amount : hint_range(0.0, 0.02) = 0.003;
uniform float ripple_speed : hint_range(0.5, 4.0) = 1.2;

void fragment() {
	vec2 uv = UV;

	// Water area mask - top portion of trough (cyan water area)
	// Shifted down ~5px in UV space
	float water_mask = smoothstep(0.75, 0.70, UV.y) * smoothstep(0.11, 0.17, UV.y);
	water_mask *= smoothstep(0.12, 0.20, UV.x) * smoothstep(0.88, 0.80, UV.x);

	// Gentle horizontal wave distortion
	float wave = sin(UV.y * 25.0 + TIME * wave_speed) * wave_amount;
	wave += sin(UV.y * 18.0 - TIME * wave_speed * 1.3) * wave_amount * 0.6;
	uv.x += wave * water_mask;

	// Sample the texture
	vec4 color = texture(TEXTURE, uv);

	// Subtle caustic/ripple lighting effect
	float ripple1 = sin((UV.x + UV.y) * 40.0 + TIME * ripple_speed);
	float ripple2 = sin((UV.x - UV.y) * 35.0 - TIME * ripple_speed * 0.7);
	float caustic = (ripple1 * ripple2 + 1.0) * 0.5;
	caustic = smoothstep(0.4, 0.9, caustic) * 0.08 * water_mask;

	// Apply subtle brightness variation
	color.rgb += caustic;

	// Slight darkening at edges for depth
	float edge_darken = water_mask * 0.03 * (1.0 - smoothstep(0.2, 0.5, UV.y));
	color.rgb -= edge_darken;

	COLOR = color;
}
