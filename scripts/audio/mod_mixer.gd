extends RefCounted
## Samplemischer des MOD-Players. Alle Voice-Dictionaries werden in-place
## aktualisiert; ungültige Stimmen werden atomar deaktiviert.


static func mix_frame(channels: Array, samples: Array) -> Vector2:
	var left := 0.0
	var right := 0.0
	for channel_index in channels.size():
		var channel: Dictionary = channels[channel_index]
		if not bool(channel["active"]):
			continue
		var sample_index := int(channel["sidx"])
		if sample_index < 0 or sample_index >= samples.size():
			channel["active"] = false
			continue
		var sample: Dictionary = samples[sample_index]
		var data: PackedByteArray = sample["data"]
		var sample_length := mini(int(sample["len"]), data.size())
		if sample_length <= 0:
			channel["active"] = false
			continue
		var position := maxf(0.0, float(channel["pos"]))
		var loop_start := clampi(int(sample["loop_start"]), 0, sample_length)
		var loop_length := clampi(int(sample["loop_len"]), 0,
			sample_length - loop_start)
		if loop_length > 2:
			var loop_end := loop_start + loop_length
			if position >= loop_end:
				position = float(loop_start) + fposmod(
					position - float(loop_start), float(loop_length))
		elif position >= sample_length:
			channel["active"] = false
			continue
		var data_index := int(position)
		if data_index < 0 or data_index >= data.size():
			channel["active"] = false
			continue
		var byte := int(data[data_index])
		var sample_value := float(byte if byte < 128 else byte - 256) / 128.0
		var amplitude := sample_value * (float(channel["vol"]) / 64.0)
		# Amiga LRRL-Panning, bei 6/8 Kanälen periodisch fortgesetzt.
		if channel_index % 4 == 0 or channel_index % 4 == 3:
			left += amplitude
			right += amplitude * 0.3
		else:
			right += amplitude
			left += amplitude * 0.3
		channel["pos"] = position + float(channel["step"])
	var gain := 0.4 * sqrt(4.0 / maxf(4.0, float(channels.size())))
	return Vector2(clampf(left * gain, -1.0, 1.0),
		clampf(right * gain, -1.0, 1.0))


## Mischt `count` Frames ab `start` in `buf`. Zwischen zwei Sequencer-Ticks
## aendern sich Sample, Lautstaerke und Schrittweite eines Kanals nicht; darum
## wird der Kanalzustand einmal gelesen und die Frames in einer engen Schleife
## ohne Dictionary-Zugriffe gemischt. Summationsreihenfolge (Kanal 0..n je
## Frame, 64-bit-Zwischensummen) entspricht exakt mix_frame(): bitgleiches PCM.
static func mix_block(channels: Array, samples: Array, buf: PackedVector2Array,
		start: int, count: int) -> void:
	var left := PackedFloat64Array()
	var right := PackedFloat64Array()
	left.resize(count)
	right.resize(count)
	left.fill(0.0)
	right.fill(0.0)
	for channel_index in channels.size():
		var channel: Dictionary = channels[channel_index]
		if not bool(channel["active"]):
			continue
		var sample_index := int(channel["sidx"])
		if sample_index < 0 or sample_index >= samples.size():
			channel["active"] = false
			continue
		var sample: Dictionary = samples[sample_index]
		var data: PackedByteArray = sample["data"]
		var data_size := data.size()
		var sample_length := mini(int(sample["len"]), data_size)
		if sample_length <= 0:
			channel["active"] = false
			continue
		var loop_start := clampi(int(sample["loop_start"]), 0, sample_length)
		var loop_length := clampi(int(sample["loop_len"]), 0, sample_length - loop_start)
		var looped := loop_length > 2
		var loop_end := loop_start + loop_length
		var level := float(channel["vol"]) / 64.0
		var step := float(channel["step"])
		var on_left := channel_index % 4 == 0 or channel_index % 4 == 3
		var position := float(channel["pos"])
		var stopped := false
		for f in count:
			position = maxf(0.0, position)
			if looped:
				if position >= loop_end:
					position = float(loop_start) + fposmod(position - float(loop_start), float(loop_length))
			elif position >= sample_length:
				stopped = true
				break
			var data_index := int(position)
			if data_index < 0 or data_index >= data_size:
				stopped = true
				break
			var byte := int(data[data_index])
			var amplitude := float(byte if byte < 128 else byte - 256) / 128.0 * level
			if on_left:
				left[f] += amplitude
				right[f] += amplitude * 0.3
			else:
				right[f] += amplitude
				left[f] += amplitude * 0.3
			position = position + step
		if stopped:
			channel["active"] = false
		else:
			channel["pos"] = position
	var gain := 0.4 * sqrt(4.0 / maxf(4.0, float(channels.size())))
	for f in count:
		buf[start + f] = Vector2(clampf(left[f] * gain, -1.0, 1.0), clampf(right[f] * gain, -1.0, 1.0))
