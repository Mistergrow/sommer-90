class_name StefanAnthologySynth
## Prozedurale 4-Kanal-Klangschicht fuer Stefans 27 Diskettenspiele.
## Alle Wellenformen werden beim Start der jeweiligen Diskette erzeugt; es
## werden weder fremde Samples noch MOD-Dateien benoetigt.

const RATE := 22_050
const SynthCore := preload("res://scripts/audio/synth_core.gd")


static func _buffer(seconds: float) -> PackedFloat32Array:
	return SynthCore.buffer(seconds, RATE)


static func _pulse(phase: float, duty := 0.5) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


static func _triangle(phase: float) -> float:
	return 1.0 - 4.0 * absf(fmod(phase + 0.25, 1.0) - 0.5)


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	return SynthCore.to_wav(samples, RATE, loop)


static func _scale(seed_value: int) -> Array[float]:
	var roots: Array[float] = [55.0, 61.74, 65.41, 73.42, 82.41]
	var root := roots[posmod(seed_value, roots.size())]
	return [root, root * 1.125, root * 1.25, root * 1.3333,
		root * 1.5, root * 1.6667, root * 1.875, root * 2.0]


static func title_loop(seed_value: int, difficulty: int) -> AudioStreamWAV:
	var scale := _scale(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var sequence: Array[int] = []
	for i in 16:
		sequence.append(posmod(i * 3 + rng.randi_range(0, 2), scale.size()))
	var bpm := 92.0 + difficulty * 2.0
	var step := 60.0 / bpm / 2.0
	var samples := _buffer(step * sequence.size())
	for i in samples.size():
		var t := float(i) / RATE
		var note_index := mini(sequence.size() - 1, floori(t / step))
		var local := fmod(t, step)
		var lead := scale[sequence[note_index]] * 4.0
		var bass := scale[sequence[note_index] % 4]
		var gate := exp(-local * 6.5)
		var kick := sin(TAU * t * lerpf(95.0, 42.0, minf(1.0, local * 9.0))) \
			* exp(-local * 28.0) * (0.11 if note_index % 4 == 0 else 0.0)
		samples[i] = _pulse(t * lead, 0.22) * 0.075 * gate \
			+ _triangle(t * bass) * 0.17 + kick
	return _wav(samples, true)


static func game_loop(mode: String, seed_value: int, difficulty: int) -> AudioStreamWAV:
	var scale := _scale(seed_value + mode.hash())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 97 + mode.hash()
	var bpm_by_mode := {
		"shooter": 138.0, "platform": 126.0, "circuit": 104.0,
		"miner": 112.0, "rescue": 116.0, "stealth": 96.0,
		"racer": 148.0, "strategy": 102.0, "rhythm": 132.0,
	}
	var bpm := float(bpm_by_mode.get(mode, 120.0)) + difficulty * 1.4
	var step := 60.0 / bpm / 4.0
	var count := 32
	var melody: Array[int] = []
	for i in count:
		melody.append(posmod(i * (3 if mode in ["racer", "shooter"] else 2)
			+ rng.randi_range(0, 2), scale.size()))
	var samples := _buffer(step * count)
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(count - 1, floori(t / step))
		var local := fmod(t, step)
		var note := scale[melody[index]] * (4.0 if mode != "strategy" else 2.0)
		var bass := scale[floori(float(index) / 8.0) % 4]
		var lead_gate := exp(-local * (12.0 if mode in ["racer", "rhythm"] else 7.0))
		var lead := _pulse(t * note, 0.18 + float(index % 3) * 0.05) * 0.075 * lead_gate
		var low := _triangle(t * bass) * (0.16 if index % 2 == 0 else 0.13)
		var kick := sin(TAU * t * lerpf(92.0, 40.0, minf(1.0, local * 10.0))) \
			* exp(-local * 32.0) * (0.13 if index % 4 == 0 else 0.0)
		var hat := rng.randf_range(-1.0, 1.0) * exp(-local * 55.0) \
			* (0.038 if index % 2 == 1 else 0.012)
		samples[i] = lead + low + kick + hat
	return _wav(samples, true)


static func blip(frequency := 660.0, seconds := 0.075) -> AudioStreamWAV:
	var samples := _buffer(seconds)
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] = _pulse(t * frequency, 0.28) * exp(-t * 32.0) * 0.24
	return _wav(samples)


static func sweep(up := true, seconds := 0.2) -> AudioStreamWAV:
	var samples := _buffer(seconds)
	for i in samples.size():
		var t := float(i) / RATE
		var ratio := t / seconds
		var frequency := lerpf(140.0, 1_050.0, ratio if up else 1.0 - ratio)
		samples[i] = (_pulse(t * frequency, 0.23) * 0.14
			+ _triangle(t * frequency * 0.5) * 0.09) * sin(PI * ratio)
	return _wav(samples)


static func noise_hit(seconds := 0.15) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19_910_911
	var samples := _buffer(seconds)
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] = (rng.randf_range(-1.0, 1.0) * 0.19
			+ _pulse(t * 93.0, 0.4) * 0.11) * exp(-t * 18.0)
	return _wav(samples)


static func victory() -> AudioStreamWAV:
	var notes: Array[float] = [392.0, 523.25, 659.25, 783.99, 1_046.5]
	var step := 0.13
	var samples := _buffer(notes.size() * step)
	for i in samples.size():
		var t := float(i) / RATE
		var index := mini(notes.size() - 1, floori(t / step))
		var local := fmod(t, step)
		samples[i] = (_pulse(t * notes[index], 0.28) * 0.17
			+ _triangle(t * notes[index] * 0.5) * 0.1) * exp(-local * 6.0)
	return _wav(samples)
