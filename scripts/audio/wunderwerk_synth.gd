class_name WunderwerkSynth
## Originale prozedurale Vierkanal-Klangwelt fuer WUNDERWERK '94.
## Keine Fremdsamples: Puls, Dreieck und deterministisches Noise entstehen im RAM.

const RATE := 22050
const SynthCore := preload("res://scripts/audio/synth_core.gd")


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	return SynthCore.to_wav(samples, RATE, loop)


static func _buffer(seconds: float) -> PackedFloat32Array:
	return SynthCore.buffer(seconds, RATE)


static func _pulse(phase: float, duty := 0.5) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


static func _triangle(phase: float) -> float:
	return 1.0 - 4.0 * absf(fmod(phase + 0.25, 1.0) - 0.5)


static func title_loop() -> AudioStreamWAV:
	var step := 60.0 / 118.0 / 2.0
	var melody := [392.0, 493.88, 587.33, 659.25, 587.33, 493.88, 440.0, 523.25,
		659.25, 783.99, 659.25, 587.33, 523.25, 440.0, 392.0, 329.63]
	var bass := [98.0, 98.0, 110.0, 110.0, 82.41, 82.41, 98.0, 98.0,
		87.31, 87.31, 110.0, 110.0, 98.0, 98.0, 73.42, 73.42]
	var samples := _buffer(step * melody.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 199_494
	for index in samples.size():
		var t := float(index) / RATE
		var note := mini(melody.size() - 1, int(t / step))
		var local := fmod(t, step)
		var lead := _pulse(t * melody[note], 0.24) * exp(-local * 8.0) * 0.12
		var low := _triangle(t * bass[note]) * 0.19
		var chord := _pulse(t * melody[note] * 0.5, 0.48) * 0.045
		var hat := rng.randf_range(-1.0, 1.0) * exp(-local * 55.0) * 0.035
		samples[index] = clampf(lead + low + chord + hat, -0.82, 0.82)
	return _wav(samples, true)


static func park_loop() -> AudioStreamWAV:
	var step := 60.0 / 126.0 / 4.0
	var melody := [523.25, 0.0, 659.25, 0.0, 587.33, 659.25, 783.99, 0.0,
		493.88, 0.0, 587.33, 0.0, 659.25, 587.33, 523.25, 0.0]
	var bass := [65.41, 65.41, 82.41, 82.41, 73.42, 73.42, 98.0, 98.0,
		61.74, 61.74, 73.42, 73.42, 82.41, 82.41, 65.41, 65.41]
	var samples := _buffer(step * melody.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 126_1994
	for index in samples.size():
		var t := float(index) / RATE
		var note := mini(melody.size() - 1, int(t / step))
		var local := fmod(t, step)
		var lead := 0.0 if melody[note] <= 0.0 else (
			_pulse(t * melody[note], 0.18) * exp(-local * 13.0) * 0.10)
		var low := _triangle(t * bass[note]) * 0.20
		var organ := _pulse(t * bass[note] * 2.0, 0.48) * 0.045
		var hat := rng.randf_range(-1.0, 1.0) * exp(-local * 60.0) \
			* (0.055 if note % 2 else 0.025)
		samples[index] = clampf(lead + low + organ + hat, -0.80, 0.80)
	return _wav(samples, true)


static func blip(frequency := 720.0, seconds := 0.07) -> AudioStreamWAV:
	var samples := _buffer(seconds)
	for index in samples.size():
		var t := float(index) / RATE
		samples[index] = _pulse(t * frequency, 0.25) * exp(-t * 34.0) * 0.22
	return _wav(samples)


static func build() -> AudioStreamWAV:
	var samples := _buffer(0.18)
	var notes := [392.0, 523.25, 659.25]
	for index in samples.size():
		var t := float(index) / RATE
		var note := mini(2, int(t / 0.06))
		var local := fmod(t, 0.06)
		samples[index] = (_pulse(t * notes[note], 0.3) * 0.17
			+ _triangle(t * notes[note] * 0.5) * 0.10) * exp(-local * 17.0)
	return _wav(samples)


static func cash() -> AudioStreamWAV:
	var samples := _buffer(0.12)
	for index in samples.size():
		var t := float(index) / RATE
		var frequency := 880.0 if t < 0.06 else 1174.66
		samples[index] = _pulse(t * frequency, 0.18) * exp(-fmod(t, 0.06) * 28.0) * 0.18
	return _wav(samples)


static func alarm() -> AudioStreamWAV:
	var samples := _buffer(0.32)
	for index in samples.size():
		var t := float(index) / RATE
		var wobble := 170.0 + sin(t * TAU * 7.0) * 22.0
		samples[index] = _pulse(t * wobble, 0.5) * sin(PI * t / 0.32) * 0.23
	return _wav(samples)


static func cheer() -> AudioStreamWAV:
	var samples := _buffer(0.34)
	var rng := RandomNumberGenerator.new()
	rng.seed = 94_777
	for index in samples.size():
		var t := float(index) / RATE
		var voice := sin(TAU * (420.0 + t * 620.0) * t) * 0.12
		var crowd := rng.randf_range(-1.0, 1.0) * 0.10
		samples[index] = (voice + crowd) * sin(PI * t / 0.34)
	return _wav(samples)
