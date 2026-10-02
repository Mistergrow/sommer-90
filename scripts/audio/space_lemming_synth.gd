class_name SpaceLemmingSynth
## Originale prozedurale Vierkanal-Klangwelt: keine Samples, keine MOD-Datei.
## Puls, Dreieck und deterministisches Noise werden beim Start in RAM erzeugt.

const RATE := 22050
const SynthCore := preload("res://scripts/audio/synth_core.gd")


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	return SynthCore.to_wav(samples, RATE, loop)


static func _buffer(seconds: float) -> PackedFloat32Array:
	return SynthCore.buffer(seconds, RATE)


static func _pulse(phase: float, duty := 0.5) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


static func _triangle(phase: float) -> float:
	return 1.0 - 4.0 * abs(fmod(phase + 0.25, 1.0) - 0.5)


static func title_loop() -> AudioStreamWAV:
	var step := 60.0 / 104.0 / 2.0
	var notes := [220.0, 329.63, 277.18, 415.30, 246.94, 369.99, 277.18, 329.63]
	var bass := [55.0, 55.0, 69.30, 69.30, 61.74, 61.74, 73.42, 73.42]
	var samples := _buffer(step * notes.size())
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(notes.size() - 1, int(t / step))
		var local := fmod(t, step)
		var gate := exp(-local * 5.5)
		samples[i] = _pulse(t * notes[index], 0.23) * 0.11 * gate \
			+ _triangle(t * bass[index]) * 0.20 \
			+ _pulse(t * notes[index] * 0.5, 0.45) * 0.045
	return _wav(samples, true)


static func mission_loop() -> AudioStreamWAV:
	var step := 60.0 / 126.0 / 4.0
	var notes := [329.63, 0.0, 392.0, 0.0, 440.0, 392.0, 329.63, 0.0,
		293.66, 0.0, 349.23, 0.0, 392.0, 349.23, 293.66, 246.94]
	var bass := [82.41, 82.41, 73.42, 73.42, 65.41, 65.41, 73.42, 73.42,
		82.41, 82.41, 98.0, 98.0, 73.42, 73.42, 61.74, 61.74]
	var samples := _buffer(step * notes.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 1992_042
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(notes.size() - 1, int(t / step))
		var local := fmod(t, step)
		var lead := 0.0 if notes[index] <= 0.0 else _pulse(t * notes[index], 0.18) * exp(-local * 12.0) * 0.10
		var low := _triangle(t * bass[index]) * 0.19
		var hat := rng.randf_range(-1.0, 1.0) * exp(-local * 48.0) * (0.055 if index % 2 else 0.025)
		samples[i] = lead + low + hat
	return _wav(samples, true)


static func blip(frequency := 660.0, seconds := 0.08) -> AudioStreamWAV:
	var samples := _buffer(seconds)
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] = _pulse(t * frequency, 0.3) * exp(-t * 28.0) * 0.26
	return _wav(samples)


static func launch() -> AudioStreamWAV:
	var samples := _buffer(0.28)
	for i in samples.size():
		var t := float(i) / RATE
		var frequency := lerpf(110.0, 880.0, t / 0.28)
		samples[i] = (_pulse(t * frequency, 0.28) * 0.15 + _triangle(t * frequency * 0.5) * 0.12) * sin(PI * t / 0.28)
	return _wav(samples)


static func lost() -> AudioStreamWAV:
	var samples := _buffer(0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in samples.size():
		var t := float(i) / RATE
		var frequency := lerpf(330.0, 55.0, t / 0.25)
		samples[i] = (_pulse(t * frequency, 0.4) * 0.2 + rng.randf_range(-1.0, 1.0) * 0.11) * exp(-t * 7.0)
	return _wav(samples)


static func victory() -> AudioStreamWAV:
	var notes := [392.0, 523.25, 659.25, 783.99]
	var length := 0.16
	var samples := _buffer(notes.size() * length)
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(notes.size() - 1, int(t / length))
		var local := fmod(t, length)
		samples[i] = (_pulse(t * notes[index], 0.3) * 0.18 + _triangle(t * notes[index] * 0.5) * 0.12) * exp(-local * 7.0)
	return _wav(samples)
