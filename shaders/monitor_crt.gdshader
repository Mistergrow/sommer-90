// Monitor-LOKALER CRT-Effekt (EFFECT_005, Slot crt_glow): liegt direkt auf dem
// Röhren-Standbild und macht den Bildröhren-Look — pro Modell aus data/monitors.json
// (1084S ≠ 1901 = Qualität) und, solange nicht kalibriert, in einer von drei
// "uncalibrated"-Varianten (Geometrie/Fokus/Farbe). Anders als der optionale
// Vollbild-Filter (shaders/crt.gdshader, F10) gehört DIESER Effekt fest zum Monitor.
shader_type canvas_item;

uniform float curvature   : hint_range(0.0, 0.35) = 0.06; // Tonnen-Krümmung der Röhre
uniform float scanline    : hint_range(0.0, 1.0)  = 0.30; // Zeilenstärke
uniform float bloom       : hint_range(0.0, 0.8)  = 0.10; // Phosphor-Nachglühen
uniform float aberration  : hint_range(0.0, 0.02) = 0.0;  // Konvergenz/Farbsäume
uniform float vignette    : hint_range(0.0, 1.0)  = 0.14; // Randabdunklung
uniform float brightness  : hint_range(0.2, 1.8)  = 1.15; // Leuchtkraft
uniform vec3  phosphor     = vec3(1.0);                    // Röhrenfarbton (Modell)
uniform vec3  tint         = vec3(1.0);                    // Farbstich (uncalibrated)
uniform float roll_strength : hint_range(0.0, 0.6) = 0.0; // rollendes Helligkeitsband
uniform float roll_speed  : hint_range(0.0, 1.0)  = 0.16;
uniform float flicker     : hint_range(0.0, 0.2)  = 0.0;  // 50-Hz-Flackern
uniform float jitter      : hint_range(0.0, 0.01) = 0.0;  // Signal-Zittern (H)
uniform float focus       : hint_range(0.0, 1.0)  = 0.70; // Strahlfokus/Maskenschaerfe
uniform float mask_strength : hint_range(0.0, 0.5) = 0.22; // sichtbare RGB-Schattenmaske
uniform float interlace_artifact : hint_range(0.0, 0.5) = 0.25; // Zeilenflimmern

uniform bool reduced_motion = false;
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	float signal_time = reduced_motion ? 0.0 : TIME;
	float motion_gain = reduced_motion ? 0.0 : 1.0;
	// UV um die Bildmitte krümmen (Tonne). Außerhalb → schwarze Fassung.
	vec2 c = UV * 2.0 - 1.0;
	c += c * (c.yx * c.yx) * curvature;
	vec2 uv = c * 0.5 + 0.5;

	// Feines horizontales Signal-Zittern
	uv.x += (sin(uv.y * 130.0 + signal_time * 9.0) * 0.4
		+ (fract(sin(signal_time * 71.13) * 43758.5) - 0.5)) * jitter * motion_gain;

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = (vec4(0.0, 0.0, 0.0, 1.0)) * item_modulate;
	} else {
		// Konvergenz/Farbsäume: R/B gegeneinander versetzt, stärker zum Rand
		float edge = length(uv - 0.5);
		float ca = aberration * (0.4 + edge * edge * 2.0);
		vec4 base = texture(TEXTURE, uv);
		vec3 col;
		col.r = texture(TEXTURE, uv + vec2(ca, 0.0)).r;
		col.g = base.g;
		col.b = texture(TEXTURE, uv - vec2(ca, 0.0)).b;

		// Modellabhaengiger Strahlfokus. Ein 1084S bleibt sichtbar weicher,
		// waehrend 0,28-/0,25-mm-Multisync-Roehren feine Pixelkanten erhalten.
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec3 neighbours = (
			texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb
			+ texture(TEXTURE, uv - vec2(px.x, 0.0)).rgb
			+ texture(TEXTURE, uv + vec2(0.0, px.y)).rgb
			+ texture(TEXTURE, uv - vec2(0.0, px.y)).rgb) * 0.25;
		col = mix(neighbours, col, focus);

		// Phosphor-Nachglühen: helle Stellen strahlen nach
		col += col * col * bloom;

		// Beam-Scanlines (helligkeitserhaltend)
		float beam = sin(uv.y * 210.0 * 3.14159);
		// Suppress frequencies a small/distant monitor cannot resolve.
		float scan_visibility = 1.0 - smoothstep(0.5, 1.0, fwidth(uv.y) * 210.0);
		col *= (1.0 + scanline * scan_visibility * (beam * beam - 0.5));

		// RGB-Schattenmaske. Spaete feine Multisync-Masken nutzen eine deutlich
		// kleinere Intensitaet; dadurch wirkt dieselbe Workbench sichtbar ruhiger.
		float triad = mod(FRAGCOORD.x, 3.0);
		vec3 aperture = triad < 1.0 ? vec3(1.0, 0.78, 0.78)
			: (triad < 2.0 ? vec3(0.78, 1.0, 0.78) : vec3(0.78, 0.78, 1.0));
		col *= mix(vec3(1.0), aperture, mask_strength);

		// Halbbild-Flimmern ist ein echter sichtbarer Qualitätsunterschied:
		// bei Multisync/HiRes fast verschwunden, auf 15-kHz-Roehren praesent.
		float field_line = step(0.5, fract(FRAGCOORD.y * 0.5 + signal_time * 25.0));
		col *= 1.0 - interlace_artifact * motion_gain * field_line * 0.12;

		// Rollender Bildröhren-Faden
		if (roll_strength > 0.0 && !reduced_motion) {
			float band_center = fract(-signal_time * roll_speed);
			float d = abs(fract(uv.y - band_center + 0.5) - 0.5);
			col *= 1.0 + roll_strength * (1.0 - smoothstep(0.0, 0.16, d));
		}

		// Vignette zu den Röhrenrändern
		vec2 v = uv * (1.0 - uv);
		col *= mix(1.0, pow(max(v.x * v.y * 16.0, 0.0), 0.25), vignette);

		// 50-Hz-Flackern
		if (flicker > 0.0 && !reduced_motion) col *= 1.0 - flicker * (0.5 + 0.5 * sin(signal_time * 100.0));

		col *= phosphor * tint * brightness;
		COLOR = (vec4(col, base.a)) * item_modulate;
	}
}
