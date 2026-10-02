class_name CodeRedSynth
## Prozeduraler Vierkanal-Sound im Stil spaeter Amiga-Strategiespiele.
## Alle Wellenformen werden deterministisch im RAM erzeugt; keine Fremdsamples.

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


static func operation_loop(intensity: int) -> AudioStreamWAV:
	var level := clampi(intensity, 0, 3)
	var tempos: Array[float] = [76.0, 88.0, 104.0, 122.0]
	var tempo: float = tempos[level]
	var step: float = 60.0 / tempo / 2.0
	var roots: Array[float] = [55.0, 65.41, 49.0, 58.27, 55.0, 73.42, 49.0, 43.65]
	var lead_notes: Array[float] = [220.0, 0.0, 261.63, 0.0, 233.08, 220.0, 174.61, 0.0]
	var samples := _buffer(step * roots.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 620_034 + level * 771
	for i in samples.size():
		var t := i / float(RATE)
		var index := mini(roots.size() - 1, int(t / step))
		var local := fmod(t, step)
		var low := _triangle(t * roots[index]) * (0.17 + level * 0.012)
		var lead := 0.0
		if lead_notes[index] > 0.0:
			lead = _pulse(t * lead_notes[index], 0.18) * exp(-local * 7.0) * (0.04 + level * 0.018)
		var clock := _pulse(t * (tempo / 60.0) * 4.0, 0.08) * exp(-fmod(t, step) * 36.0) * 0.025
		var noise := 0.0
		if level >= 2:
			noise = rng.randf_range(-1.0, 1.0) * exp(-local * 42.0) * (0.018 + level * 0.009)
		samples[i] = low + lead + clock + noise
	return _wav(samples, true)


static func blip(frequency := 620.0, seconds := 0.07) -> AudioStreamWAV:
	var samples := _buffer(seconds)
	for i in samples.size():
		var t := i / float(RATE)
		samples[i] = _pulse(t * frequency, 0.26) * exp(-t * 30.0) * 0.23
	return _wav(samples)


static func alarm() -> AudioStreamWAV:
	var samples := _buffer(0.42)
	for i in samples.size():
		var t := i / float(RATE)
		var frequency := 135.0 if fmod(t, 0.18) < 0.09 else 185.0
		samples[i] = (_pulse(t * frequency, 0.45) * 0.18 + _triangle(t * 67.5) * 0.08) * sin(PI * t / 0.42)
	return _wav(samples)


static func confirm() -> AudioStreamWAV:
	var samples := _buffer(0.18)
	for i in samples.size():
		var t := i / float(RATE)
		var frequency := 330.0 if t < 0.09 else 495.0
		samples[i] = _pulse(t * frequency, 0.3) * exp(-fmod(t, 0.09) * 18.0) * 0.2
	return _wav(samples)


static func failure() -> AudioStreamWAV:
	var samples := _buffer(0.34)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2034
	for i in samples.size():
		var t := i / float(RATE)
		var frequency := lerpf(240.0, 42.0, t / 0.34)
		samples[i] = (_pulse(t * frequency, 0.4) * 0.17 + rng.randf_range(-1.0, 1.0) * 0.08) * exp(-t * 5.2)
	return _wav(samples)


# ------------------------------------------------------------ AAA-Ausbau
# Die Konsole klang bis hier aus fuenf Signalen. Ein Amiga-Strategiespiel
# dieser Klasse quittierte dagegen jede Ebene eigenstaendig: Tastendruck,
# Bildwechsel, verbrauchter Befehl, Messwertlauf, Eskalationsstufe. Alles
# bleibt deterministisch und vierstimmig denkbar — keine Fremdsamples.


## Trockener Tastentick fuer die Menuenavigation. Kuerzer und stumpfer als
## blip(), damit schnelles Durchsteppen nicht klingelt.
static func key_click() -> AudioStreamWAV:
	var samples := _buffer(0.035)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1084
	for i in samples.size():
		var t := i / float(RATE)
		samples[i] = (_pulse(t * 1480.0, 0.12) * 0.10
			+ rng.randf_range(-1.0, 1.0) * 0.05) * exp(-t * 130.0)
	return _wav(samples)


## Copper-Sweep beim Bildwechsel: ein durchlaufender Ton, wie ihn die
## Rasterzeilenverlaeufe dieser Aera akustisch begleiteten.
static func screen_sweep(rising := true) -> AudioStreamWAV:
	var seconds := 0.16
	var samples := _buffer(seconds)
	for i in samples.size():
		var t := i / float(RATE)
		var ratio := t / seconds
		var frequency := lerpf(300.0, 900.0, ratio) if rising \
			else lerpf(900.0, 300.0, ratio)
		samples[i] = (_pulse(t * frequency, 0.2) * 0.09
			+ _triangle(t * frequency * 0.5) * 0.05) * sin(PI * ratio)
	return _wav(samples)


## Ein verbrauchter Befehl. Schwerer Quittungsschlag mit kurzem Nachhall im
## Rauschkanal — der Spieler soll die Endlichkeit der Befehle hoeren.
static func command_spend() -> AudioStreamWAV:
	var samples := _buffer(0.26)
	var rng := RandomNumberGenerator.new()
	rng.seed = 620_034
	for i in samples.size():
		var t := i / float(RATE)
		var body := _triangle(t * lerpf(196.0, 98.0, clampf(t / 0.26, 0.0, 1.0))) * 0.20
		var click := _pulse(t * 880.0, 0.15) * exp(-t * 90.0) * 0.12
		var tail := rng.randf_range(-1.0, 1.0) * exp(-t * 14.0) * 0.05
		samples[i] = (body + click + tail) * exp(-t * 6.0)
	return _wav(samples)


## Dreistufiger Alarm. Stufe 0 mahnt, Stufe 2 ist der Z-Pinch-Notfall.
static func alarm_level(stage: int) -> AudioStreamWAV:
	var level := clampi(stage, 0, 2)
	var seconds: float = [0.34, 0.42, 0.62][level]
	var low: float = [150.0, 135.0, 116.0][level]
	var high: float = [196.0, 185.0, 233.0][level]
	var period: float = [0.14, 0.09, 0.055][level]
	var gain: float = [0.13, 0.18, 0.24][level]
	var samples := _buffer(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2034 + level * 97
	for i in samples.size():
		var t := i / float(RATE)
		var frequency := low if fmod(t, period * 2.0) < period else high
		var grit := 0.0
		if level >= 2:
			grit = rng.randf_range(-1.0, 1.0) * 0.05
		samples[i] = (_pulse(t * frequency, 0.45) * gain
			+ _triangle(t * low * 0.5) * gain * 0.44 + grit) * sin(PI * t / seconds)
	return _wav(samples)


## Messwertlauf: kurze aufsteigende Tonfolge, wenn eine Anzeige neu einliest.
static func data_readout() -> AudioStreamWAV:
	var steps: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	var step_time := 0.032
	var samples := _buffer(step_time * float(steps.size()))
	for i in samples.size():
		var t := i / float(RATE)
		var index := mini(steps.size() - 1, int(t / step_time))
		var local := fmod(t, step_time)
		samples[i] = _pulse(t * steps[index], 0.22) * exp(-local * 46.0) * 0.13
	return _wav(samples)


## Regionwechsel auf der Weltkarte — zwei weiche Toene, kein Klingeln.
static func region_select() -> AudioStreamWAV:
	var samples := _buffer(0.13)
	for i in samples.size():
		var t := i / float(RATE)
		var frequency := 392.0 if t < 0.055 else 523.25
		samples[i] = _triangle(t * frequency) * exp(-fmod(t, 0.055) * 20.0) * 0.16
	return _wav(samples)


## Doktrin gewaehlt: ein gehaltener Dreiklang. Der einzige Moment im Spiel,
## in dem drei Stimmen zugleich stehen — die Entscheidung wiegt.
static func doctrine_chosen() -> AudioStreamWAV:
	var seconds := 0.72
	var samples := _buffer(seconds)
	var chord: Array[float] = [146.83, 220.0, 293.66]
	for i in samples.size():
		var t := i / float(RATE)
		var value := 0.0
		for note: float in chord:
			value += _triangle(t * note) * 0.075
		var swell := minf(1.0, t / 0.09) * exp(-maxf(0.0, t - 0.24) * 3.4)
		samples[i] = value * swell
	return _wav(samples)


## Plasmastoss der Himmelsereignisse: tiefes Grollen mit Entladungsspitze.
static func plasma_surge() -> AudioStreamWAV:
	var seconds := 0.85
	var samples := _buffer(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962
	for i in samples.size():
		var t := i / float(RATE)
		var ratio := t / seconds
		var rumble := _triangle(t * lerpf(38.0, 64.0, ratio)) * 0.20
		var crackle := rng.randf_range(-1.0, 1.0) * 0.10 \
			* exp(-absf(ratio - 0.34) * 14.0)
		samples[i] = (rumble + crackle) * minf(1.0, t / 0.12) * exp(-maxf(0.0, t - 0.4) * 3.0)
	return _wav(samples)


## Bootzeichen der Diskette, bevor der Titel steht.
static func boot_chime() -> AudioStreamWAV:
	var samples := _buffer(0.5)
	var notes: Array[float] = [261.63, 349.23, 523.25]
	for i in samples.size():
		var t := i / float(RATE)
		var index := mini(notes.size() - 1, int(t / 0.11))
		var local := fmod(t, 0.11)
		samples[i] = (_triangle(t * notes[index]) * 0.15
			+ _pulse(t * notes[index] * 2.0, 0.14) * 0.04) * exp(-local * 9.0)
	return _wav(samples)


## Schlussmotive. "victory" loest auf, "mixed" bleibt offen, "chaos" faellt.
static func ending_motif(kind: String) -> AudioStreamWAV:
	var progressions := {
		"victory": [174.61, 220.0, 261.63, 349.23],
		"mixed": [196.0, 233.08, 261.63, 233.08],
		"chaos": [220.0, 174.61, 146.83, 110.0],
	}
	var notes: Array = progressions.get(kind, progressions["mixed"])
	var step := 0.34
	var samples := _buffer(step * float(notes.size()))
	var falling := kind == "chaos"
	for i in samples.size():
		var t := i / float(RATE)
		var index := mini(notes.size() - 1, int(t / step))
		var local := fmod(t, step)
		var base := float(notes[index])
		var value := _triangle(t * base) * 0.16 + _triangle(t * base * 2.0) * 0.05
		if falling:
			value += _pulse(t * base * 0.5, 0.3) * 0.05
		samples[i] = value * minf(1.0, local / 0.04) * exp(-local * 2.6)
	return _wav(samples)
