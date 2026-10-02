shader_type canvas_item;
render_mode unshaded;

// Sehr leichte Gauß-Weichzeichnung für den freigestellten Händler. Sie nimmt
// nur die digitale Schnittschärfe heraus; Silhouette und Gesicht bleiben klar.
uniform float softness : hint_range(0.0, 4.0) = 1.65;

vec4 premultiplied(vec4 c) {
	c.rgb *= c.a;
	return c;
}

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * softness;
	vec2 uv0 = clamp(UV, vec2(0.001), vec2(0.999));
	vec4 sum = premultiplied(texture(TEXTURE, uv0)) * 0.32;
	sum += premultiplied(texture(TEXTURE, clamp(UV + vec2(px.x, 0.0), vec2(0.001), vec2(0.999)))) * 0.12;
	sum += premultiplied(texture(TEXTURE, clamp(UV - vec2(px.x, 0.0), vec2(0.001), vec2(0.999)))) * 0.12;
	sum += premultiplied(texture(TEXTURE, clamp(UV + vec2(0.0, px.y), vec2(0.001), vec2(0.999)))) * 0.12;
	sum += premultiplied(texture(TEXTURE, clamp(UV - vec2(0.0, px.y), vec2(0.001), vec2(0.999)))) * 0.12;
	sum += premultiplied(texture(TEXTURE, clamp(UV + px, vec2(0.001), vec2(0.999)))) * 0.05;
	sum += premultiplied(texture(TEXTURE, clamp(UV - px, vec2(0.001), vec2(0.999)))) * 0.05;
	sum += premultiplied(texture(TEXTURE, clamp(UV + vec2(px.x, -px.y), vec2(0.001), vec2(0.999)))) * 0.05;
	sum += premultiplied(texture(TEXTURE, clamp(UV + vec2(-px.x, px.y), vec2(0.001), vec2(0.999)))) * 0.05;
	if (sum.a > 0.0001) {
		sum.rgb /= sum.a;
	}
	COLOR = (sum) * item_modulate;
}
