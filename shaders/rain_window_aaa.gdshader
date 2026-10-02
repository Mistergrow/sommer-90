shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float time = 0.0;
uniform float motion_speed : hint_range(0.25, 3.0) = 1.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.7;
uniform float wind : hint_range(-1.0, 1.0) = 0.0;
uniform float storm_factor : hint_range(0.0, 1.0) = 0.0;
uniform float impact_strength : hint_range(0.0, 2.0) = 1.0;
uniform float seed = 1.0;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

// Freier Regen VOR dem Fenster. Diese Ebene ist absichtlich schnell, duenn und
// weich. Sie gehoert optisch hinter das Glas und darf deshalb nicht dieselbe
// Geschwindigkeit wie haftende Tropfen oder Rinnsale besitzen.
float airborne_rain_layer(vec2 uv, float columns, float speed, float layer_seed,
		float anim_time) {
	vec2 q = uv;
	float slant = 0.035 + wind * 0.21;
	q.x += q.y * slant;
	q.x -= anim_time * wind * speed * 0.055;
	q.y -= anim_time * speed;
	vec2 grid = vec2(columns, columns * 0.58);
	vec2 id = floor(q * grid);
	vec2 gv = fract(q * grid) - 0.5;
	float rnd = hash21(id + vec2(layer_seed, seed * 11.7));
	float lane = (hash21(id + layer_seed * 4.9) - 0.5) * 0.54;
	float x = gv.x - lane - gv.y * (0.055 + wind * 0.19);
	float length_random = mix(0.18, 0.48, hash21(id + layer_seed * 8.2));
	float line = 1.0 - smoothstep(0.010, 0.055, abs(x));
	float body = 1.0 - smoothstep(length_random, length_random + 0.11, abs(gv.y));
	float head = 1.0 - smoothstep(0.012, 0.075, length(vec2(x, gv.y - length_random)));
	return max(line * body, head * 0.72) * step(0.54, rnd);
}

float splash_satellite(vec2 p, vec2 id, float epoch, float age, float index,
		float radius, float layer_seed) {
	float rnd = hash21(id + vec2(epoch * 3.17 + index * 13.1,
		layer_seed * 9.7 + index * 4.3));
	float angle = rnd * TAU + wind * 0.58;
	float distance = radius * mix(1.04, 1.62, hash21(id + index * 7.9 + epoch));
	vec2 direction = vec2(cos(angle), sin(angle));
	// Wind und Schwerkraft ziehen die kleinsten Splitter schon waehrend der sehr
	// kurzen Aufprallphase leicht seitlich beziehungsweise nach unten.
	vec2 center = direction * distance;
	center += vec2(wind * age * 0.045, age * age * 0.035);
	float dot_radius = mix(0.012, 0.025, rnd) * (1.0 - age * 0.34);
	return 1.0 - smoothstep(dot_radius, dot_radius * 2.25, length(p - center));
}

// Ein raeumlich und zeitlich gehashter Scheibenaufprall. Der Treffer existiert
// nur wenige Zehntelsekunden: Lichtkern -> gebrochene Krone -> Mikrospritzer.
// Danach bleibt manchmal eine kleine Perle zurueck. So entsteht Kontakt mit dem
// Glas statt eines permanent nach unten verschobenen Musters.
vec4 impact_layer(vec2 uv, float cells, float rate, float layer_seed,
		float anim_time) {
	vec2 grid = vec2(cells, cells * 0.62);
	vec2 id = floor(uv * grid);
	vec2 gv = fract(uv * grid) - 0.5;
	float phase_offset = hash21(id + vec2(layer_seed, seed * 5.7));
	float phase = anim_time * rate + phase_offset;
	float epoch = floor(phase);
	float cycle_age = fract(phase);
	float event_random = hash21(id + vec2(epoch * 5.13 + layer_seed,
		epoch * 1.71 + seed * 8.9));
	float chance = mix(0.075, 0.19, storm_factor) * intensity;
	float spawned = step(1.0 - chance, event_random);
	float life = mix(0.24, 0.38, hash21(id + epoch + layer_seed * 2.4));
	float age = cycle_age / max(life, 0.001);
	float alive = spawned * (1.0 - step(1.0, age));

	vec2 hit = vec2(
		hash21(id + vec2(epoch * 2.7, layer_seed * 11.3)),
		hash21(id + vec2(layer_seed * 3.9, epoch * 7.1))
	);
	hit = (hit - 0.5) * 0.42;
	vec2 p = gv - hit;
	// Schraeg auftreffender Regen ergibt eine Ellipse, keine Feuerwerks-Kreise.
	p.x -= wind * p.y * 0.34;
	p.x -= wind * age * 0.025;
	float distance_to_hit = length(p * vec2(1.0, mix(1.18, 1.42, abs(wind))));
	float eased_age = age * age * (3.0 - 2.0 * age);
	float radius = mix(0.015, 0.235, eased_age);
	float ring_width = mix(0.048, 0.014, age);
	float angle = atan(p.y, p.x);
	// Oberflaechenspannung, schrager Kontakt und vorhandener Wasserfilm machen
	// eine echte Krone unregelmaessig. Ein geometrisch perfekter Kreis liest sich
	// sonst sofort wie ein HUD-Ring oder Einschussloch.
	float radius_variation = 1.0 + sin(angle * 3.0 + event_random * 19.0) * 0.13 +
		sin(angle * 7.0 - event_random * 31.0) * 0.055;
	float ring = 1.0 - smoothstep(ring_width, ring_width * 2.15,
		abs(distance_to_hit - radius * radius_variation));
	float arc_wave_a = 0.5 + 0.5 * sin(angle * (5.0 + mod(epoch, 3.0)) + event_random * 17.0);
	float arc_wave_b = 0.5 + 0.5 * sin(angle * 11.0 - event_random * 29.0 + age * 1.8);
	float broken_arcs = max(smoothstep(0.43, 0.70, arc_wave_a),
		smoothstep(0.64, 0.84, arc_wave_b) * 0.58);
	float strike_side = mix(0.58, 1.0, smoothstep(-0.75, 0.65,
		cos(angle - wind * 0.72)));
	float crown = ring * broken_arcs * strike_side *
		(1.0 - smoothstep(0.62, 1.0, age));
	float core = (1.0 - smoothstep(0.018, 0.075, distance_to_hit)) *
		(1.0 - smoothstep(0.06, 0.42, age));
	float satellites = splash_satellite(p, id, epoch, age, 1.0, radius, layer_seed);
	satellites += splash_satellite(p, id, epoch, age, 2.0, radius, layer_seed);
	satellites += splash_satellite(p, id, epoch, age, 3.0, radius, layer_seed);
	satellites += splash_satellite(p, id, epoch, age, 4.0, radius, layer_seed);
	satellites += splash_satellite(p, id, epoch, age, 5.0, radius, layer_seed);
	satellites = clamp(satellites, 0.0, 1.0) * smoothstep(0.08, 0.28, age) *
		(1.0 - smoothstep(0.58, 0.96, age));
	// Nur ein Teil der Treffer hinterlaesst eine sichtbare Perle. Diese liegt nach
	// der Krone kurz ruhig auf dem Glas, statt sofort als Rinnsal loszulaufen.
	float deposits = step(0.42, hash21(id + epoch * 4.1 + layer_seed * 6.2));
	float deposit_age = smoothstep(life * 0.72, life, cycle_age) *
		(1.0 - smoothstep(0.82, 0.98, cycle_age));
	float deposit = (1.0 - smoothstep(0.020, 0.061, distance_to_hit)) *
		spawned * deposits * deposit_age;
	return vec4(core, crown, satellites, deposit) * alive + vec4(0.0, 0.0, 0.0, deposit);
}

vec3 drop_layer(vec2 uv, float columns, float speed, float layer_seed, float anim_time) {
	uv.x += uv.y * (wind * 0.13 + 0.018);
	vec2 grid = vec2(columns, columns * 0.43);
	vec2 id = floor(uv * grid);
	vec2 gv = fract(uv * grid) - 0.5;
	float rnd = hash21(id + layer_seed + seed * 19.7);
	float active = step(0.38, rnd);
	float lane = (hash21(id + layer_seed * 7.3) - 0.5) * 0.54;
	// Tropfen haften lange. Nur ihre sehr langsame Kriechphase verändert die
	// Position; dadurch läuft nicht mehr das ganze Fenster wie ein Förderband.
	float travel = fract(anim_time * speed * (0.45 + rnd * 0.55) + rnd * 13.7);
	float y = gv.y + 0.5 - travel;
	y = fract(y + 0.5) - 0.5;
	float x = gv.x - lane - sin((gv.y + rnd) * 8.0) * 0.025;
	float head = (1.0 - smoothstep(0.012, 0.105, length(vec2(x, y * 1.65))));
	float trail_gate = (1.0 - smoothstep(0.02, 0.46, -y)) * smoothstep(-0.50, -0.02, -y);
	float trail = (1.0 - smoothstep(0.006, 0.040, abs(x))) * trail_gate;
	float bead = (1.0 - smoothstep(0.004, 0.028, abs(x + 0.012))) *
		(1.0 - smoothstep(0.03, 0.44, abs(y + 0.20)));
	return vec3(head, trail * (0.35 + rnd * 0.65), bead) * active;
}

float streak_layer(vec2 uv, float scale, float speed, float layer_seed, float anim_time) {
	float column = floor(uv.x * scale);
	float rnd = hash21(vec2(column + layer_seed * 17.0, seed * 9.1));
	float row_scale = scale * (0.24 + rnd * 0.20);
	float y = fract(uv.y * row_scale - anim_time * speed * (0.72 + rnd * 0.55) + rnd * 11.0);
	float x = fract(uv.x * scale) - 0.5;
	x -= (y - 0.5) * (0.10 + wind * 0.32);
	x += sin(y * 6.2831 + rnd * 12.0) * 0.025;
	float line = (1.0 - smoothstep(0.012, 0.115, abs(x)));
	float head = (1.0 - smoothstep(0.015, 0.16, abs(y - 0.72)));
	float tail = (1.0 - smoothstep(0.13, 0.72, y)) * smoothstep(0.01, 0.12, y);
	return line * max(head, tail * 0.48) * step(0.58, rnd);
}

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	float anim_time = time * motion_speed;
	vec2 uv = (UV - uv_rect.xy) / max(uv_rect.zw - uv_rect.xy, vec2(0.0001));
	uv = clamp(uv, vec2(0.0), vec2(1.0));
	float gust = mix(0.72, 1.0, value_noise(vec2(anim_time * 0.31 + seed, seed * 2.7)));
	float far_rain = airborne_rain_layer(uv, 47.0, 2.45, 5.3, anim_time);
	float near_rain = airborne_rain_layer(uv + vec2(0.17, 0.08), 29.0,
		3.85 + storm_factor * 1.1, 14.7, anim_time);
	float airborne = (far_rain * 0.34 + near_rain * 0.72) * gust;
	float film_a = value_noise(uv * vec2(7.0, 14.0) + vec2(anim_time * 0.0024, -anim_time * 0.0038));
	float film_b = value_noise(uv * vec2(19.0, 8.0) + vec2(-anim_time * 0.0017, anim_time * 0.0029));
	vec2 film_normal = vec2(dFdx(film_a + film_b * 0.45), dFdy(film_a + film_b * 0.45));
	vec4 impacts_near = impact_layer(uv, 9.0, mix(0.46, 0.72, storm_factor), 7.1, anim_time);
	vec4 impacts_fine = impact_layer(uv + vec2(0.071, 0.039), 16.0,
		mix(0.58, 0.94, storm_factor), 19.3, anim_time);
	vec4 impacts = impacts_near + impacts_fine * vec4(0.58, 0.66, 0.48, 0.54);
	float impact_height = impacts.x * 1.0 + impacts.y * 0.64 + impacts.z * 0.46 + impacts.w * 0.72;
	vec2 impact_normal = vec2(dFdx(impact_height), dFdy(impact_height));
	vec2 screen_px = 1.0 / vec2(textureSize(screen_texture, 0));
	vec2 refract_uv = SCREEN_UV + film_normal * screen_px * (3.0 + intensity * 8.0) +
		impact_normal * screen_px * (15.0 + intensity * 19.0) * impact_strength;
	vec3 scene = textureLod(screen_texture, refract_uv, 0.45 + intensity * 0.8).rgb;
	// Haftende Tropfen kriechen klar sichtbar, während nur einzelne Rinnsale
	// schneller ablaufen. Die Ebenen besitzen bewusst verschiedene Tempi.
	vec3 far_drops = drop_layer(uv, 21.0, 0.082, 2.3, anim_time);
	vec3 mid_drops = drop_layer(uv + vec2(0.17, 0.04), 13.0, 0.057, 9.1, anim_time);
	vec3 near_drops = drop_layer(uv + vec2(0.33, 0.11), 7.0, 0.036, 17.7, anim_time);
	vec3 drops = far_drops * 0.34 + mid_drops * 0.66 + near_drops;
	// Wenige deutlich laufende Rinnsale liefern die lesbare Bewegung. Sie sind
	// weit langsamer als frei fallender Außenregen und bewegen sich nicht mehr
	// als gleichförmiger Vorhang.
	float streaks = streak_layer(uv, 29.0, 1.08, 3.7, anim_time) * 0.32 +
		streak_layer(uv + vec2(0.21, 0.13), 17.0, 0.72, 11.2, anim_time) * 0.48 +
		streak_layer(uv + vec2(0.48, 0.27), 9.0, 0.43, 27.4, anim_time) * 0.62;
	float water = clamp(drops.x + drops.y * 0.72 + drops.z * 0.45, 0.0, 1.0);
	float edge = drops.y * 0.15 + drops.x * 0.30;
	vec3 wet_scene = scene * mix(vec3(1.0), vec3(0.72, 0.80, 0.93), intensity * 0.16);
	// Der freie Regen ist schnell und leicht unscharf. Er liegt optisch hinter den
	// scharfen Aufprallkanten und dem langsamen Wasser auf dem Glas.
	wet_scene += vec3(0.54, 0.70, 0.92) * airborne * intensity *
		mix(0.18, 0.31, storm_factor);
	wet_scene -= vec3(0.035, 0.025, 0.012) * edge * intensity;
	wet_scene += vec3(0.58, 0.77, 1.0) * water * intensity * 0.58;
	wet_scene += vec3(0.93, 0.97, 1.0) * drops.x * intensity * 0.36;
	wet_scene += vec3(0.30, 0.58, 1.0) * streaks * intensity * 0.38;
	wet_scene += vec3(0.82, 0.92, 1.0) * streaks * streaks * intensity * 0.18;
	// Aufpralllicht ist kurz, gebrochen und normalbasiert. Der dunkle Gegenrand
	// verhindert aufgemalte neonblaue Kreise auf hellen Teilen des Aussenbildes.
	wet_scene -= vec3(0.055, 0.070, 0.085) * impacts.y * intensity * impact_strength * 0.55;
	wet_scene += vec3(0.93, 0.98, 1.0) * impacts.x * intensity * impact_strength * 0.86;
	wet_scene += vec3(0.67, 0.84, 1.0) * impacts.y * intensity * impact_strength * 0.58;
	wet_scene += vec3(0.83, 0.93, 1.0) * impacts.z * intensity * impact_strength * 0.62;
	wet_scene += vec3(0.72, 0.86, 1.0) * impacts.w * intensity * impact_strength * 0.34;
	float sheen = pow(clamp(1.0 - abs(film_a - 0.53) * 7.0, 0.0, 1.0), 3.0);
	wet_scene += vec3(0.22, 0.34, 0.48) * sheen * intensity * 0.055;
	COLOR = (vec4(wet_scene, 1.0)) * item_modulate;
}
