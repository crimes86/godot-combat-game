shader_type canvas_item;

// =============================================================================
// MIDSECTION TINT SHADER - Part of "Skorpio Armor Illusion" hack
// =============================================================================
// Used by: SimpleLPCSprite.gd gun mode (east/west directions only)
// Purpose: Tint the torso area of Skorpio gun-pose body to match armor,
//          and tint the hip/butt area to match pants color.
//          KEEP the feet visible (original skin color).
//
// The Skorpio sprite pack doesn't have armor variants, so we fake it by
// color-tinting just the midsection to match the player's equipped chest armor.
// =============================================================================

uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 pants_tint_color : source_color = vec4(0.3, 0.5, 0.3, 1.0);  // Default green-ish

// Y thresholds tuned for 64x64 LPC/Skorpio sprites
// top_threshold: where torso tinting starts (below head) ~0.53
// bottom_threshold: where torso tinting ends ~0.72
// pants_start: where pants tinting starts ~0.72
// pants_end: where pants tinting ends (above feet) ~0.88
uniform float top_threshold : hint_range(0.0, 1.0) = 0.53;
uniform float bottom_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float pants_start : hint_range(0.0, 1.0) = 0.72;
uniform float pants_end : hint_range(0.0, 1.0) = 0.88;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);

	// Tint hip/butt area to match pants color (between pants_start and pants_end)
	if (UV.y > pants_start && UV.y < pants_end) {
		COLOR = tex_color * pants_tint_color;
	}
	// Tint the middle section (torso/arms area) to match armor
	else if (UV.y > top_threshold && UV.y < bottom_threshold) {
		COLOR = tex_color * tint_color;
	}
	// Keep original color for head AND feet
	else {
		COLOR = tex_color;
	}
}
