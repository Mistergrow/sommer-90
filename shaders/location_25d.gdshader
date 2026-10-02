shader_type canvas_item;
render_mode unshaded;

// Subtiler, vertikal gewichteter Tiefenversatz für gemalte/fotografische
// Standort-Master. Der Overscan hält alle Samples innerhalb des Bildes.
uniform vec2 look = vec2(0.0);
uniform float horizon : hint_range(0.0, 0.9) = 0.44;
uniform float strength : hint_range(0.0, 0.03) = 0.009;
uniform float far_gain : hint_range(0.0, 1.0) = 0.18;
uniform float near_gain : hint_range(0.0, 2.0) = 1.0;
uniform float vertical_gain : hint_range(0.0, 1.0) = 0.45;
uniform float overscan : hint_range(0.0, 0.08) = 0.028;
uniform sampler2D semantic_depth : filter_linear, repeat_disable;
uniform bool use_semantic_depth = false;

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * (1.0 - overscan * 2.0) + vec2(0.5);
	// Sobald der SurfaceEditor mindestens eine gültige Fläche für den Ort
	// gespeichert hat, ersetzt die semantische Map dort den pauschalen
	// Y-Verlauf. Unmarkierte Pixel in der Map enthalten weiterhin den Fallback.
	float depth = use_semantic_depth
		? texture(semantic_depth, uv).r
		: smoothstep(horizon, 1.0, uv.y);
	float gain = mix(far_gain, near_gain, depth);
	vec2 shift = look * strength * gain;
	shift.y *= vertical_gain;
	// Negatives Sampling verschiebt das sichtbare Motiv in Blickrichtung.
	uv -= shift;
	uv = clamp(uv, vec2(0.001), vec2(0.999));
	// Apply the vertex modulation once, independent of the shifted texture sample.
	COLOR = texture(TEXTURE, uv) * item_modulate;
}
