class_name SfxSynth
## Prozedurale 90er-Computer-Sounds — synthetisiert als AudioStreamWAV, KEINE
## externen Dateien nötig. Iconische, gut synthetisierbare Elektronik-Klänge:
## Tastaturklick, Modem-Einwahl-Handshake, CRT-Brummen (Loop), Relais/Netzschalter,
## UI-Blip, Regen (Loop) und Donner. Vom AudioManager beim Start erzeugt.
##
## Alles Mono, 22050 Hz, 16-bit PCM — bewusst rau/retro. Loops sauber gesetzt.

const RATE := 22050
const SynthCore := preload("res://scripts/audio/synth_core.gd")


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	return SynthCore.to_wav(samples, RATE, loop)


static func _wav_stereo(left: PackedFloat32Array, right: PackedFloat32Array) -> AudioStreamWAV:
	var frame_count := mini(left.size(), right.size())
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 4)
	for i in frame_count:
		bytes.encode_s16(i * 4, int(clampf(left[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(right[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = bytes
	return wav


static func _n(count: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(count)
	return a


# --------------------------------------------------------------- UI / Mechanik
## Kurzer, freundlicher UI-Blip (Fenster/Klick).
static func ui_blip() -> AudioStreamWAV:
	var n := int(RATE * 0.06)
	var s := _n(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 42.0)
		s[i] = sin(TAU * 880.0 * t) * 0.32 * env + sin(TAU * 1320.0 * t) * 0.14 * env
	return _wav(s)


## Mechanischer Tastenklick (gefiltertes Rausch-Knacken + kleiner Ton).
static func key_click() -> AudioStreamWAV:
	var n := int(RATE * 0.035)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 150.0)
		var noise := rng.randf_range(-1.0, 1.0)
		prev = prev * 0.6 + noise * 0.4          # weiches Tiefpass-Knacken
		s[i] = (prev * 0.7 + sin(TAU * 220.0 * t) * 0.3) * env * 0.5
	return _wav(s)


## Relais / Netzschalter — zwei satte Klicks.
static func relay() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / RATE
		var click1 := exp(-pow((t - 0.005) * 260.0, 2.0))
		var click2 := exp(-pow((t - 0.075) * 220.0, 2.0))
		s[i] = rng.randf_range(-1.0, 1.0) * (click1 + click2 * 0.8) * 0.6
	return _wav(s)


## Trockener Mikroschalter-Klick eines Digitaljoysticks.
static func joystick_click() -> AudioStreamWAV:
	var n := int(RATE * 0.055)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990
	for i in n:
		var t := float(i) / RATE
		var snap := exp(-pow((t - 0.006) * 310.0, 2.0))
		var body := sin(TAU * 185.0 * t) * exp(-t * 72.0)
		s[i] = rng.randf_range(-1.0, 1.0) * snap * 0.52 + body * 0.24
	return _wav(s)


## Sehr leises Kolophonium-/Zinn-Zischen beim Kontakt der heißen Spitze.
static func solder_touch() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4096
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lp * 0.74 + noise * 0.26
		var env := sin(PI * clampf(t / 0.18, 0.0, 1.0)) * exp(-t * 3.0)
		s[i] = (noise - lp * 0.55) * env * 0.18
	return _wav(s)


## Kurzer Durchgangsprüfer: zwei saubere aufsteigende Töne.
static func continuity_ok() -> AudioStreamWAV:
	var n := int(RATE * 0.24)
	var s := _n(n)
	for i in n:
		var t := float(i) / RATE
		var first := 1.0 if t < 0.095 else 0.0
		var second := 1.0 if t >= 0.125 and t < 0.22 else 0.0
		var local_t := t if first > 0.0 else maxf(0.0, t - 0.125)
		var env := exp(-local_t * 22.0)
		s[i] = (sin(TAU * 660.0 * t) * first + sin(TAU * 990.0 * t) * second) * env * 0.24
	return _wav(s)


## Dumpfer Doppelblip für Kaltstelle/Brücke, ohne schrillen Fehlerton.
static func joint_bad() -> AudioStreamWAV:
	var n := int(RATE * 0.28)
	var s := _n(n)
	for i in n:
		var t := float(i) / RATE
		var e1 := exp(-pow((t - 0.035) * 28.0, 2.0))
		var e2 := exp(-pow((t - 0.18) * 28.0, 2.0))
		s[i] = sin(TAU * 145.0 * t) * (e1 + e2 * 0.82) * 0.30
	return _wav(s)


## Magnetstreifenkarte wird vom alten Rollenleser eingezogen/ausgeworfen:
## kurzer Gleichstrommotor, Gummiwalze und ein sattes Endschalter-Klick.
static func atm_card() -> AudioStreamWAV:
	var n := int(RATE * 0.48)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 904271
	for i in n:
		var t := float(i) / RATE
		var motor_env := sin(PI * clampf(t / 0.42, 0.0, 1.0))
		var motor := (sin(TAU * 118.0 * t) * 0.22 + sin(TAU * 236.0 * t) * 0.08) * motor_env
		var roller := rng.randf_range(-1.0, 1.0) * (0.04 + 0.03 * sin(TAU * 27.0 * t)) * motor_env
		var stop_click := rng.randf_range(-1.0, 1.0) * exp(-pow((t - 0.43) * 170.0, 2.0)) * 0.55
		s[i] = motor + roller + stop_click
	return _wav(s)


## Banknoten-Ausgabe: Transportmotor, drei getrennte Zaehlerimpulse und
## Ausgabeklappe. Bewusst mechanisch und langsamer als moderne Recycler.
static func atm_dispense() -> AudioStreamWAV:
	var n := int(RATE * 1.15)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990400
	for i in n:
		var t := float(i) / RATE
		var motor_env := sin(PI * clampf(t / 1.05, 0.0, 1.0))
		var motor := (sin(TAU * 82.0 * t) * 0.17 + sin(TAU * 164.0 * t) * 0.07) * motor_env
		var paper_feed := rng.randf_range(-1.0, 1.0) * 0.045 * motor_env
		var pulses := 0.0
		for p in [0.30, 0.49, 0.68]:
			pulses += rng.randf_range(-1.0, 1.0) * exp(-pow((t - float(p)) * 115.0, 2.0)) * 0.33
		var hatch := rng.randf_range(-1.0, 1.0) * exp(-pow((t - 1.02) * 85.0, 2.0)) * 0.52
		s[i] = motor + paper_feed + pulses + hatch
	return _wav(s)


## Kurze Tracker-/Paula-artige Spielsignale. Das ist absichtlich keine MOD-Datei:
## klassische MODs spielen kurze 8-Bit-Samples über vier Paula-Kanäle ab. Hier
## wird genau dieses Klangprinzip als deterministischer One-shot erzeugt, ohne
## für jeden Minispielgriff eine weitere Audiodatei in den Export zu legen.
static func tracker_cue(id: String, event: StringName = &"action",
		root_frequency: float = 0.0) -> AudioStreamWAV:
	var patterns := {
		&"focus": [0, 7],
		&"action": [0, 4, 7],
		&"hint": [7, 12, 16],
		&"warning": [0, -2, 0, -5],
		&"error": [0, -1, -6],
		&"success": [0, 4, 7, 12],
	}
	var pattern: Array = patterns.get(event, patterns[&"action"])
	var duration := float({
		&"focus": 0.075, &"action": 0.12, &"hint": 0.16,
		&"warning": 0.20, &"error": 0.19, &"success": 0.27,
	}.get(event, 0.12))
	var root := root_frequency
	if root <= 0.0:
		root = 165.0 + float(posmod(id.hash(), 220))
	var frames := maxi(1, roundi(RATE * duration))
	var step_length := duration / float(pattern.size())
	var samples := _n(frames)
	var id_phase := float(posmod(id.hash(), 4096)) * 0.001
	for i in frames:
		var t := float(i) / RATE
		var step := mini(pattern.size() - 1, floori(t / step_length))
		var local_t := fmod(t, step_length)
		var note := float(pattern[step])
		var frequency := root * pow(2.0, note / 12.0)
		# Kanal 1: raues 8-Bit-Sägezahn-Sample.
		var saw_phase := fmod(t * frequency, 1.0)
		var lead := saw_phase * 2.0 - 1.0
		# Kanal 2: Rechteck eine Oktave tiefer, wie ein kurzes Bass-Sample.
		var bass := (1.0 if fmod(t * frequency * 0.5, 1.0) < 0.5 else -1.0) * 0.24
		# Kanal 3: 50-Hz-Arpeggio, typisch für kleine Tracker-Akkorde.
		var arp_tick := floori(t * 50.0) % 3
		var arp_note: float = float([0.0, 4.0, 7.0][arp_tick])
		var arp_frequency := frequency * pow(2.0, arp_note / 12.0)
		var arp := sin(TAU * arp_frequency * t) * 0.26
		# Kanal 4: sehr kurzes, deterministisches Noise-Sample für Anschlag/Fehler.
		var noise := sin((float(i * 1103515245) + id_phase) * 0.000001)
		var noise_level := 0.20 if event in [&"action", &"warning", &"error"] else 0.08
		var step_envelope := pow(1.0 - clampf(local_t / step_length, 0.0, 1.0), 1.35)
		var master_envelope := pow(1.0 - float(i) / float(frames), 0.8)
		var value := (lead * 0.36 + bass + arp + noise * noise_level) \
			* step_envelope * master_envelope
		# Paula-Samplecharakter: Amplitude vor dem 16-Bit-Container auf 8 Bit rastern.
		samples[i] = roundf(clampf(value, -1.0, 1.0) * 127.0) / 127.0
	return _wav(samples)


# --------------------------------------------------------------- CRT
## CRT-Brummen als nahtloser Loop: 50-Hz-Netzbrumm + leiser 15,7-kHz-Zeilentrafo.
static func crt_hum() -> AudioStreamWAV:
	# Ganzzahlige Perioden für sauberes Loopen (50 Hz → 441 Samples).
	var n := floori(float(RATE) / 50.0)    # 441
	var s := _n(n)
	for i in n:
		var t := float(i) / RATE
		var hum := sin(TAU * 50.0 * t) * 0.5 + sin(TAU * 100.0 * t) * 0.2
		var flyback := sin(TAU * 15734.0 * t) * 0.06
		s[i] = hum * 0.09 + flyback
	return _wav(s, true)


## CRT abschalten — absteigender Zeilenpfiff + „Plopp".
static func crt_off() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(15734.0, 400.0, clampf(t / 0.35, 0.0, 1.0))
		var whine := sin(TAU * f * t) * 0.12 * exp(-t * 5.0)
		var plop := rng.randf_range(-1.0, 1.0) * exp(-pow((t - 0.02) * 90.0, 2.0)) * 0.5
		s[i] = whine + plop
	return _wav(s)


# --------------------------------------------------------------- Modem
## Iconischer Modem-Einwahl-Handshake: Freizeichen → 4 DTMF-Ziffern →
## Carrier-Pfeifen + Trägerrausch. Bewusst nostalgisch (~3,2 s).
static func modem_dial() -> AudioStreamWAV:
	var n := int(RATE * 3.2)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	var seg := func(a: float, b: float, t: float) -> float:
		return 1.0 if t >= a and t < b else 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		# Freizeichen (Dauerton 425 Hz)
		v += sin(TAU * 425.0 * t) * 0.22 * seg.call(0.0, 0.5, t)
		# 4 DTMF-Ziffern (je Doppelton, kurze Pausen)
		var digits := [[697.0, 1209.0], [770.0, 1336.0], [852.0, 1477.0], [697.0, 1477.0]]
		for d in 4:
			var d0 := 0.6 + d * 0.18
			var pair: Array = digits[d]
			var g: float = seg.call(d0, d0 + 0.12, t)
			v += (sin(TAU * pair[0] * t) + sin(TAU * pair[1] * t)) * 0.16 * g
		# Handshake: Carrier-Töne + Trägerrausch ab ~1,5 s
		if t >= 1.5:
			var hs := clampf((t - 1.5) / 0.3, 0.0, 1.0)
			v += sin(TAU * 1070.0 * t) * 0.12 * hs
			v += sin(TAU * 2225.0 * t) * 0.10 * hs
			# rauer Träger-Screech (moduliertes Rauschen)
			var mod := 0.5 + 0.5 * sin(TAU * 15.0 * t)
			v += rng.randf_range(-1.0, 1.0) * 0.10 * hs * mod
			if t >= 2.6:  # „Verbindung steht" — Rauschen fällt ab
				v *= clampf(1.0 - (t - 2.6) / 0.6, 0.15, 1.0)
		s[i] = clampf(v, -1.0, 1.0)
	return _wav(s)


# --------------------------------------------------------------- Wetter
## Regen als nahtloser Loop (gefiltertes Rauschen, dezente Tropfen-Textur).
static func rain() -> AudioStreamWAV:
	var n := int(RATE * 2.0)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var white := rng.randf_range(-1.0, 1.0)
		lp = lp * 0.86 + white * 0.14          # Tiefpass = Rauschen wird „nass"
		hp = white - lp                        # etwas Zischen dazu
		s[i] = lp * 0.5 + hp * 0.12
	# nahtlos: die letzten Samples in die ersten überblenden
	var xf := int(RATE * 0.05)
	for i in xf:
		var a := float(i) / xf
		s[i] = lerpf(s[n - xf + i], s[i], a)
	return _wav(s, true)


## Einzelner Tropfen, der auf die geschlossene Fensterscheibe trifft. Das kurze
## hochfrequente Knacken plus zwei Glasresonanzen bleibt bewusst leise und sitzt
## je Variante links/rechts im Stereobild. `heavy` fuegt den weicheren Koerper
## eines groesseren Sturm-Tropfens hinzu.
static func rain_glass_impact(pan: float = 0.0, heavy: bool = false) -> AudioStreamWAV:
	var duration := 0.13 if heavy else 0.085
	var n := int(RATE * duration)
	var mono := _n(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x61A55 ^ (0xB017 if heavy else 0) ^ int((pan + 1.0) * 1000.0)
	var smoothed := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		var previous := smoothed
		smoothed = smoothed * 0.72 + white * 0.28
		var bright_noise := white - previous
		var click_env := exp(-t * (72.0 if heavy else 108.0))
		var glass_env := exp(-t * (31.0 if heavy else 43.0))
		var glass := sin(TAU * (1180.0 if heavy else 1760.0) * t) * 0.24
		glass += sin(TAU * (2470.0 if heavy else 3260.0) * t) * 0.11
		var body := sin(TAU * 510.0 * t) * exp(-t * 24.0) * (0.16 if heavy else 0.05)
		mono[i] = (bright_noise * click_env * 0.38 + glass * glass_env + body) * 0.58
	var left := _n(n)
	var right := _n(n)
	var p := clampf(pan, -1.0, 1.0)
	# Equal-Power-Pan: auch ein harter Seitentreffer bleibt auf dem anderen Ohr
	# noch als Raumreflexion vorhanden.
	var left_gain := sqrt(0.5 * (1.0 - p))
	var right_gain := sqrt(0.5 * (1.0 + p))
	for i in n:
		left[i] = mono[i] * left_gain
		right[i] = mono[i] * right_gain
	return _wav_stereo(left, right)


## Donner — tiefes, rollendes Grollen (gefiltertes Rauschen, langsame Hüllkurve).
static func thunder() -> AudioStreamWAV:
	var n := int(RATE * 2.6)
	var s := _n(n)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		# Doppel-Hüllkurve: erster Knall + nachrollendes Grollen
		var env := exp(-pow((t - 0.15) * 6.0, 2.0)) * 0.8 + exp(-t * 1.3) * 0.6
		lp = lp * 0.93 + rng.randf_range(-1.0, 1.0) * 0.07   # tiefes Rumpeln
		s[i] = clampf(lp * env * 3.0, -1.0, 1.0)
	return _wav(s)
