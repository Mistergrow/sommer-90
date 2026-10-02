extends Node
## AudioManager — zentrale Soundausgabe. Kurze Effekte laufen über einen
## kleinen Pool von AudioStreamPlayern, damit sich Geräusche überlagern
## können, ohne sich gegenseitig abzuschneiden (z. B. Einlegen + Lesen).
##
## Aktuell bespielt: die vier Diskettengeräusche (Freesound-Community, CC0),
## konform als SFX_FLOPPY_*_V01 abgelegt. Weitere Effekte einfach in SFX
## eintragen und über play("<name>") oder einen der Aliase auslösen.

const SFX := {
	"floppy_insert": "res://assets/audio/sfx/SFX_FLOPPY_INSERT_V01.mp3",
	"floppy_read_a": "res://assets/audio/sfx/SFX_FLOPPY_READ_A_V01.mp3",
	"floppy_read_b": "res://assets/audio/sfx/SFX_FLOPPY_READ_B_V01.mp3",
	"floppy_eject":  "res://assets/audio/sfx/SFX_FLOPPY_EJECT_V01.mp3",
	# Echte Tastatur-Sounds (überschreiben die synthetischen, falls vorhanden).
	"key_click":     "res://assets/audio/sfx/SFX_KEY_CLICK_V01.ogg",
	"key_enter":     "res://assets/audio/sfx/SFX_KEY_ENTER_V01.ogg",
	"typing_fast":   "res://assets/audio/sfx/SFX_TYPING_FAST_V01.ogg",
	"typing":        "res://assets/audio/sfx/SFX_TYPING_V01.ogg",
	# Modem & Telefon (echt) — modem_dial überschreibt den synthetischen Handshake.
	"modem_dial":    "res://assets/audio/sfx/SFX_MODEM_DIAL_V01.ogg",
	"modem_dial_b":  "res://assets/audio/sfx/SFX_MODEM_DIAL_B_V01.ogg",
	"modem_usr":     "res://assets/audio/sfx/SFX_MODEM_USROBOTICS_V01.ogg",
	"phone_ring":    "res://assets/audio/sfx/SFX_PHONE_RING_V01.ogg",
	"phone_ring_office": "res://assets/audio/sfx/SFX_PHONE_RING_OFFICE_V01.ogg",
	"phone_ringback": "res://assets/audio/sfx/SFX_PHONE_RINGBACK_V01.ogg",
	"phone_dialtone": "res://assets/audio/sfx/SFX_PHONE_DIALTONE_V01.ogg",
	# Neu: echter Röhren-Start, Fax-Kreischen (falsche Nummer!), echter Donner.
	"crt_startup":   "res://assets/audio/sfx/SFX_CRT_STARTUP_V01.ogg",
	"fax":           "res://assets/audio/sfx/SFX_FAX_V01.ogg",
	"thunder":       "res://assets/audio/sfx/SFX_THUNDER_V02.ogg",
	# Gelegentlicher heller Vogelruf über dem Schönwetter-Bett (nur tagsüber).
	"bird_chirp":    "res://assets/audio/sfx/SFX_BIRD_CHIRP_V01.ogg",
	# Anrufbeantworter (echt): Abspielen (Piepser/Klicks/Leitungsbrummen),
	# Rewind-Taste, Gerät einschalten.
	"tam_play":      "res://assets/audio/sfx/SFX_TAM_PLAY_V01.ogg",
	"tam_rewind":    "res://assets/audio/sfx/SFX_TAM_REWIND_V01.ogg",
	"tam_on":        "res://assets/audio/sfx/SFX_TAM_ON_V01.ogg",
	# Telefon: echtes Besetzt-Zeichen + Hörer abnehmen/auflegen (Amts-/Freizeichen
	# liegen unter den vorhandenen Keys phone_dialtone/phone_ringback, jetzt analog).
	"phone_busy":    "res://assets/audio/sfx/SFX_PHONE_BUSY_V01.ogg",
	"phone_pickup":  "res://assets/audio/sfx/SFX_PHONE_PICKUP_V01.ogg",
	"phone_hangup":  "res://assets/audio/sfx/SFX_PHONE_HANGUP_V01.ogg",
	# Weltgeräusche: Ladenglocke, Blättern, Papier/Postkarte, Karton (Klebeband/
	# Auspacken), Plastiktüte.
	"shop_bell":     "res://assets/audio/sfx/SFX_SHOP_BELL_V01.ogg",
	"door":          "res://assets/audio/sfx/SFX_DOOR_V01.ogg",        # Tür öffnen (Zimmer/Freundeszimmer)
	"footsteps":     "res://assets/audio/sfx/SFX_FOOTSTEPS_V01.ogg",   # Ankunft nach Ortswechsel
	"haggle":        "res://assets/audio/sfx/SFX_HAGGLE_V01.ogg",      # Feilsch-Gemurmel (Flohmarkt)
	"knock":         "res://assets/audio/sfx/SFX_KNOCK_V01.ogg",       # Freund klopft (normal)
	"knock_fast":    "res://assets/audio/sfx/SFX_KNOCK_FAST_V01.ogg",  # ungeduldig/energisch
	"knock_soft":    "res://assets/audio/sfx/SFX_KNOCK_SOFT_V01.ogg",  # sachte/leise — jeder klopft anders
	"page_turn":     "res://assets/audio/sfx/SFX_PAGE_TURN_V01.ogg",
	"paper":         "res://assets/audio/sfx/SFX_PAPER_V01.ogg",
	"box_tape":      "res://assets/audio/sfx/SFX_BOX_TAPE_V01.ogg",
	"box_item":      "res://assets/audio/sfx/SFX_BOX_ITEM_V01.ogg",
	"bag":           "res://assets/audio/sfx/SFX_BAG_V01.ogg",
	# Geld: Ladenkasse (Kauf), Münzen (Verkauf/Lohn), Scheine zählen (Bank).
	"cash_register": "res://assets/audio/sfx/SFX_CASH_REGISTER_V01.ogg",
	"coins":         "res://assets/audio/sfx/SFX_COINS_V01.ogg",
	"cash_count":    "res://assets/audio/sfx/SFX_CASH_COUNT_V01.ogg",
	"camera":        "res://assets/audio/sfx/SFX_CAMERA_V01.ogg",   # Foto-Album (Idee)
	# Bearbeiteter, nahtloser Motor-Loop fuer das gehaltene Staubsauger-Werkzeug.
	# Eigener Player in HouseholdSprintStage, damit Start/Stop exakt der Hand folgt.
	"vacuum_loop":   "res://assets/audio/sfx/SFX_VACUUM_CLEANER_LOOP_V01.ogg",
}

const POOL_SIZE := 6
## Einige Mischbloecke des Audio-Threads (Dummy- wie Echttreiber), auch wenn
## die CPU ausgelastet ist; beim Beenden nicht spuerbar.
const SHUTDOWN_MIX_MSEC := 100

const SfxSynthScript := preload("res://scripts/audio/sfx_synth.gd")

var muted := false
var sfx_db := -5.0

var _streams: Dictionary = {}
var _pool: Array = []
var _next := 0
var _floppy_read_serial := 0
var _play_serials: Dictionary = {}

# Dauer-Loops (eigene Player) + Wetter-Bett.
var _crt_player: AudioStreamPlayer = null
var _rain_player: AudioStreamPlayer = null
var _birds_player: AudioStreamPlayer = null    # Schönwetter-Vogelbett (nur tagsüber)
var _typing_player: AudioStreamPlayer = null   # Programmierer-Tipp-Bett
var _rattle_player: AudioStreamPlayer = null   # Kopf-Rattern beim Kopieren (stapelt NICHT)
var _storm := false
var _thunder_t := 6.0
var _chirp_t := 9.0
var _rain_light: AudioStream = null            # leichter Regen (durchs Fenster)
var _rain_heavy: AudioStream = null            # kräftiger Regen (Gewitter)
var _weather := "clear"
var _daytime := true
var _weather_sync_t := 0.0                     # Save-Laden kann das Datum ohne Wettersignal wechseln


func _ready() -> void:
	var missing_files: Array[String] = []
	for sfx_name in SFX:
		var path: String = SFX[sfx_name]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				_streams[sfx_name] = stream
			else:
				missing_files.append(path)
		else:
			missing_files.append(path)
	if not missing_files.is_empty():
		push_error("AudioManager: %d exportierte SFX fehlen/koennen nicht geladen werden: %s" % [
			missing_files.size(), ", ".join(missing_files.slice(0, 8))])
	for _i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)
	# Dedizierter Player fürs Kopf-Rattern beim Kopieren — genau EINE Instanz, damit
	# sich die langen Read-Samples nicht überlagern (Doppel-Sound bei Einlaufwerk-Kopie).
	_rattle_player = AudioStreamPlayer.new()
	_rattle_player.bus = "SFX"
	add_child(_rattle_player)
	# Prozedurale 90er-Computer-Sounds als Fallback — echte Dateien (oben in SFX)
	# gewinnen, wo vorhanden (z. B. key_click). get()-Fallback lässt sie stehen.
	_streams["ui_blip"] = _streams.get("ui_blip", SfxSynthScript.ui_blip())
	_streams["key_click"] = _streams.get("key_click", SfxSynthScript.key_click())
	_streams["relay"] = _streams.get("relay", SfxSynthScript.relay())
	_streams["joystick_click"] = _streams.get("joystick_click", SfxSynthScript.joystick_click())
	_streams["solder_touch"] = _streams.get("solder_touch", SfxSynthScript.solder_touch())
	_streams["continuity_ok"] = _streams.get("continuity_ok", SfxSynthScript.continuity_ok())
	_streams["joint_bad"] = _streams.get("joint_bad", SfxSynthScript.joint_bad())
	# Stadtbank: rauer Kartenleser-Motor und mechanischer Banknotentransport.
	# Eigene Signatur statt generischem UI-Klick — der GAA soll sich wie eine
	# schwere Maschine von 1990 anfuehlen.
	_streams["atm_card"] = _streams.get("atm_card", SfxSynthScript.atm_card())
	_streams["atm_dispense"] = _streams.get("atm_dispense", SfxSynthScript.atm_dispense())
	_streams["modem_dial"] = _streams.get("modem_dial", SfxSynthScript.modem_dial())
	_streams["crt_off"] = _streams.get("crt_off", SfxSynthScript.crt_off())
	_streams["thunder"] = _streams.get("thunder", SfxSynthScript.thunder())
	# Kurze, räumlich getrennte Scheiben-Aufpraller. Das dauerhafte Regenbett
	# liefert die Masse; diese Impulse machen nur einzelne nahe Kontakte lesbar.
	_streams["rain_glass_left"] = SfxSynthScript.rain_glass_impact(-0.72, false)
	_streams["rain_glass_right"] = SfxSynthScript.rain_glass_impact(0.72, false)
	_streams["rain_glass_heavy_left"] = SfxSynthScript.rain_glass_impact(-0.66, true)
	_streams["rain_glass_heavy_right"] = SfxSynthScript.rain_glass_impact(0.66, true)
	_crt_player = _make_loop_player("SFX", SfxSynthScript.crt_hum(), -24.0)
	# Echte Regenbetten (Datei gewinnt, sonst synthetischer Regen als Fallback).
	# _rain_light = leichter Fensterregen ("rain"), _rain_heavy = Gewitterregen.
	_rain_light = _loop_stream("res://assets/audio/sfx/SFX_RAIN_ROOM_V01.ogg", SfxSynthScript.rain())
	_rain_heavy = _loop_stream("res://assets/audio/sfx/SFX_RAIN_STORM_V01.ogg", _rain_light)
	# Die Aufnahme besitzt selbst nur etwa -28 dB mittlere Lautheit. -9 dB am
	# Player machte den Regen hinter Raumton/Musik faktisch unhörbar. Der Loop
	# bleibt ein zurückhaltendes Fensterbett, ist bei normaler Masterlautstärke
	# nun aber klar wahrnehmbar.
	_rain_player = _make_loop_player("Ambient", _rain_light, -3.5)
	# Schönwetter-Vogelbett (nur tagsüber, clear/clouds) — leise über allem.
	var birds := _loop_stream("res://assets/audio/sfx/SFX_BIRDS_V01.ogg", null)
	if birds != null:
		_birds_player = _make_loop_player("Ambient", birds, -18.0)
	# Tipp-Bett des Programmierers (schnelles Tippen, Loop auf Ambient-Bus).
	var typing_stream: AudioStream = _streams.get("typing_fast")
	if typing_stream != null and "loop" in typing_stream:
		typing_stream.set("loop", true)
	if typing_stream != null:
		_typing_player = _make_loop_player("Ambient", typing_stream, -14.0)
	# Tageszeit: Vögel schweigen abends/nachts (Slot 3/4).
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("slot_changed"):
		tm.slot_changed.connect(_on_slot_changed)
		_daytime = int(tm.get("slot")) <= 2
	# Wetter-Bett automatisch am WeatherManager (Regen-Loop + Donner im Sturm,
	# Vögel bei Sonne). weather_changed steuert Regen/Donner, slot die Vögel.
	var wm := get_node_or_null("/root/WeatherManager")
	if wm != null and wm.has_signal("weather_changed"):
		wm.weather_changed.connect(_on_weather_changed)
		_apply_weather(str(wm.call("state")))
	else:
		_apply_weather("clear")


func _make_loop_player(bus: String, stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


## Loop-Stream aus Datei laden (mit loop-Flag), sonst Fallback zurückgeben.
func _loop_stream(path: String, fallback: AudioStream) -> AudioStream:
	if ResourceLoader.exists(path):
		var s: AudioStream = load(path)
		if s != null:
			if "loop" in s:
				s.set("loop", true)
			return s
	return fallback


func _process(delta: float) -> void:
	# WeatherOverlay und WeatherManager cachen den datumsabhängigen Zustand. Beim
	# Laden eines Spielstands setzt
	# TimeManager.from_dict() jedoch Datum/Slot ohne day_changed — Ergebnis:
	# sichtbarer Regen, aber ein weiterhin trockenes Audiobett. Vier Prüfungen pro
	# Sekunde sind billig und halten Bild und Ton auch nach Laden/Debug-Overrides
	# garantiert synchron.
	_weather_sync_t -= delta
	if _weather_sync_t <= 0.0:
		_weather_sync_t = 0.25
		var weather_manager := get_node_or_null("/root/WeatherManager")
		if weather_manager != null:
			var actual := str(weather_manager.call("state"))
			if actual != _weather:
				_apply_weather(actual)
	if muted:
		return
	if _storm:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			play("thunder", 0.02)
			# Der neue Donner-Clip ist ~12 s lang → größerer Abstand, kein Stapeln.
			_thunder_t = randf_range(14.0, 28.0)
	elif _birds_player != null and _birds_player.playing:
		# Gelegentlicher einzelner Vogelruf über dem Bett (nur bei Sonne, tagsüber).
		_chirp_t -= delta
		if _chirp_t <= 0.0:
			play("bird_chirp", 0.10)
			_chirp_t = randf_range(9.0, 22.0)


## Einen Effekt abspielen. pitch_jitter streut die Tonhöhe leicht, damit
## wiederholte Geräusche (mehrfaches Lesen) nicht mechanisch gleich klingen.
func play(sfx_name: String, pitch_jitter := 0.06, volume_offset_db := 0.0) -> void:
	if muted or _pool.is_empty() or not _streams.has(sfx_name):
		return
	_play_serials[sfx_name] = int(_play_serials.get(sfx_name, 0)) + 1
	var player: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = _streams[sfx_name]
	player.volume_db = sfx_db + volume_offset_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


## Monotoner Diagnosewert fuer Audio-Regressionstests. Er veraendert weder
## Pooling noch Wiedergabe und wird nicht gespeichert.
func play_serial(sfx_name: String) -> int:
	return int(_play_serials.get(sfx_name, 0))


## Stoppt nur laufende Instanzen des benannten Effekts. Anders als ein globales
## Pool-Stoppen bleiben dadurch Dialog-, UI- und Raumgeraeusche unangetastet.
func stop_sfx(sfx_name: String) -> void:
	if not _streams.has(sfx_name):
		return
	var target: AudioStream = _streams[sfx_name]
	for player: AudioStreamPlayer in _pool:
		if player.playing and player.stream == target:
			player.stop()


## Deterministische Tonhoehe fuer musikalische Minispiele. Anders als `play`
## ist dies kein Zufalls-Jitter und damit fuer A/B-Playback reproduzierbar.
func play_toned(sfx_name: String, pitch_scale: float) -> void:
	if muted or _pool.is_empty() or not _streams.has(sfx_name): return
	var player: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = _streams[sfx_name]; player.volume_db = sfx_db
	player.pitch_scale = clampf(pitch_scale, 0.35, 2.2); player.play()


## Prozedurale, reproduzierbare Paula-/Tracker-Cues fuer alle Minispiele. Die
## ID bestimmt die Grundtonlage, das Ereignis das kurze 4-Kanal-Muster.
func minigame_cue(id:String,event:StringName=&"action")->void:
	if muted or _pool.is_empty():return
	var base:float=180.0+posmod(hash(id),360);var event_offset:float=float({&"focus":0.0,&"action":70.0,&"hint":-45.0,&"error":-95.0,&"success":180.0}.get(event,30.0))
	var stream:=_synth_cue(base+event_offset,event,id)
	var player:AudioStreamPlayer=_pool[_next];_next=(_next+1)%_pool.size();player.stream=stream;player.volume_db=sfx_db-5.0;player.pitch_scale=1.0;player.play()
	if Input.get_connected_joypads().size()>0 and event in [&"action",&"error",&"success"]:
		Input.start_joy_vibration(Input.get_connected_joypads()[0],.16 if event!=&"error"else .32,.28 if event==&"success"else .12,.07 if event==&"action"else .13)

## Adaptername bleibt für bestehende Minispiele und ältere Szenen stabil.
func _synth_cue(frequency:float,event:StringName,id:String="minigame")->AudioStreamWAV:
	return SfxSynthScript.tracker_cue(id,event,frequency)


# ------------------------------------------------------------- Aliase

func floppy_insert() -> void:
	play("floppy_insert")


## Lesegeräusch — würfelt zwischen den beiden Aufnahmen für Abwechslung.
func floppy_read() -> void:
	_floppy_read_serial += 1
	play("floppy_read_a" if randf() < 0.5 else "floppy_read_b")


## Monotoner, flüchtiger Diagnosewert für Tests und Audio-Telemetrie. Anders als
## der Ringindex des SFX-Pools zählt er auch bei gleichzeitigem Raumklang exakt.
func floppy_read_serial() -> int:
	return _floppy_read_serial


## Kopf-Rattern beim KOPIEREN — nicht-stapelnd: läuft schon eine Instanz, bleibt
## sie (statt ein zweites langes Sample darüberzulegen). Erst wenn sie ausklingt,
## startet der nächste Aufruf neu → durchgehendes Rattern ohne Doppel-Sound.
func floppy_rattle() -> void:
	if _rattle_player == null or _rattle_player.playing:
		return
	var stream: AudioStream = _streams.get("floppy_read_a")
	if stream == null:
		return
	_rattle_player.stream = stream
	_rattle_player.pitch_scale = 1.0
	_rattle_player.play()


func floppy_eject() -> void:
	play("floppy_eject")


# ----------------------------------------------------- Prozedurale Aliase
func ui_click() -> void:
	play("ui_blip")


func key_click() -> void:
	play("key_click", 0.12)   # etwas Tonhöhen-Streuung = mechanischer


func key_enter() -> void:
	play("key_enter", 0.04)   # Enter/Bestätigen — satterer Anschlag


## Schnelles Tipp-Bett (Programmierer) starten/stoppen — Loop auf dem Ambient-Bus.
func start_typing() -> void:
	if _typing_player != null and not _typing_player.playing and not muted:
		_typing_player.play()


func stop_typing() -> void:
	if _typing_player != null and _typing_player.playing:
		_typing_player.stop()


func relay() -> void:
	play("relay", 0.03)


func modem_dial() -> void:
	play("modem_dial", 0.0)   # der Handshake soll NICHT verstimmt sein


func phone_ring() -> void:
	play("phone_ring", 0.0)       # eingehender Anruf (Klingel)


func phone_ringback() -> void:
	play("phone_ringback", 0.0)   # Freizeichen beim Rauswählen


func phone_dialtone() -> void:
	play("phone_dialtone", 0.0)   # Amtszeichen / besetzt


## CRT-Brummen starten/stoppen (beim Monitor ein-/ausschalten aufrufen).
## Beim Einschalten knistert erst der echte Röhren-Start, dann setzt das Brummen ein.
func start_crt_hum() -> void:
	if _streams.has("crt_startup"):
		play("crt_startup", 0.0)
	if _crt_player != null and not _crt_player.playing and not muted:
		_crt_player.play()


func stop_crt_hum() -> void:
	if _crt_player != null and _crt_player.playing:
		_crt_player.stop()
		play("crt_off")


# ----------------------------------------------------- Wetter-Bett
func _on_weather_changed(state: String) -> void:
	_apply_weather(state)


func _on_slot_changed(slot: int) -> void:
	# Vögel nur morgens/mittags/nachmittags (0–2), nicht abends/nachts.
	var day := slot <= 2
	if day == _daytime:
		return
	_daytime = day
	_refresh_birds()


func _apply_weather(state: String) -> void:
	_weather = state
	var raining := state == "rain" or state == "storm"
	_storm = state == "storm"
	if _rain_player != null:
		# Gewitter liegt etwas näher und kräftiger im Raum, normaler Regen bleibt
		# hinter der geschlossenen Scheibe hörbar, aber nicht aufdringlich.
		_rain_player.volume_db = -1.5 if _storm else -3.5
		# Passenden Regen-Stream wählen (leicht vs. Gewitter) und schalten.
		var wanted: AudioStream = _rain_heavy if _storm else _rain_light
		if raining:
			if _rain_player.stream != wanted:
				_rain_player.stream = wanted
				if _rain_player.playing:
					_rain_player.play()
			if not _rain_player.playing and not muted:
				_rain_player.play()
		elif _rain_player.playing:
			_rain_player.stop()
	if _storm:
		_thunder_t = randf_range(3.0, 7.0)
	_refresh_birds()


## Vögel spielen nur bei Sonne/leichter Bewölkung UND tagsüber UND nicht stumm.
func _refresh_birds() -> void:
	if _birds_player == null:
		return
	var want := _daytime and (_weather == "clear" or _weather == "clouds") and not muted
	if want and not _birds_player.playing:
		_chirp_t = randf_range(4.0, 10.0)
		_birds_player.play()
	elif not want and _birds_player.playing:
		_birds_player.stop()


## Laufende Diskettengeräusche SOFORT stoppen (z. B. beim Diskettenwechsel oder
## wenn der Spieler mitten im Rattern etwas anderes anklickt).
func stop_floppy() -> void:
	var floppy_streams := [_streams.get("floppy_insert"), _streams.get("floppy_read_a"),
		_streams.get("floppy_read_b"), _streams.get("floppy_eject")]
	for p: AudioStreamPlayer in _pool:
		if p.playing and p.stream in floppy_streams:
			p.stop()
	if _rattle_player != null and _rattle_player.playing:
		_rattle_player.stop()   # auch das durchgehende Kopf-Rattern beenden


# ------------------------------------------------------------- Steuerung

## SFX-Lautstärke setzen (linear 0..1) — wird beim nächsten Effekt angewandt.
func set_sfx_volume(linear: float) -> void:
	sfx_db = -60.0 if linear <= 0.001 else linear_to_db(clampf(linear, 0.0, 1.0))


func toggle_mute() -> bool:
	muted = not muted
	if muted:
		for player in _pool:
			player.stop()
		if _crt_player != null:
			_crt_player.stop()
		if _rain_player != null:
			_rain_player.stop()
		if _birds_player != null:
			_birds_player.stop()
		if _typing_player != null:
			_typing_player.stop()
	else:
		# Wetter-Bett (Regen/Vögel) nach dem Stummschalten wieder aufnehmen.
		_apply_weather(_weather)
	return muted


## Kontrollierter Abbau für Release-Audits. Normales Stummschalten hält Streams
## absichtlich resident; beim Prozessende müssen auch Playback und Referenzen
## gelöst werden, bevor der AudioServer selbst finalisiert.
func release_audio() -> void:
	muted = true
	for player: AudioStreamPlayer in _pool:
		player.stop()
		player.stream = null
	if _rattle_player != null:
		_rattle_player.stop()
		_rattle_player.stream = null
	for player: AudioStreamPlayer in [
		_crt_player, _rain_player, _birds_player, _typing_player,
	]:
		if player != null:
			player.stop()
			player.stream = null
	_streams.clear()
	_rain_light = null
	_rain_heavy = null



## Prozessende (Spiel-„Beenden“, Fensterschließen und jedes SceneTree.quit()):
## Autoloads verlassen den Baum in umgekehrter Reihenfolge, Music-/Ambient-
## Manager und Szene sind hier also schon draußen. Deshalb bewusst KEINE
## Manager-Logik und keine Signale, nur die Player selbst stoppen. Gestoppte
## Playbacks gibt erst der nächste Mischschritt des Audio-Threads frei; ohne
## kurze Wartezeit finalisiert der AudioServer sie als geleakte Playbacks.
func _exit_tree() -> void:
	for node: Node in get_tree().root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			node.call("stop")
	# Auch ein im letzten Frame gestarteter und sofort gestoppter Sound wartet
	# noch auf Freigabe.
	OS.delay_msec(SHUTDOWN_MIX_MSEC)
