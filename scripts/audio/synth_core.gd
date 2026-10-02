extends RefCounted
## Gemeinsamer Kern aller prozeduralen Synths (Code Red, Space Lemming,
## Turbo Kart, Stefan-Anthologie, SFX).
##
## Bis zuletzt lag dieselbe 16-Bit-Wandlung fuenfmal kopiert in den einzelnen
## Synths — inklusive Drift: mal `int()` (schneidet ab), mal `roundi()` (rundet
## korrekt). Hier steht sie einmal, mit der korrekt rundenden Variante.
##
## BEWUSST ohne class_name (Pfad-preload, Klassen-Cache-Race — Projektregel).

const DEFAULT_RATE := 22050


## Wandelt Mono-Gleitkomma-Samples (-1..1) in einen 16-Bit-PCM-Stream.
static func to_wav(
		samples: PackedFloat32Array, rate := DEFAULT_RATE, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, roundi(clampf(samples[i], -1.0, 1.0) * 32_767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Stiller Puffer der gewuenschten Laenge; mindestens ein Sample.
static func buffer(seconds: float, rate := DEFAULT_RATE) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(maxi(1, roundi(seconds * rate)))
	return samples
