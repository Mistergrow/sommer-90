shader_type canvas_item;
// Prozedurales Material-Varianten-System (docs/MATERIAL_SYSTEM.md).
// EIN Master-PNG + EIN Masken-PNG erzeugen tausende Varianten:
// Farbe, Alterung, Staub, Kratzer — alles Shader-Parameter, keine
// Textur-Duplikate. Maske: R = Plastik, G = Metall, B = Papier/Label.

// ACHTUNG: ungebundene Sampler liefern WEISS — recolor_strength muss
// deshalb default 0 sein, sonst faerben maskenlose Objekte komplett um.
// repeat_disable: sonst „wrappt" die Maske beim Schräg-Versatz (skew) und die
// Alterung (Metall/Papier) läuft als Geister-Streifen an der Kante auf.
uniform sampler2D mask_tex : filter_nearest, repeat_disable;
uniform float recolor_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 plastic_color : source_color = vec4(0.23, 0.35, 0.78, 1.0);
uniform float plastic_saturation : hint_range(0.0, 2.0) = 1.0;
uniform float plastic_brightness : hint_range(0.2, 2.0) = 1.0;
uniform float yellowing_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.0;
uniform float scratch_amount : hint_range(0.0, 1.0) = 0.0;
uniform float metal_wear : hint_range(0.0, 1.0) = 0.0;
uniform float paper_age : hint_range(0.0, 1.0) = 0.0;
// Schraeger Versatz (Deko: Alt+Mausrad): unten fix, oben seitlich —
// skew_top ist auf die Inhaltsbreite normiert, widen = Rect-Verbreiterung.
uniform float skew_top = 0.0;
uniform float widen = 1.0;

// --- Szenen-Licht-Integration (3D-Anmutung) ---------------------------------
// Flache Foto-Ausschnitte ins Raumlicht setzen: leichte Volumen-Schattierung
// zur Lichtseite, warmes Kantenlicht auf der dem Fenster zugewandten Kante
// (aus der Alpha-Silhouette) und ein Kontakt-Abdunkeln am Fuss. Default AUS
// (scene_light = 0), damit sich ohne Aktivierung nichts aendert.
uniform float scene_light : hint_range(0.0, 1.0) = 0.0;   // Master an/aus
uniform vec2 light_dir = vec2(0.75, -0.66);               // UV: +x rechts, -y oben (Fenster)
uniform float form_strength : hint_range(0.0, 1.0) = 0.24; // Volumen-Tilt
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;   // Kantenlicht
uniform float rim_width : hint_range(0.5, 6.0) = 2.0;      // Breite des Kantenlichts (Texel)
uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.6); // warmes Fensterlicht
uniform float ao_strength : hint_range(0.0, 1.0) = 0.2;    // Kontakt-Abdunkeln unten
uniform vec3 warm_tint : source_color = vec3(1.05, 0.99, 0.88);
uniform float warm_amount : hint_range(0.0, 1.0) = 0.12;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	float x_wide = UV.x * widen;
	float shear_off = max(-skew_top, 0.0) + skew_top * (1.0 - UV.y);
	float u = x_wide - shear_off;
	if (u < 0.0 || u > 1.0) {
		COLOR = vec4(0.0);
	} else {
	vec2 uv = vec2(u, UV.y);
	vec4 base = texture(TEXTURE, uv);
	vec3 mask = texture(mask_tex, uv).rgb;
	vec3 col = base.rgb;

	// Plastik umfaerben: Helligkeit/Schattierung der Basis bleibt,
	// nur der Farbton wird ersetzt (Metall/Papier unberuehrt).
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 recol = plastic_color.rgb * lum * 1.9 * plastic_brightness;
	recol = mix(vec3(lum * plastic_brightness), recol, plastic_saturation);
	col = mix(col, recol, mask.r * recolor_strength);

	// Vergilbung (Plastik + Papier), Papier-Alterung, Metall-Anlaufen
	col = mix(col, col * vec3(1.02, 0.94, 0.72), yellowing_amount * max(mask.r, mask.b));
	col = mix(col, col * vec3(0.92, 0.86, 0.70), paper_age * mask.b);
	col = mix(col, col * vec3(0.75, 0.73, 0.70), metal_wear * mask.g);

	// Kratzer: feine helle Streifen im Plastik
	float streak = smoothstep(0.985, 1.0, hash21(floor(uv * vec2(180.0, 14.0))));
	col += streak * scratch_amount * 0.35 * mask.r;

	// Staub: koerniges, mattes Aufhellen
	float dust = hash21(floor(uv * 320.0)) * dust_amount * 0.25;
	col = mix(col, vec3(0.78, 0.75, 0.70), dust * max(mask.r, mask.g));

	// --- Szenen-Licht: Objekt ins Raumlicht setzen (3D-Anmutung) ---
	if (scene_light > 0.001) {
		vec2 ld = light_dir / max(length(light_dir), 0.0001);
		// Volumen-Tilt: heller zur Lichtseite (oben/rechts), dunkler abgewandt
		float along = (uv.x - 0.5) * ld.x + (uv.y - 0.5) * ld.y;
		col *= 1.0 + clamp(along, -0.6, 0.6) * form_strength * scene_light;
		// Kontakt-AO: unteren Rand abdunkeln (Objekt sitzt auf der Flaeche)
		col *= 1.0 - ao_strength * scene_light * smoothstep(0.55, 1.0, UV.y);
		// warme Toenung, damit der Ausschnitt farblich in den Raum passt
		col = mix(col, col * warm_tint, warm_amount * scene_light);
		// Kantenlicht an der dem Fenster zugewandten Silhouettenkante (hier ist
		// Alpha da, in Lichtrichtung aber schon transparent = Aussenkante)
		float ahead = texture(TEXTURE, uv + ld * TEXTURE_PIXEL_SIZE * rim_width).a;
		float rim = clamp(base.a - ahead, 0.0, 1.0);
		col += rim_color * rim * rim_strength * scene_light;
	}

	COLOR = vec4(col, base.a) * item_modulate;
	}
}
