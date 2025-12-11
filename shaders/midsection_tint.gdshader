shader_type canvas_item;

// =============================================================================
// MIDSECTION TINT SHADER - Part of "Skorpio Armor Illusion" hack
// =============================================================================
// Used by: SimpleLPCSprite.gd gun mode (east/west directions only)
// Purpose: Tint only the torso area of Skorpio gun-pose body to match armor
//          while keeping head and feet their original skin color.
//
// The Skorpio sprite pack doesn't have armor variants, so we fake it by
// color-tinting just the midsection to match the player's equipped chest armor.
// =============================================================================

uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Y thresholds tuned for 64x64 LPC/Skorpio sprites
// During walk animation, the body bobs up/down within the frame (~2-3px).
// We need a band that covers the torso across all frames while excluding:
//   - Head/face (top ~53% of frame = ~34px)
//   - Feet (bottom ~28% of frame = ~18px)
// top_threshold=0.53 starts below the chin/neck area
// bottom_threshold=0.72 ends above the ankles
// This leaves a ~12px torso band that covers walk bobbing
uniform float top_threshold : hint_range(0.0, 1.0) = 0.53;
uniform float bottom_threshold : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);

	// Only tint the middle section (torso/arms area)
	if (UV.y > top_threshold && UV.y < bottom_threshold) {
		// Apply tint to midsection
		COLOR = tex_color * tint_color;
	} else {
		// Keep original color for head and feet
		COLOR = tex_color;
	}
}
