// CRT-Shader (AAA): Bildschirmkrümmung mit abgerundeter Röhre, helligkeits-
// erhaltende Beam-Scanlines, RGB-Lochmaske, Farbsäume, Signal-Zittern,
// Phosphor-Nachglühen, der langsam rollende Bildröhren-„Faden", Glas-Reflexion
// und Vignette. Liegt als Fullscreen-ColorRect auf einem eigenen CanvasLayer:
// optional als experimenteller Gesamtspiel-Look oder automatisch am Computer.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float curvature : hint_range(0.0, 0.3) = 0.045;
uniform float pincushion : hint_range(-0.12, 0.12) = 0.018; // analoge Kissen-Geometrie
uniform float overscan : hint_range(0.0, 0.12) = 0.008;     // Bild ueber Glasrand hinaus
uniform float rotation : hint_range(-0.025, 0.025) = 0.0;   // verdrehte Ablenkspulen
uniform float vertical_hold : hint_range(-0.04, 0.04) = 0.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.13;
uniform float interlace_strength : hint_range(0.0, 0.5) = 0.025;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.20;
uniform float rgb_mask_strength : hint_range(0.0, 1.0) = 0.045;
uniform float mask_pitch : hint_range(120.0, 720.0) = 360.0;
uniform float flicker_strength : hint_range(0.0, 0.2) = 0.014;
uniform float aberration : hint_range(0.0, 0.004) = 0.00055; // horizontale Konvergenz
uniform float vertical_aberration : hint_range(0.0, 0.004) = 0.00018;
uniform float color_bleed : hint_range(0.0, 0.01) = 0.00035;
uniform float jitter : hint_range(0.0, 0.004) = 0.00032;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.009;
uniform float hum_bar_strength : hint_range(0.0, 0.3) = 0.018;
uniform float hum_bar_speed : hint_range(0.0, 2.0) = 0.18;
uniform float roll_speed : hint_range(0.0, 1.0) = 0.13;     // Tempo des Fadens
uniform float roll_width : hint_range(0.01, 0.5) = 0.18;    // Breite des Fadens
uniform float roll_strength : hint_range(0.0, 0.6) = 0.075; // Helligkeit des Fadens
uniform float bloom : hint_range(0.0, 0.6) = 0.075;         // Phosphor-Nachglühen
uniform float ghosting : hint_range(0.0, 0.4) = 0.035;      // horizontales Nachbild
uniform float sharpness : hint_range(0.0, 1.0) = 0.10;      // Beam-Fokus
uniform float saturation : hint_range(0.0, 1.5) = 0.98;
uniform float gamma : hint_range(0.6, 1.6) = 1.0;
uniform float black_level : hint_range(0.0, 0.2) = 0.006;
uniform float white_level : hint_range(0.8, 1.4) = 1.03;
uniform float text_boost : hint_range(0.0, 0.6) = 0.12;     // Kontrast-/Lesbarkeits-Anhebung
uniform float corner_radius : hint_range(0.0, 0.15) = 0.032;
uniform float edge_softness : hint_range(0.001, 0.05) = 0.010;
uniform float reflection : hint_range(0.0, 0.2) = 0.035;    // Glas-Reflexion

uniform bool reduced_motion = false;
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	float signal_time = reduced_motion ? 0.0 : TIME;
	float motion_gain = reduced_motion ? 0.0 : 1.0;
	// UV um die Bildmitte krümmen (Tonnen-Verzerrung wie bei einer Bildröhre)
	vec2 cuv = SCREEN_UV * 2.0 - 1.0;
	float rc = cos(rotation);
	float rs = sin(rotation);
	cuv = mat2(vec2(rc, -rs), vec2(rs, rc)) * cuv;
	cuv *= 1.0 + overscan;
	cuv.y += vertical_hold * 2.0;
	vec2 offset = cuv.yx * cuv.yx * curvature;
	cuv = cuv + cuv * offset;
	// Kleine, getrennt regelbare Kissenkorrektur einer nicht ideal justierten
	// Ablenkung. Sie ist asymmetrischer als die reine Tonnenkrümmung.
	cuv.x += cuv.x * cuv.y * cuv.y * pincushion;
	cuv.y -= cuv.y * cuv.x * cuv.x * pincushion * 0.35;
	vec2 uv = cuv * 0.5 + 0.5;

	// Horizontales Zittern des Videosignals (feines, zeilenweises Wackeln)
	float wob = sin(uv.y * 140.0 + signal_time * 9.0) * 0.35
		+ (fract(sin(signal_time * 71.13) * 43758.5453) - 0.5);
	uv.x += wob * jitter * motion_gain;

	// Abgerundete Röhrenmaske: weicher Übergang zur schwarzen Fassung statt
	// harter rechteckiger Kanten (Rundung wie bei einer echten Bildröhre).
	vec2 q = abs(uv - 0.5) - (vec2(0.5) - corner_radius);
	float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_radius;
	float tube = 1.0 - smoothstep(0.0, edge_softness, dist);

	if (tube <= 0.0) {
		COLOR = (vec4(0.0, 0.0, 0.0, 1.0)) * item_modulate;
	} else {
		// Farbsäume: R/B leicht gegeneinander versetzt, stärker zum Rand hin
		float edge = length(uv - 0.5);
		float ca = aberration * (0.35 + edge * edge * 2.0);
		float cav = vertical_aberration * (0.25 + edge * edge * 2.0);
		vec3 col;
		col.r = texture(screen_tex, uv + vec2(ca, cav)).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - vec2(ca, cav)).b;

		// Analoge Chroma-Bandbreite: Farben laufen horizontal weicher aus als
		// die Luminanz. Ein dezentes Nachbild simuliert langsamen Phosphor.
		vec3 bleed = (texture(screen_tex, uv - vec2(color_bleed, 0.0)).rgb
			+ texture(screen_tex, uv + vec2(color_bleed, 0.0)).rgb) * 0.5;
		col.rb = mix(col.rb, bleed.rb, 0.46);
		vec3 ghost = texture(screen_tex, uv - vec2(0.0015 + ghosting * 0.009, 0.0)).rgb;
		col = mix(col, max(col, ghost * 0.90), ghosting);
		vec3 soft = (texture(screen_tex, uv - vec2(SCREEN_PIXEL_SIZE.x * 1.5, 0.0)).rgb
			+ texture(screen_tex, uv + vec2(SCREEN_PIXEL_SIZE.x * 1.5, 0.0)).rgb) * 0.5;
		col += (col - soft) * sharpness;

		// Lesbarkeit: dezente Kontrastanhebung um die Bildmitte, damit helle
		// Schrift auf dem Röhrenbild deutlicher gegen den Hintergrund steht.
		col = clamp((col - 0.5) * (1.0 + text_boost) + 0.5, vec3(0.0), vec3(1.5));
		float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(vec3(luma), col, saturation);
		col = max(col - vec3(black_level), vec3(0.0)) / max(white_level - black_level, 0.01);
		col = pow(max(col, vec3(0.0)), vec3(1.0 / max(gamma, 0.01)));

		// Phosphor-Nachglühen: helle Stellen strahlen dezent nach
		col += col * col * bloom;

		// Beam-Scanlines: Zeilenmitte leuchtet, Lücke dunkelt ab — die mittlere
		// Helligkeit bleibt erhalten (leuchtet, statt nur alles abzudunkeln).
		float beam = sin(uv.y * 200.0 * 3.14159);
		float scan_visibility = 1.0 - smoothstep(0.5, 1.0, fwidth(uv.y) * 200.0);
		float scan = (1.0 + scanline_strength * scan_visibility * (beam * beam - 0.5));
		col *= scan;
		float field = mod(floor(uv.y / max(SCREEN_PIXEL_SIZE.y, 0.00001)) + floor(signal_time * 50.0), 2.0);
		col *= mix(1.0 - interlace_strength * motion_gain, 1.0, field);

		// Dezente RGB-Streifenmaske (Lochmasken-Gefühl)
		float px = floor(uv.x * mask_pitch);
		float m = mod(px, 3.0);
		vec3 mask = vec3(
			m == 0.0 ? 1.0 : 1.0 - rgb_mask_strength,
			m == 1.0 ? 1.0 : 1.0 - rgb_mask_strength,
			m == 2.0 ? 1.0 : 1.0 - rgb_mask_strength);
		col *= mask;

		// Der rollende Bildröhren-„Faden": ein weiches, helles Band, das langsam
		// nach oben durchs Bild wandert (Refresh-Desync einer echten Röhre).
		float band_center = fract(-signal_time * roll_speed);
		float d = abs(fract(uv.y - band_center + 0.5) - 0.5);
		float band = (1.0 - smoothstep(0.0, roll_width, d));
		col *= 1.0 + roll_strength * motion_gain * band * band;
		// Sehr langsames 50-Hz-Netzbrummband plus fein gekörntes HF-Rauschen.
		float hum = 0.5 + 0.5 * sin((uv.y * 1.7 + signal_time * hum_bar_speed) * 6.2831853);
		col *= 1.0 - hum_bar_strength * motion_gain * (0.35 + hum * 0.65);
		float grain = fract(sin(dot(floor(uv * vec2(720.0, 540.0)), vec2(12.9898, 78.233))
			+ floor(signal_time * 50.0) * 0.731) * 43758.5453);
		col += (grain - 0.5) * noise_strength;

		// Glas-Reflexion: weicher, heller Schein oben links auf der Röhre
		float refl = (1.0 - smoothstep(0.0, 0.55, length(uv - vec2(0.30, 0.24))));
		col += refl * reflection;

		// Vignette zu den Röhrenrändern
		vec2 v = uv * (1.0 - uv);
		float vig = pow(max(v.x * v.y * 16.0, 0.0), 0.25);
		col *= mix(1.0, vig, vignette_strength);

		// Ganz leichtes 50-Hz-Flackern
		col *= 1.0 - flicker_strength * motion_gain * (0.5 + 0.5 * sin(signal_time * 100.0));

		// Weicher Randabfall zur schwarzen Fassung (abgerundete Röhre)
		col *= tube;

		COLOR = (vec4(col, 1.0)) * item_modulate;
	}
}
