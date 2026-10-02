class_name TurboKartSynth
## Originale, prozedurale Vierkanal-Klangwelt fuer Turbo Kart Deluxe.
## Absichtlich rau: 8-bit-artige Wellenformen, 22050 Hz, mono und kurze Loops.
## Es werden keine fremden MODs oder Samples ausgeliefert.

const RATE := 22050
const SynthCore := preload("res://scripts/audio/synth_core.gd")


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	return SynthCore.to_wav(samples, RATE, loop)


static func _buffer(seconds: float) -> PackedFloat32Array:
	return SynthCore.buffer(seconds, RATE)


static func _square(phase: float, duty := 0.5) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


static func _triangle(phase: float) -> float:
	return 1.0 - 4.0 * abs(fmod(phase + 0.25, 1.0) - 0.5)


static func title_loop() -> AudioStreamWAV:
	# Acht 1/8-Noten bei 112 BPM; der Loop schliesst samplegenau.
	var step := 60.0 / 112.0 / 2.0
	var seconds := step * 8.0
	var samples := _buffer(seconds)
	var arp := [220.0, 277.18, 329.63, 277.18, 196.0, 246.94, 293.66, 246.94]
	var bass := [55.0, 55.0, 49.0, 49.0, 65.41, 65.41, 49.0, 49.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990112
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(7, int(t / step))
		var local := fmod(t, step)
		var gate := minf(1.0, (step - local) * 16.0)
		var lead := _square(t * float(arp[index]), 0.28) * 0.18 * gate
		var low := _triangle(t * float(bass[index])) * 0.22
		var chord := _square(t * float(arp[index]) * 0.5, 0.5) * 0.07
		var tick := rng.randf_range(-1.0, 1.0) * exp(-local * 70.0) * 0.07
		samples[i] = clampf(lead + low + chord + tick, -0.82, 0.82)
	return _wav(samples, true)


static func race_loop() -> AudioStreamWAV:
	# Treibendes 16-Step-Pattern bei 138 BPM, drei Musikstimmen plus Noise-Hat.
	var step := 60.0 / 138.0 / 4.0
	var seconds := step * 16.0
	var samples := _buffer(seconds)
	var lead := [329.63, 392.0, 440.0, 392.0, 293.66, 349.23, 392.0, 349.23,
		329.63, 392.0, 493.88, 440.0, 293.66, 349.23, 392.0, 261.63]
	var bass := [82.41, 82.41, 73.42, 73.42, 98.0, 98.0, 73.42, 73.42,
		82.41, 82.41, 65.41, 65.41, 73.42, 73.42, 98.0, 98.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990138
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(15, int(t / step))
		var local := fmod(t, step)
		var env := exp(-local * 12.0)
		var pulse := _square(t * float(lead[index]), 0.22) * 0.13 * env
		var low := _triangle(t * float(bass[index])) * 0.25
		var offbeat := _square(t * float(lead[index]) * 0.5, 0.42) * 0.055
		var hat := rng.randf_range(-1.0, 1.0) * exp(-local * 55.0) * (0.08 if index % 2 else 0.04)
		samples[i] = clampf(pulse + low + offbeat + hat, -0.86, 0.86)
	return _wav(samples, true)


static func engine_loop() -> AudioStreamWAV:
	var seconds := 0.2
	var samples := _buffer(seconds)
	for i in samples.size():
		var t := float(i) / RATE
		var motor := _square(t * 72.0, 0.38) * 0.16
		motor += _triangle(t * 144.0) * 0.11
		motor += sin(TAU * 36.0 * t) * 0.07
		samples[i] = motor
	return _wav(samples, true)


static func countdown(high := false) -> AudioStreamWAV:
	var samples := _buffer(0.12)
	var frequency := 1046.5 if high else 523.25
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] = _square(t * frequency, 0.5) * exp(-t * 24.0) * 0.28
	return _wav(samples)


static func boost() -> AudioStreamWAV:
	var samples := _buffer(0.26)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4096
	for i in samples.size():
		var t := float(i) / RATE
		var frequency := lerpf(150.0, 760.0, t / 0.26)
		var tone := _square(t * frequency, 0.32) * 0.20
		var hiss := rng.randf_range(-1.0, 1.0) * 0.08
		samples[i] = (tone + hiss) * sin(PI * t / 0.26)
	return _wav(samples)


static func impact() -> AudioStreamWAV:
	var samples := _buffer(0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for i in samples.size():
		var t := float(i) / RATE
		var env := exp(-t * 24.0)
		samples[i] = (rng.randf_range(-1.0, 1.0) * 0.45 + sin(TAU * 88.0 * t) * 0.35) * env
	return _wav(samples)


static func skid() -> AudioStreamWAV:
	var samples := _buffer(0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var previous := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		previous = previous * 0.45 + noise * 0.55
		samples[i] = (noise - previous * 0.35) * sin(PI * t / 0.3) * 0.24
	return _wav(samples)


static func finish() -> AudioStreamWAV:
	var samples := _buffer(0.72)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var note_len := 0.18
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(3, int(t / note_len))
		var local := fmod(t, note_len)
		samples[i] = (_square(t * float(notes[index]), 0.35) * 0.18 + _triangle(t * float(notes[index]) * 0.5) * 0.12) * exp(-local * 8.0)
	return _wav(samples)
