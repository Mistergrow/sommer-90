extends RefCounted
## Zustandslose ProTracker-Sequencerregeln. ModPlayer behält kompatible Adapter,
## während Kanalgrundzustand, Sprungauflösung und Zyklusschlüssel hier liegen.


static func new_channel() -> Dictionary:
	return {
		"sidx": 0, "period": 0, "target": 0, "vol": 0,
		"pos": 0.0, "step": 0.0, "eff": 0, "param": 0, "active": false,
		"vibr_pos": 0, "porta_up": 0, "porta_down": 0, "tone_porta": 0,
		"vibr_speed": 0, "vibr_depth": 0, "vol_slide": 0,
		"sample_offset": 0, "loop_row": 0, "loop_count": 0,
		"delayed_period": 0, "delayed_offset": 0,
	}


static func order_transition(current_order: int, order_jump: int,
		pattern_break: int, skip_break_target: bool) -> Dictionary:
	var target_order := order_jump if order_jump >= 0 else current_order + 1
	var target_row := clampi(pattern_break, 0, 63) if pattern_break >= 0 else 0
	if skip_break_target and pattern_break >= 0:
		target_row += 1
	if target_row >= 64:
		target_row = 0
		target_order += 1
	return {"order": target_order, "row": target_row}


static func flow_state_key(order: int, row: int, speed: int, bpm: int,
		channels: Array) -> String:
	var parts: Array[String] = [str(order), str(row), str(speed), str(bpm)]
	for channel: Dictionary in channels:
		parts.append(str(int(channel["loop_row"])))
		parts.append(str(int(channel["loop_count"])))
	return ":".join(parts)
