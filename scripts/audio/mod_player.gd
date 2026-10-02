class_name ModPlayer
extends Node
## Nativer ProTracker-/FastTracker-.mod-Replayer (4/6/8 Kanaele) in reinem GDScript.
## Liest die Rohbytes einer .mod-Datei und synthetisiert das Stück live in einen
## AudioStreamGenerator — keine Konvertierung, keine Fremdbibliothek. Genau die
## Technik der Amiga-Ära, in der das Spiel steckt.
##
## Umgesetzt: 31 Samples inkl. Loops/Finetune, Pattern-Sequencer mit Tempo/
## Speed und die gebräuchlichen Effekte (Arpeggio, Porta, Vibrato, Volumeslide,
## Set-Volume, Pattern-Break, Position-Jump, Speed/Tempo). Die Ablaufsteuerung
## bildet zusätzlich reale ProTracker-Kompatibilitätsfälle ab: F00 ist kein
## Songende, rückwärts gerichtete Bxx-Loops markieren bei Einzelwiedergabe das
## Ende eines Durchlaufs und alte SoundTracker-2.3-Module verwenden Dxx ohne
## Zielzeile.

signal finished

const MIX_RATE := 22050.0
const PAL_CLOCK := 3546895.0   # rate_hz = PAL_CLOCK / period (Amiga PAL)
const MIN_PERIOD := 113
const MAX_PERIOD := 856
const Parser := preload("res://scripts/audio/mod_parser.gd")
const Mixer := preload("res://scripts/audio/mod_mixer.gd")
const Sequencer := preload("res://scripts/audio/mod_sequencer.gd")
const PlaybackView := preload("res://scripts/audio/mod_playback_view.gd")

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback = null
var loaded := false
var playing := false
var loop_song := true
var title := ""
var last_error := ""
var channel_count := 4

var _samples: Array = []    # {data:PackedByteArray, len, loop_start, loop_len, vol, finetune}
var _patterns: Array = []   # [pattern][row][4] = {period, sample, eff, param}
var _order: Array = []
var _song_len := 0
var _restart_position := 0
var _legacy_pattern_break_zero := false
var last_end_reason := ""

# Wiedergabestatus
var _speed := 6
var _bpm := 125
var _samples_per_tick := 0.0
var _tick_accum := 0.0
var _cur_order := 0
var _cur_row := 0
var _cur_tick := 0
var _channels: Array = []
var _pattern_break := -1
var _order_jump := -1
var _pattern_loop_jump := -1
var _pattern_delay_cycles := 0
var _pattern_delay_hold := false
var _sequence_stopped := false
var _finished_queued := false
var _sequence_restart_pending := false
var _sequence_finish_pending := false
var _sequence_finish_reason := ""
var _visited_flow_states: Dictionary = {}
var _skip_break_target_after_delay := false
var _realtime_buffer := PackedVector2Array()
var _playback_capacity := 0
var _view_history := PlaybackView.new()


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	# MOD-Musik ist ein kontinuierlicher Datenstrom. Ein etwas tieferer Puffer
	# faengt einzelne teure Bilddekodierungen ab; Eingabe-/SFX-Latenz ist davon
	# nicht betroffen, weil diese auf separaten Playern laufen.
	gen.buffer_length = 0.45
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = "Music"  # eigener Bus → Beat-FX kann Musik-Pegel isoliert lesen
	add_child(_player)


# --------------------------------------------------------------- Laden

func load_mod(path: String) -> bool:
	# Ein Titelwechsel darf niemals noch einen Frame aus den bereits geleerten
	# Arrays des vorherigen Songs mischen.
	if _player != null:
		stop()
	loaded = false
	last_error = ""
	title = ""
	_samples.clear()
	_patterns.clear()
	_order.clear()
	_song_len = 0
	_restart_position = 0
	_legacy_pattern_break_zero = false
	last_end_reason = ""
	channel_count = 4
	var parsed := Parser.parse(path)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "MOD konnte nicht gelesen werden."))
		return false
	title = str(parsed["title"])
	channel_count = int(parsed["channel_count"])
	_samples = parsed["samples"]
	_patterns = parsed["patterns"]
	_order = parsed["order"]
	_song_len = int(parsed["song_len"])
	_restart_position = int(parsed["restart_position"])
	_legacy_pattern_break_zero = bool(parsed["legacy_pattern_break_zero"])
	loaded = true
	_reset_state()  # frischer Songanfang
	return true


# ------------------------------------------------- Pattern-Ansicht (Tracker-UI)

const NOTE_NAMES := PlaybackView.NOTE_NAMES
const PERIODS := PlaybackView.PERIODS


## Amiga-Period -> Notenname ("C-2"), naechstliegender Tabellenwert.
func note_name(period: int) -> String:
	return PlaybackView.note_name(period)


## Aktuelle Abspielposition + umliegende Pattern-Zeilen als ProTracker-Hex
## ("C-3 04 A08"). rows = Gesamtzahl sichtbarer Zeilen (aktuelle mittig).
func playback_view(rows := 5) -> Dictionary:
	if not loaded or _order.is_empty():
		return {"ok": false}
	var state := _audible_view_state()
	if state.is_empty():
		state = {"order": _cur_order, "row": _cur_row, "tick": _cur_tick,
			"speed": _speed, "bpm": _bpm}
	return PlaybackView.format_view(state, _order, _patterns, _song_len, channel_count, rows)


func _audible_view_state() -> Dictionary:
	if _playback == null:
		return {}
	var queued := _playback_capacity - _playback.get_frames_available()
	return _view_history.state_at(maxi(0, _view_history.submitted_frames - queued))


## Kanal-Pegel 0..1 (fuer die VU-Anzeige ueber den Pattern-Spalten).
func channel_level(ch: int) -> float:
	if not playing or ch < 0 or ch >= _channels.size():
		return 0.0
	var state := _audible_view_state()
	if not state.is_empty():
		var levels: PackedFloat32Array = state["levels"]
		return float(levels[ch]) if ch < levels.size() else 0.0
	var c: Dictionary = _channels[ch]
	if not bool(c.get("active", false)):
		return 0.0
	return clampf(float(c.get("vol", 0)) / 64.0, 0.0, 1.0)


func play() -> void:
	if not loaded:
		return
	_reset_state()
	_player.play()
	_playback = _player.get_stream_playback()
	_playback_capacity = _playback.get_frames_available()
	playing = true
	_prime_realtime_buffer()


func stop() -> void:
	playing = false
	_finished_queued = false
	if _player != null:
		_player.stop()
	_playback = null
	_playback_capacity = 0
	_view_history.reset()


func _reset_state() -> void:
	_view_history.reset()
	_speed = 6
	_set_bpm(125)
	_tick_accum = 0.0
	_reset_sequence()


## Setzt nur den Tracker-Sequencer zurueck. Der Audiopuffer selbst laeuft
## weiter, damit ein MOD-Loop weder einen Generator-Neustart noch einen
## variablen Frame lang Stille produziert.
func _reset_sequence(start_order := 0) -> void:
	_speed = 6
	_set_bpm(125)
	_cur_order = clampi(start_order, 0, maxi(0, _song_len - 1))
	_cur_row = 0
	_cur_tick = 0
	_pattern_break = -1
	_order_jump = -1
	_pattern_loop_jump = -1
	_pattern_delay_cycles = 0
	_pattern_delay_hold = false
	_sequence_stopped = false
	_finished_queued = false
	_sequence_restart_pending = false
	_sequence_finish_pending = false
	_sequence_finish_reason = ""
	_visited_flow_states.clear()
	_skip_break_target_after_delay = false
	last_end_reason = ""
	_channels.clear()
	for _c in channel_count:
		_channels.append(Sequencer.new_channel())


func _process(_delta: float) -> void:
	if _finished_queued and _playback != null:
		# Der Sequencer rendert dem Lautsprecher um einen Generatorpuffer voraus.
		# Erst nach dessen Verbrauch darf eine Playlist den nächsten Song laden.
		_emit_finished()
		return
	if not playing or _playback == null:
		return
	_prime_realtime_buffer()


## Fuellt den Generator direkt beim Start. Ohne diese Vorfuellung konnte der
## erste teure UI-Frame bereits vor `_process()` eine kurze Stille erzeugen.
func _prime_realtime_buffer() -> void:
	if _playback == null:
		return
	_audible_view_state()  # begrenzt die Historie auch bei geschlossener Tracker-UI
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	if _realtime_buffer.size() != frames:
		_realtime_buffer.resize(frames)
	var audible_frames := _generate_into(_realtime_buffer, true)
	# Offline-Render behalten ihre angeforderte Länge mit Nullen am Ende.
	# Live darf dieser Padding-Rest keine zusätzliche Pause vor dem Folgetitel sein.
	if audible_frames < frames:
		_realtime_buffer.resize(audible_frames)
	if audible_frames > 0:
		_playback.push_buffer(_realtime_buffer)
		_view_history.submitted_frames += audible_frames


# --------------------------------------------------------------- Synthese

## Erzeugt n Frames (auch ohne Audiogerät nutzbar → Tests).
func render_frames(n: int) -> PackedVector2Array:
	if not loaded:
		return PackedVector2Array()
	if _channels.is_empty():
		_reset_state()
	var buf := PackedVector2Array()
	buf.resize(n)
	_generate_into(buf)
	return buf


func _generate_into(buf: PackedVector2Array, realtime_view := false) -> int:
	# Blockweise zwischen zwei Ticks mischen (Mixer.mix_block): gleiche Tick-
	# Zeitpunkte und bitgleiches PCM wie die fruehere Einzelframe-Schleife,
	# aber ohne Dictionary-Zugriffe pro Sample und Kanal.
	var n := buf.size()
	var i := 0
	var audible_frames := n
	while i < n:
		if _sequence_stopped:
			audible_frames = mini(audible_frames, i)
			buf[i] = Vector2.ZERO
			i += 1
			continue
		if _tick_accum <= 0.0:
			_do_tick(_view_history.submitted_frames + i if realtime_view else -1)
			_tick_accum += _samples_per_tick
		if _sequence_stopped:
			audible_frames = mini(audible_frames, i)
			_tick_accum -= 1.0
			buf[i] = Vector2.ZERO
			i += 1
			continue
		var count := mini(n - i, maxi(1, ceili(_tick_accum)))
		_tick_accum -= float(count)
		Mixer.mix_block(_channels, _samples, buf, i, count)
		i += count
	return audible_frames


func _mix_frame() -> Vector2:
	return Mixer.mix_frame(_channels, _samples)


# --------------------------------------------------------------- Sequencer

func _do_tick(view_frame := -1) -> void:
	# Ein natuerliches Order-Ende wird erst an der folgenden Tickgrenze
	# vollzogen. So bleibt der letzte Tick hoerbar, statt durch das Leeren der
	# Kanaele rund 20 ms zu frueh abgeschnitten zu werden.
	if _sequence_finish_pending:
		_sequence_finish_pending = false
		_finish_sequence(_sequence_finish_reason)
		return
	if _sequence_restart_pending:
		_reset_sequence(_restart_position)
	if _pattern_delay_hold:
		# Speed 1 besitzt keinen Tick 1, an dem ein verzögerter Zeilenzyklus
		# gehalten werden könnte. Dieser synthetische Hold-Tick verbraucht genau
		# eine Zeilenlänge, ohne Fxx/EEx und Noten auf Tick 0 neu auszulösen.
		_pattern_delay_hold = false
	elif _cur_tick == 0:
		if not loop_song and _flow_cycle_reached():
			_finish_sequence("flow_cycle")
			return
		_process_row()
	else:
		_process_tick_effects()
	# Vor _next_row aufnehmen: der gerade gemischte letzte Tick gehoert noch
	# zur alten Zeile, auch wenn der Sequencer bereits auf die naechste zeigt.
	if view_frame >= 0:
		_view_history.record(view_frame, _cur_order, _cur_row, _cur_tick, _speed, _bpm, _channels)
	_cur_tick += 1
	if _cur_tick >= _speed:
		if _pattern_delay_cycles > 0:
			# Stehen EEx und Dxx in derselben Zeile, ueberspringt ProTracker nach
			# dem Delay die Dxx-Zielzeile. „Condom Corruption“ nutzt das in Zeile
			# 63 bewusst: D31 fuehrt dadurch effektiv zu Zeile 32.
			if _pattern_break >= 0:
				_skip_break_target_after_delay = true
			_pattern_delay_cycles -= 1
			# Jeder Delay-Zyklus ist eine VOLLSTAENDIGE Zeilenlaenge. Der
			# synthetische Hold-Tick ersetzt Tick 0, ohne Noten/Fxx/EEx erneut
			# anzuschlagen; danach folgen regulär Tick 1..Speed-1.
			_cur_tick = 0
			_pattern_delay_hold = true
		else:
			_cur_tick = 0
			_next_row()


func _process_row() -> void:
	var usable_orders := mini(_song_len, _order.size())
	if _cur_order < 0 or _cur_order >= usable_orders:
		_wrap_order()
	if _cur_order < 0 or _cur_order >= usable_orders:
		return
	var pattern_index := int(_order[_cur_order])
	if pattern_index < 0 or pattern_index >= _patterns.size():
		for ch: Dictionary in _channels:
			ch["active"] = false
		return
	var pat: Array = _patterns[pattern_index]
	if _cur_row < 0 or _cur_row >= pat.size():
		return
	var row: Array = pat[_cur_row]
	for c in mini(channel_count, mini(row.size(), _channels.size())):
		var cell: Dictionary = row[c]
		var ch: Dictionary = _channels[c]
		var effect := int(cell["eff"])
		var param := int(cell["param"])
		var extended := param >> 4 if effect == 0xE else -1
		var extended_value := param & 0x0F
		# Ein Note-Delay gehört ausschließlich zu der Patternzelle, die ihn
		# angefordert hat. Unerreichbare EDx-Ticks (x >= Speed) dürfen niemals
		# in einer späteren Zeile plötzlich die alte Note auslösen.
		ch["delayed_period"] = 0
		ch["delayed_offset"] = 0
		# Arpeggio und Vibrato veraendern nur die gerenderte Tonhoehe einzelner
		# Ticks. Auf Tick 0 muss immer wieder die echte Basisperiode gelten.
		_update_step(ch)
		ch["eff"] = effect
		ch["param"] = param
		if int(cell["sample"]) > 0 and int(cell["sample"]) <= 31:
			ch["sidx"] = int(cell["sample"]) - 1
			ch["vol"] = _samples[ch["sidx"]]["vol"]
		if int(cell["period"]) > 0:
			var ft: int = _samples[ch["sidx"]]["finetune"]
			var period := _finetuned(cell["period"], ft)
			if effect == 0x3 or effect == 0x5:
				ch["target"] = period  # Tone-Porta: nicht neu anschlagen
			elif extended == 0xD and extended_value > 0:
				# EDx: Note erst auf Tick x starten. Instrument/Volume sind bereits
				# gelatcht, die Sampleposition bleibt bis dahin unangetastet.
				ch["delayed_period"] = period
				ch["delayed_offset"] = 0
			else:
				var offset := 0
				if effect == 0x9:
					if param > 0:
						ch["sample_offset"] = param
					offset = int(ch["sample_offset"]) * 256
				_trigger_note(ch, period, offset)
		# Tick-0-Effekte
		match effect:
			0x1:
				# Porta up/down (1xx/2xx) haben in ProTracker KEIN Gedaechtnis:
				# 100/200 schieben um 0. Nur Tone-Porta (3xx) merkt sich die Rate.
				ch["porta_up"] = param
			0x2:
				ch["porta_down"] = param
			0x3:
				if param > 0:
					ch["tone_porta"] = param
			0x4:
				_remember_vibrato(ch, param)
			0x5:
				_remember_volume_slide(ch, param)
			0x6:
				_remember_volume_slide(ch, param)
			0x9:
				if param > 0:
					ch["sample_offset"] = param
			0xA:
				_remember_volume_slide(ch, param)
			0xC:
				ch["vol"] = mini(param, 64)
			0xF:
				if param == 0:
					# Das fuer diesen Katalog validierte OpenMPT-
					# Kompatibilitaetsprofil behandelt F00 als wirkungslosen
					# Nullparameter. Ein globales Stoppen schnitt u.a. Tubular
					# Dreams um 58 s und Be De Funk II um 24 s ab.
					pass
				elif param < 0x20:
					_speed = param
				else:
					_set_bpm(param)
			0xD:
				_pattern_break = 0 if _legacy_pattern_break_zero \
					else (param >> 4) * 10 + (param & 0x0F)
			0xB:
				_order_jump = param
			0xE:
				_process_extended_tick_zero(ch, extended, extended_value)


func _process_tick_effects() -> void:
	for c in mini(channel_count, _channels.size()):
		var ch: Dictionary = _channels[c]
		match ch["eff"]:
			0x0:  # Arpeggio
				var param: int = ch["param"]
				if param != 0 and int(ch["period"]) > 0:   # ohne aktiven Ton keine Division durch 0
					var t := _cur_tick % 3
					var semi := 0
					if t == 1:
						semi = param >> 4
					elif t == 2:
						semi = param & 0x0F
					ch["step"] = (PAL_CLOCK / _period_shift(ch["period"], semi)) / MIX_RATE
			0x1:  # Porta up
				ch["period"] = maxi(MIN_PERIOD, int(ch["period"]) - int(ch["porta_up"]))
				_update_step(ch)
			0x2:  # Porta down
				ch["period"] = mini(MAX_PERIOD, int(ch["period"]) + int(ch["porta_down"]))
				_update_step(ch)
			0x3:  # Tone-Porta
				_apply_tone_porta(ch)
			0x4:  # Vibrato
				_apply_vibrato(ch)
			0x5:  # Tone-Porta + Volume-Slide
				_apply_tone_porta(ch)
				_apply_volume_slide(ch)
			0x6:  # Vibrato + Volume-Slide
				_apply_vibrato(ch)
				_apply_volume_slide(ch)
			0xA:  # Volume-Slide
				_apply_volume_slide(ch)
			0xE:
				_process_extended_tick(ch)


func _next_row() -> void:
	if _pattern_loop_jump >= 0:
		_cur_row = clampi(_pattern_loop_jump, 0, 63)
		_pattern_loop_jump = -1
		return
	if _order_jump >= 0 or _pattern_break >= 0:
		_apply_order_transition()
		return
	_cur_row += 1
	if _cur_row >= 64:
		_cur_row = 0
		_cur_order += 1
		_wrap_order()


func _apply_order_transition() -> void:
	# Bxx + Dxx duerfen in derselben Zeile stehen: B waehlt die Order,
	# D die Startzeile. Bei gleichzeitigem EEx wird die Zielzeile wie im
	# ProTracker-Replayer ausgelassen.
	var transition := Sequencer.order_transition(_cur_order, _order_jump,
		_pattern_break, _skip_break_target_after_delay)
	_skip_break_target_after_delay = false
	_order_jump = -1
	_pattern_break = -1
	_cur_order = int(transition["order"])
	_cur_row = int(transition["row"])
	_wrap_order()


func _wrap_order() -> void:
	if _song_len <= 0 or _order.is_empty():
		_finish_sequence("empty_song")
		return
	_cur_order = maxi(0, _cur_order)
	if _cur_order >= _song_len:
		if loop_song:
			_sequence_restart_pending = true
		else:
			_sequence_finish_reason = "order_end"
			_sequence_finish_pending = true


# --------------------------------------------------------------- Helfer

func _trigger_note(ch: Dictionary, period: int, sample_offset := 0) -> void:
	ch["period"] = clampi(period, MIN_PERIOD, MAX_PERIOD)
	ch["target"] = ch["period"]
	ch["pos"] = float(maxi(0, sample_offset))
	ch["delayed_period"] = 0
	ch["delayed_offset"] = 0
	var sample_index := int(ch.get("sidx", -1))
	ch["active"] = sample_index >= 0 and sample_index < _samples.size() \
		and int((_samples[sample_index] as Dictionary).get("len", 0)) > 0
	_update_step(ch)


func _remember_vibrato(ch: Dictionary, param: int) -> void:
	var speed := param >> 4
	var depth := param & 0x0F
	if speed > 0:
		ch["vibr_speed"] = speed
	if depth > 0:
		ch["vibr_depth"] = depth


func _remember_volume_slide(ch: Dictionary, param: int) -> void:
	# ProTracker-Volume-Slide (Axy/5xy/6xy) hat KEIN Effekt-Gedaechtnis: A00/500/600
	# schieben um 0, statt einen frueheren Slide fortzusetzen. Deshalb immer den
	# aktuellen Parameter uebernehmen (im Gegensatz zu Tone-Porta/Vibrato/9xx).
	ch["vol_slide"] = param


func _apply_tone_porta(ch: Dictionary) -> void:
	var current := int(ch.get("period", 0))
	var target := int(ch.get("target", 0))
	var amount := int(ch.get("tone_porta", 0))
	if current <= 0 or target <= 0 or amount <= 0:
		return
	if current < target:
		current = mini(target, current + amount)
	elif current > target:
		current = maxi(target, current - amount)
	ch["period"] = current
	_update_step(ch)


func _apply_vibrato(ch: Dictionary) -> void:
	var period := int(ch.get("period", 0))
	var speed := int(ch.get("vibr_speed", 0))
	var depth := int(ch.get("vibr_depth", 0))
	if period <= 0 or speed <= 0 or depth <= 0:
		return
	var phase := (int(ch.get("vibr_pos", 0)) + speed) & 63
	ch["vibr_pos"] = phase
	# ProTracker arbeitet mit einer 64-stufigen Sinuswelle. Eine Berechnung
	# statt einer Tabelle ist hier klanglich identisch und vermeidet Quantisierung
	# durch die Audio-Ausgaberate.
	var delta := sin(float(phase) * TAU / 64.0) * float(depth) * 2.0
	var rendered_period := clampf(float(period) + delta, MIN_PERIOD, MAX_PERIOD)
	ch["step"] = (PAL_CLOCK / rendered_period) / MIX_RATE


func _apply_volume_slide(ch: Dictionary) -> void:
	var param := int(ch.get("vol_slide", 0))
	var up := param >> 4
	var down := param & 0x0F
	# Bei ungueltigen Axy-Werten mit zwei gesetzten Nibbles gewinnt wie auf
	# gaengigen ProTracker-Replayern die Aufwaertsrichtung.
	ch["vol"] = clampi(int(ch.get("vol", 0)) + up - (down if up == 0 else 0), 0, 64)


func _process_extended_tick_zero(ch: Dictionary, command: int, value: int) -> void:
	match command:
		0x1:  # E1x Fine-Portamento hoch
			ch["period"] = maxi(MIN_PERIOD, int(ch.get("period", 0)) - value)
			_update_step(ch)
		0x2:  # E2x Fine-Portamento runter
			ch["period"] = mini(MAX_PERIOD, int(ch.get("period", 0)) + value)
			_update_step(ch)
		0x6:  # E6x Pattern-Loop
			if value == 0:
				ch["loop_row"] = _cur_row
			else:
				if int(ch.get("loop_count", 0)) == 0:
					ch["loop_count"] = value
				else:
					ch["loop_count"] = int(ch["loop_count"]) - 1
				if int(ch["loop_count"]) > 0:
					_pattern_loop_jump = int(ch.get("loop_row", 0))
		0xA:  # EAx Fine-Volume hoch
			ch["vol"] = mini(64, int(ch.get("vol", 0)) + value)
		0xB:  # EBx Fine-Volume runter
			ch["vol"] = maxi(0, int(ch.get("vol", 0)) - value)
		0xC:  # EC0 schneidet bereits auf Tick 0 ab
			if value == 0:
				ch["vol"] = 0
		0xE:  # EEx Pattern-Delay um x weitere Zeilenlaengen
			_pattern_delay_cycles = maxi(_pattern_delay_cycles, value)


func _process_extended_tick(ch: Dictionary) -> void:
	var param := int(ch.get("param", 0))
	var command := param >> 4
	var value := param & 0x0F
	match command:
		0x9:  # E9x Retrigger
			if value > 0 and _cur_tick % value == 0:
				ch["pos"] = 0.0
				ch["active"] = int(ch.get("sidx", -1)) >= 0
		0xC:  # ECx Note-Cut
			if _cur_tick == value:
				ch["vol"] = 0
		0xD:  # EDx Note-Delay
			if value > 0 and _cur_tick == value and int(ch.get("delayed_period", 0)) > 0:
				_trigger_note(ch, int(ch["delayed_period"]), int(ch.get("delayed_offset", 0)))


func _finish_sequence(reason := "sequence_end") -> void:
	last_end_reason = reason
	_sequence_stopped = true
	if _playback == null:
		playing = false
	for ch: Dictionary in _channels:
		ch["active"] = false
	if _finished_queued:
		return
	_finished_queued = true
	if _playback == null:
		call_deferred("_emit_finished")


func _flow_cycle_reached() -> bool:
	# Bxx-Rueckspruenge sind nicht pauschal ein Songende: einige historische MODs
	# durchlaufen denselben Order mehrfach mit veraenderten E6x-Loopzaehlern. Erst
	# ein vollstaendig wiederholter Kontrollzustand ist ein echtes, endloses
	# Songloop. Das verhindert sowohl ewige Playlists als auch zu fruehe Enden.
	var key := Sequencer.flow_state_key(
		_cur_order, _cur_row, _speed, _bpm, _channels)
	if _visited_flow_states.has(key):
		return true
	_visited_flow_states[key] = true
	return false


func _emit_finished() -> void:
	if not _finished_queued:
		return
	if _playback != null and _playback.get_frames_available() < _playback_capacity:
		return
	stop()
	finished.emit()


func _update_step(ch: Dictionary) -> void:
	if ch["period"] > 0:
		ch["step"] = (PAL_CLOCK / float(ch["period"])) / MIX_RATE


func _finetuned(period: int, finetune: int) -> int:
	if finetune == 0:
		return period
	return int(round(float(period) * pow(2.0, -float(finetune) / 96.0)))


func _period_shift(period: int, semitones: int) -> float:
	if semitones == 0:
		return float(period)
	return float(period) * pow(2.0, -float(semitones) / 12.0)


func _set_bpm(bpm: int) -> void:
	_bpm = maxi(32, bpm)
	_samples_per_tick = MIX_RATE * 2.5 / float(_bpm)
