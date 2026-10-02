shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 source_rect = vec4(0.38, 0.0, 0.69, 0.42);
uniform float time = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.7;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec2 uv = UV;
	float coarse = noise21(uv * vec2(11.0, 32.0) + vec2(time * 0.0042, -time * 0.0031));
	float fibers = noise21(uv * vec2(73.0, 145.0));
	float broken = smoothstep(0.27, 0.82, coarse * 0.72 + fibers * 0.28);
	float ripple = sin(uv.x * 92.0 + uv.y * 21.0 + time * 0.11) * 0.0046;
	float source_x = mix(source_rect.x, source_rect.z, clamp(uv.x + ripple, 0.0, 1.0));
	float source_y = mix(source_rect.w, source_rect.y, clamp(uv.y * 0.94, 0.0, 1.0));
	vec2 source_uv = vec2(source_x, source_y);
	vec3 reflected = textureLod(screen_texture, source_uv,
		mix(1.6, 4.2, uv.y) + coarse * 0.7).rgb;
	float luminance = dot(reflected, vec3(0.2126, 0.7152, 0.0722));
	vec3 cool_reflection = pow(max(reflected, vec3(0.0)), vec3(0.74)) *
		vec3(0.48, 0.65, 0.92);
	float edge_fade = smoothstep(0.0, 0.13, uv.x) * smoothstep(0.0, 0.13, 1.0 - uv.x);
	edge_fade *= smoothstep(0.0, 0.11, uv.y) * smoothstep(0.0, 0.18, 1.0 - uv.y);
	float depth_fade = mix(0.85, 0.34, uv.y);

	// Zwei Fensterfelder und Mittelholm bleiben im abstrakten Teppichbounce
	// lesbar; der Hochflor bricht ihre Kanten in unregelmäßige Fragmente.
	float center_mullion = 1.0 - smoothstep(0.018, 0.072, abs(uv.x - 0.5));
	float side_frames = (1.0 - smoothstep(0.012, 0.055, abs(uv.x - 0.08))) +
		(1.0 - smoothstep(0.012, 0.055, abs(uv.x - 0.92)));
	float frame_shadow = clamp(center_mullion * 0.82 + side_frames * 0.42, 0.0, 1.0);
	cool_reflection *= 1.0 - frame_shadow * (0.38 + broken * 0.18);

	// Laufende Regenschlieren spiegeln sich als kurze Caustic-Fragmente.
	vec2 rain_grid = vec2(uv.x * 34.0 + uv.y * 1.7, uv.y * 18.0 - time * 0.13);
	vec2 rain_id = floor(rain_grid);
	vec2 rain_f = fract(rain_grid);
	float rain_random = hash21(rain_id);
	float rain_line = (1.0 - smoothstep(0.018, 0.16, abs(rain_f.x - 0.5 -
		(rain_f.y - 0.5) * 0.18)));
	float rain_tail = smoothstep(0.06, 0.24, rain_f.y) *
		(1.0 - smoothstep(0.54, 0.94, rain_f.y));
	float rain_caustic = rain_line * rain_tail * step(0.46, rain_random) * broken;

	float glint = step(0.925, fibers) * (0.24 + luminance * 0.46) * intensity;
	// Auch bei schwarzem Nachthimmel bleibt das vom nassen Glas gestreute kalte
	// Raumlicht sichtbar. Zuvor hing fast die gesamte Deckkraft von der dunklen
	// Fensterluminanz ab und verschwand auf dem hellen Teppich vollständig.
	float reflection_body = (0.25 + luminance * 0.42) * (0.62 + broken * 0.50);
	float alpha = intensity * edge_fade * depth_fade * reflection_body;
	cool_reflection = max(cool_reflection, vec3(0.10, 0.20, 0.36) * (0.70 + broken * 0.45));
	cool_reflection += vec3(0.07, 0.18, 0.40) * intensity * broken * 0.88;
	cool_reflection += vec3(0.34, 0.67, 1.0) * rain_caustic * intensity * 1.08;
	cool_reflection += vec3(0.62, 0.82, 1.0) * glint;
	alpha += rain_caustic * intensity * 0.22 + glint * 0.30;
	COLOR = (vec4(cool_reflection, clamp(alpha * edge_fade, 0.0, 0.62))) * item_modulate;
}
