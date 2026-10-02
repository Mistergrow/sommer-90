shader_type canvas_item;
render_mode unshaded;

// Room-spezifische Depthmap-Reprojektion. Der Node selbst ist bereits um
// node_gain verschoben; der Shader addiert nur den relativen Rest. So gibt es
// keinen Double-Shift, waehrend Tischplatte/Props exakt starr bleiben.
uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform vec2 look = vec2(0.0);
uniform float strength : hint_range(0.0, 0.02) = 0.0072;
uniform float far_gain : hint_range(0.0, 1.0) = 0.08;
uniform float near_gain : hint_range(0.0, 1.5) = 0.95;
uniform float node_gain : hint_range(0.0, 1.5) = 0.08;
uniform float vertical_gain : hint_range(0.0, 1.0) = 0.48;
uniform float overscan : hint_range(0.0, 0.03) = 0.004;
uniform float relief_strength : hint_range(0.0, 0.2) = 0.055;

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * (1.0 - overscan * 2.0) + vec2(0.5);
	float depth = texture(depth_tex, clamp(uv, vec2(0.0), vec2(1.0))).r;
	float gain = mix(far_gain, near_gain, depth);
	vec2 shift = look * strength * (gain - node_gain);
	shift.y *= vertical_gain;
	uv = clamp(uv - shift, vec2(0.001), vec2(0.999));

	vec4 col = texture(TEXTURE, uv);
	// Sehr dezente blickabhaengige Reliefreaktion an Tiefenkanten. Keine
	// aufgemalte Lampe: nur ein weiches Helligkeitssignal bei echter Bewegung.
	ivec2 depth_size = textureSize(depth_tex, 0);
	vec2 texel = 1.0 / max(vec2(depth_size), vec2(1.0));
	float dx = texture(depth_tex, clamp(uv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r
		- texture(depth_tex, clamp(uv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r;
	float dy = texture(depth_tex, clamp(uv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r
		- texture(depth_tex, clamp(uv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r;
	float look_len = min(length(look), 1.0);
	vec2 view_dir = look / max(look_len, 0.0001);
	float relief = clamp(dot(vec2(dx, dy), view_dir) * look_len * relief_strength,
		-0.035, 0.035);
	col.rgb *= 1.0 + relief;
	COLOR = (col) * item_modulate;
}
