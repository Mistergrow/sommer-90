shader_type canvas_item;
render_mode unshaded;

// Ausschliesslicher Ausgabepass der Amiga-Pipeline. Das logische Spielbild
// bleibt unangetastet und pixelgenau; dieses Material liegt erst auf dem
// ganzzahlig skalierten TextureRect des emulierten Monitors.
uniform float scanline_strength : hint_range(0.0, 0.45) = 0.10;
uniform float shadow_mask_strength : hint_range(0.0, 0.25) = 0.035;
uniform float glow_strength : hint_range(0.0, 0.18) = 0.025;
uniform float curvature : hint_range(0.0, 0.08) = 0.0;
uniform vec2 logical_size = vec2(320.0, 200.0);


varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	vec2 warped = centered * (1.0 + dot(centered, centered) * curvature);
	vec2 uv = warped * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = (vec4(0.0, 0.0, 0.0, 1.0)) * item_modulate;
	} else {
		vec4 source = texture(TEXTURE, uv);
		float row = floor(uv.y * logical_size.y);
		float scan = 1.0 - scanline_strength * step(0.5, mod(row, 2.0));
		float column = floor(uv.x * logical_size.x);
		float mask_phase = mod(column, 3.0);
		vec3 mask = vec3(1.0);
		mask.r -= shadow_mask_strength * step(0.5, abs(mask_phase - 0.0));
		mask.g -= shadow_mask_strength * step(0.5, abs(mask_phase - 1.0));
		mask.b -= shadow_mask_strength * step(0.5, abs(mask_phase - 2.0));
		vec3 glow = source.rgb * source.rgb * glow_strength;
		COLOR = (vec4(source.rgb * scan * mask + glow, source.a)) * item_modulate;
	}
}
