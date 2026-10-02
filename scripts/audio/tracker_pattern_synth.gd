class_name TrackerPatternSynth
extends RefCounted
## Kleine Paula-inspirierte Klangbank fuer das Tracker-Labor. Alle Instrumente
## werden reproduzierbar als 16-Bit-PCM erzeugt: kein fehlendes Asset kann das
## Pattern stumm machen. Die vier Kanaele liegen wie beim Amiga leicht getrennt
## im Stereobild; Varianten und FX veraendern den Klang wirklich hoerbar.

const RATE := 22050


static func make_hit(track: int, sample_name: StringName, effect: int, step: int) -> AudioStreamWAV:
	if track < 0 or track > 3:
		return null
	var fx := clampi(effect, 0, 3)
	var mono: PackedFloat32Array
	match track:
		0:
			mono = _kick(sample_name, fx)
		1:
			mono = _snare(sample_name, fx)
		2:
			mono = _hat(sample_name, fx)
		3:
			mono = _bass(sample_name, fx, step)
	if mono.is_empty():
		return null
	if fx == 3:
		_apply_echo(mono, 0.075, 0.28)
	var pan := [-0.34, 0.34, 0.58, -0.58][track] as float
	return _stereo_wav(mono, pan)


static func _empty(seconds: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(maxi(1, roundi(float(RATE) * seconds)))
	return result


static func _kick(sample_name: StringName, effect: int) -> PackedFloat32Array:
	var duration := 0.34 if sample_name == &"bd_deep" else 0.25
	var samples := _empty(duration)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBD1990 + int(effect) * 31 + int(sample_name == &"bd_click") * 7
	var start_hz := 116.0
	var end_hz := 43.0
	var decay := 14.0
	if sample_name == &"bd_deep":
		start_hz = 92.0
		end_hz = 35.0
		decay = 10.0
	elif sample_name == &"bd_click":
		start_hz = 154.0
		end_hz = 49.0
		decay = 18.0
	for i in samples.size():
		var t := float(i) / float(RATE)
		var sweep := exp(-t * (18.0 if effect != 2 else 11.0))
		var frequency := end_hz + (start_hz - end_hz) * sweep
		phase += TAU * frequency / float(RATE)
		var body := sin(phase) * exp(-t * decay) * 0.78
		var sub := sin(phase * 0.5) * exp(-t * (decay * 0.74)) * 0.16
		var click_amount := 0.25 if sample_name == &"bd_click" else 0.11
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 115.0) * click_amount
		var accent := 1.16 if effect == 1 else 1.0
		samples[i] = (body + sub + click) * accent * 0.78
	return samples


static func _snare(sample_name: StringName, effect: int) -> PackedFloat32Array:
	var duration := 0.31 if sample_name == &"sd_clap" else (0.16 if sample_name == &"sd_tight" else 0.24)
	var samples := _empty(duration)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5D1991 + int(effect) * 43 + int(sample_name == &"sd_clap") * 101
	var lowpass := 0.0
	for i in samples.size():
		var t := float(i) / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		lowpass = lowpass * 0.68 + white * 0.32
		var bright := white - lowpass * 0.78
		var envelope := exp(-t * (25.0 if sample_name == &"sd_tight" else 15.0))
		if sample_name == &"sd_clap":
			envelope = 0.0
			for burst in [0.0, 0.027, 0.054]:
				var local_t := t - float(burst)
				if local_t >= 0.0:
					envelope += exp(-local_t * 27.0) * (1.0 if burst == 0.0 else 0.72)
		var body := sin(TAU * (178.0 if sample_name != &"sd_tight" else 214.0) * t) * exp(-t * 18.0)
		var accent := 1.15 if effect == 1 else 1.0
		samples[i] = (bright * envelope * 0.48 + body * 0.22) * accent * 0.72
	return samples


static func _hat(sample_name: StringName, effect: int) -> PackedFloat32Array:
	var duration := 0.34 if sample_name == &"hh_open" else (0.15 if sample_name == &"hh_metal" else 0.09)
	var samples := _empty(duration)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x441992 + int(effect) * 59 + int(sample_name == &"hh_open") * 83
	var lowpass := 0.0
	for i in samples.size():
		var t := float(i) / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		lowpass = lowpass * 0.82 + white * 0.18
		var high := white - lowpass
		var metallic := sin(TAU * 4311.0 * t) * sin(TAU * 6397.0 * t)
		if sample_name == &"hh_metal":
			metallic += sin(TAU * 2783.0 * t) * 0.46
		var decay := 10.0 if sample_name == &"hh_open" else (28.0 if sample_name == &"hh_metal" else 48.0)
		var envelope := exp(-t * decay)
		var accent := 1.18 if effect == 1 else 1.0
		samples[i] = (high * 0.34 + metallic * 0.18) * envelope * accent * 0.72
	return samples


static func _bass(sample_name: StringName, effect: int, step: int) -> PackedFloat32Array:
	var samples := _empty(0.31)
	var notes := [55.0, 65.41, 73.42, 82.41, 98.0, 82.41, 73.42, 65.41]
	var base_frequency := float(notes[posmod(step, notes.size())])
	var phase := 0.0
	var previous := 0.0
	for i in samples.size():
		var t := float(i) / float(RATE)
		var pitch_sweep := 1.0 + (0.42 * exp(-t * 14.0) if effect == 2 else 0.0)
		phase = fmod(phase + base_frequency * pitch_sweep / float(RATE), 1.0)
		var oscillator: float
		if sample_name == &"bass_saw":
			oscillator = phase * 2.0 - 1.0
		elif sample_name == &"bass_pulse":
			oscillator = 1.0 if phase < 0.24 else -1.0
		else:
			oscillator = 1.0 if phase < 0.5 else -1.0
		# Ein sehr einfacher Tiefpass nimmt der Rechteckwelle die digitale Schaerfe,
		# ohne den charakteristischen 8-Bit-/Amiga-Koerper zu verlieren.
		previous = previous * 0.76 + oscillator * 0.24
		var attack := clampf(t / 0.008, 0.0, 1.0)
		var envelope := attack * exp(-t * (5.8 if effect == 3 else 7.4))
		var accent := 1.14 if effect == 1 else 1.0
		samples[i] = previous * envelope * accent * 0.54
	return samples


static func _apply_echo(samples: PackedFloat32Array, delay_seconds: float, amount: float) -> void:
	var delay := maxi(1, roundi(delay_seconds * float(RATE)))
	for i in range(delay, samples.size()):
		samples[i] = clampf(samples[i] + samples[i - delay] * amount, -1.0, 1.0)


static func _stereo_wav(mono: PackedFloat32Array, pan: float) -> AudioStreamWAV:
	var clamped_pan := clampf(pan, -1.0, 1.0)
	var left_gain := sqrt(0.5 * (1.0 - clamped_pan))
	var right_gain := sqrt(0.5 * (1.0 + clamped_pan))
	var bytes := PackedByteArray()
	bytes.resize(mono.size() * 4)
	for i in mono.size():
		var value := clampf(mono[i], -0.96, 0.96)
		bytes.encode_s16(i * 4, clampi(roundi(value * left_gain * 32767.0), -32767, 32767))
		bytes.encode_s16(i * 4 + 2, clampi(roundi(value * right_gain * 32767.0), -32767, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = bytes
	return wav
