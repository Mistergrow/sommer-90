class_name XCopyScreen
extends Control
## X-COPY — originalgetreue Nachbildung des legendären Amiga-Disketten-Kopierers
## in ZWEI Ausbaustufen (HOMAGE/Platzhalter; X-COPY ist eine echte Marke, im Spiel
## als Zeitkolorit nachgebaut — Marken-/Lizenzklärung vor Release, GDD Kap. 18):
##
##  • Standard (pro=false): die frühe lila „X-COPY"-Version (deutsche Labels).
##  • Professional (pro=true): die PREMIUM-Version v6.7 auf Schwarz mit
##    Chrom-Logo, DF0–DF3 mit Lämpchen, englische Labels — erscheint erst später
##    im Spielverlauf (schneller, mehr Laufwerke).
##
## Läuft als Vollbild-Programm auf der WERKBANK und füllt die Zimmeransicht.
## Funktional: kopiert eine bespielte Diskette auf eine Leerdiskette
## (DiskManager.copy_disk); die Track/Sektor-Raster laufen dabei voll.

const Diagnosis := preload("res://scripts/ui/xcopy_diagnosis.gd")

const VW := 640.0
const VH := 400.0

var pro := false
## classic = historische X-COPY-Disk, professional = spaetere Clubfassung,
## sommer = eigener, 1992 entwickelter Ein-Pass-Kopierer des Spielers.
## Drei bewusst getrennte Produkte auf derselben geprueften Kopierengine:
## originale X-COPY-Disk, Clubfassung X-COPY Professional und der 1992 vom
## Spieler entwickelte Eigenbau Sommer Copy 92.
var edition := "classic"
var initial_source: Disk = null
var operation_kind := "copy"    # copy | backup | check

# gemeinsame Farben
const WHITE := Color8(246, 246, 250)
const GREEN := Color8(96, 226, 116)
const YELLOW := Color8(240, 204, 62)   # „0" nach dem Lesen (im RAM-Puffer)
const RED := Color8(232, 84, 72)
const CYAN := Color8(126, 224, 244)
const GRID_BG := Color8(10, 10, 16)
const GRID_LINE := Color8(70, 76, 92)
const CACHET := [Color8(232, 70, 70), Color8(240, 150, 50), Color8(240, 220, 70),
	Color8(90, 210, 110), Color8(90, 180, 240)]

var _actions: Array = []
var _drives: Array = []
var _menu_btns: Array = []
var _src_bulbs: Array = []      # klickbare Quell-Lämpchen (pro)
var _dst_bulbs: Array = []      # klickbare Ziel-Lämpchen (pro)
var _src_drive := 0
var _dst_drive := 0
var _src_index := -1
var _src_chosen = null           # per Disketten-Picker gewählte QUELLE (Disk)
var _dst_chosen = null           # per Picker gewählte LEER-Diskette (Ziel)
var _start_after_dest_pick := false
const DiskPicker := preload("res://scripts/ui/disk_picker_screen.gd")

# --- Kopiersequenz (originalgetreu): X-COPY las Spuren in DURCHGÄNGEN in den
# RAM (Quell-Laufwerk aktiv) und schrieb sie dann aufs Ziel (Ziel-Laufwerk
# aktiv). Wie viele Spuren pro Durchgang passen, hängt vom Speicherausbau ab —
# mehr RAM = weniger Durchgänge = schnellere Kopie. Beide Seiten (OBERSEITE/
# UNTERSEITE) laufen parallel, weil der Kopf zylinderweise liest.
const TRACKS := 80              # Spuren 0-79 (wie das Original-LCD: ENDE 79)
# Kopiermodi wie im Original-Handbuch (Klick aufs Modus-Feld schaltet durch):
#  DOSCOPY    = "fast backup mode, which allows you to back up a disk as it is"
#  DOSCOPY+   = wie DOSCOPY, "but it repairs errors which are found on your
#               source disk" (Fehler-Spuren werden nachgelesen → wieder grün)
#  BAMCOPY+   = wie DOSCOPY+, "formats and copies used tracks only" (leere
#               Spuren bleiben im Raster leer — noch schneller)
#  NIBBLECOPY = Rohdaten-Kopie: langsamer, keine DOS-Fehlererkennung (keine
#               roten Ziffern — man sieht Fehler schlicht nicht)
# Raster-Codes wie im Original: grüne „0" = Spur ok; rote Ziffer = Fehlercode
# (1=Sektoranzahl, 2=kein Sync, 4=Header-Prüfsumme, 6=Daten-Prüfsumme,
#  7=Longtrack, 8=Verify-Fehler — beim Schreiben entdeckt).
const MODE_NAMES := ["DOSCOPY", "DOSCOPY+", "BAMCOPY+", "NIBBLECOPY"]
var _mode := 0
var _bam_skip: Dictionary = {}  # Spur -> true (BAMCOPY+: unbelegte Spuren)
var _copying := false
var _check_only := false        # PRÜFEN: nur Lese-Durchgänge, kein Schreiben
var _phase := ""                # "" | "read" | "write"
var _track := 0                 # gerade bearbeitete Spur (Zylinder)
var _pass_to := 0               # exklusives Ende des aktuellen Durchgangs
var _pass_num := 1
var _pass_total := 1
var _read_done := 0             # Spuren im RAM (Zellen < _read_done gedimmt)
var _write_done := 0            # geschriebene Spuren (Zellen < _write_done = OK)
var _gap := 0.0                 # kurze Pause bei Phasenwechsel (Kopf/Spin-up)
var _result := {}               # echtes Backup-Ergebnis (beim ersten Schreiben)
var _demo := false
var _err_cells: Array = []      # Fehler-Spuren (rot, erscheinen beim Schreiben)
var _accum := 0.0
var _time := 0.0
var _status := ""
var _diagnosis: Dictionary = {}
var _service_action := ""       # repair | rescue | backup
var _service_label := ""
var _service_btn: Button
# --- Disketten-Wechsel (Amiga 500 mit NUR einem Laufwerk): X-COPY liegt auf
# seiner eigenen Disk, dann legt man die ORIGINAL-Disk (Quelle) ein und liest sie
# in den RAM, dann die LEER-Disk (Ziel) und schreibt. Passt die Disk nicht in
# einem Rutsch in den Speicher (512 KB), muss man fürs nächste Stück nochmal die
# Original- und dann wieder die Leerdiskette einlegen. Mit 1-MB-Erweiterung geht
# alles in EINEM Durchgang. Mit externem Laufwerk (DF1:) entfällt der Wechsel.
var _single_drive := true
var _await_insert := ""          # "" | "source" | "dest" — wartet auf Diskettenwechsel
var _swap_blink := 0.0
var marble_cache: Array = []           # gecachte Marmor-Kreise (deterministisch)
var marble_cache_size := Vector2.ZERO  # Größe, für die marble_cache berechnet wurde


func _ready() -> void:
	if edition.is_empty():
		edition = "professional" if pro else "classic"
	pro = edition == "professional"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50   # über der Werkbank (z40)
	focus_mode = Control.FOCUS_ALL
	_single_drive = not PlayerStats.has_hardware("external_drive")
	# Bei einem nackten Amiga ist DF0: abwechselnd Quelle und Ziel. DF1: darf
	# weder als logisches Ziel gelten noch während der Schreibphase aufleuchten.
	_src_drive = 0
	_dst_drive = 0 if _single_drive else 1
	operation_kind = operation_kind if operation_kind in ["copy", "backup", "check"] else "copy"
	_status = ("TUTORIAL: rote Masterdisk sichern · START drücken."
		if _space_copy_tutorial_active() else _initial_status())
	var parent := get_parent_control()
	if parent != null:
		parent.resized.connect(_sync_size)
	_sync_size.call_deferred()
	_build_buttons()
	if initial_source != null and is_instance_valid(initial_source) and initial_source in _content_disks():
		_src_chosen = initial_source
		_src_index = -1
	else:
		initial_source = null
		_pick_first_source()
	resized.connect(_layout)
	call_deferred("_layout")
	set_process(true)
	grab_focus.call_deferred()
	if operation_kind == "check" and _source_disk() != null:
		_begin_context_check.call_deferred()


func _sync_size() -> void:
	var parent := get_parent_control()
	if parent != null:
		position = Vector2.ZERO
		size = parent.size
		_layout()


# ----------------------------------------------------------------- Quelle

func _content_disks() -> Array:
	var result := DiskManager.media_disks().filter(func(d) -> bool:
		return d.content_type != "leer" and d.content_type != "mystery")
	if _space_copy_tutorial_active():
		result.sort_custom(func(a: Disk, b: Disk) -> bool:
			var a_target := a.software_id == "space_lemming_trouble" and a.is_game_master()
			var b_target := b.software_id == "space_lemming_trouble" and b.is_game_master()
			if a_target != b_target:
				return a_target
			return a.display_name().naturalnocasecmp_to(b.display_name()) < 0)
	return result


func _space_copy_tutorial_active() -> bool:
	return QuestManager.is_active("q_stefan_space") and QuestManager.stage("q_stefan_space") == 1


func _space_master() -> Disk:
	for disk: Disk in DiskManager.media_disks():
		if disk.software_id == "space_lemming_trouble" and disk.is_game_master() and disk.condition > 0:
			return disk
	return null


func _pick_first_source() -> void:
	_src_index = 0 if not _content_disks().is_empty() else -1


func _initial_status() -> String:
	if initial_source != null:
		if operation_kind == "check":
			return "Prueflauf vorbereitet: %s" % initial_source.display_name()
		if operation_kind == "backup":
			return "Archivquelle geladen: %s — START druecken." % initial_source.display_name()
		return "Quelle geladen: %s — START druecken." % initial_source.display_name()
	if is_sommer_copy():
		return "EIGENBAU BEREIT · Quelle waehlen · Ein-Pass-Verify starten."
	return "Bereit. Quelle waehlen, START druecken." if not pro else "Ready. Select source, press START."


func _begin_context_check() -> void:
	if not _copying and operation_kind == "check" and _source_disk() != null:
		_begin_copy(false, true)


func _source_disk():
	if _src_chosen != null and is_instance_valid(_src_chosen):
		return _src_chosen
	var cd := _content_disks()
	if _src_index >= 0 and _src_index < cd.size():
		return cd[_src_index]
	return null


# ----------------------------------------------------------------- Labels

func _action_labels() -> Array:
	return ["START", "REPEAT", "STOP", "DISK-INFO", "DIR", "CHECK", "DEFAULT"] if pro \
		else ["START", "NOCHMAL", "STOP", "DISK-INFO", "INHALT", "PRÜFEN", "ZURÜCK"]


func _menu_labels() -> Array:
	return ["COPY", "TOOLS", "START", "END", "SIDE", "SYNC", "MODE"] if pro \
		else ["COPY", "TOOLS", "START", "ENDE", "SEITE", "SYNC", "ÜBER"]


func _lcd_values() -> Array:
	return ["00", "0", "79", "1", "BOTH", "4489", "DISK"] if pro \
		else ["00", "0", "79", "1", "BEIDE", "4489", "RAM"]


func _ram_mb() -> float:
	return float(int(PlayerStats.ram_breakdown()["total_kb"])) / 1024.0


## Gesamtfortschritt des Kopiervorgangs in Prozent (Lesen + Schreiben aller Spuren).
func _progress() -> int:
	var total := float(TRACKS) if _check_only else float(TRACKS) * 2.0
	var done := float(_read_done) + (0.0 if _check_only else float(_write_done))
	return clampi(roundi(100.0 * done / maxf(1.0, total)), 0, 100)


## Spuren pro Lese-Durchgang: hängt vom RAM ab. Mit 1-MB-Erweiterung (oder mehr)
## passt die ganze 880-KB-Disk in einem Rutsch in den Puffer → EIN Durchgang,
## nur einmal Quelle→Ziel wechseln. Der nackte Amiga 500 (512 KB) schafft nur die
## halbe Disk am Stück → zwei Durchgänge, also einmal nachlegen.
func _tracks_per_pass() -> int:
	if _ram_mb() >= 1.0:
		return TRACKS
	return int(ceil(TRACKS / 2.0))


func _whole_disk_buffered() -> bool:
	return _tracks_per_pass() >= TRACKS


func _phase_progress() -> int:
	var done := _read_done if _phase == "read" else _write_done
	return clampi(roundi(100.0 * float(done) / float(TRACKS)), 0, 100)


func _free_mem() -> String:
	var ram := _ram_mb()
	var bytes := 1837208 if ram >= 2.0 else (925696 if ram >= 1.0 else 430080)
	if is_sommer_copy():
		return "PUFFER: %d Bytes · ECS-KANALWACHE AKTIV" % bytes
	return ("Free mem: %d bytes are unused" if pro else "Freier Speicher: %d Bytes.") % bytes


func _lcd_color() -> Color:
	if is_sommer_copy():
		return Color8(102, 242, 202)
	return Color8(240, 210, 70) if pro else Color8(246, 158, 48)


func is_sommer_copy() -> bool:
	return edition == "sommer"


func is_sommer_copy_prototype() -> bool:
	return is_sommer_copy() and QuestManager.is_active("q_sommer_copy_92")


# ----------------------------------------------------------------- Buttons

func _build_buttons() -> void:
	var labels := _action_labels()
	var xs := [18.0, 96.0, 186.0, 254.0, 354.0, 442.0, 548.0]
	var ws := [74.0, 86.0, 64.0, 96.0, 84.0, 84.0, 84.0]
	var cbs := [_start, _again, _stop, _diskinfo, _contents, _verify, _last_action]
	var cols := [CYAN, WHITE, WHITE, GREEN, GREEN, GREEN, RED]
	for i in labels.size():
		_actions.append({"id": labels[i], "rect": Rect2(xs[i], 104, ws[i], 22),
			"cb": cbs[i], "color": cols[i], "button": _hit(cbs[i])})
	# Kontextaktion nach einem abgeschlossenen PRUEFEN-Lauf. Das sichtbare Label
	# zeichnet XCopyDraw; der echte Button bleibt Teil derselben Skalen-UI.
	_service_btn = _hit(_run_service_action)
	_service_btn.disabled = true
	# Menü-Klickflächen (COPY/TOOLS/…/MODE|ÜBER)
	var menu := _menu_labels()
	var mx := [22.0, 96.0, 214.0, 342.0, 424.0, 502.0, 582.0]
	for i in menu.size():
		var cb := _about if i == menu.size() - 1 else _menu_noop.bind(menu[i])
		_menu_btns.append({"label": menu[i], "x": mx[i], "button": _hit(cb)})
	# Modus-Feld (DOSCOPY/…): Klick schaltet durch — wie im Original
	_mode_btn = _hit(_cycle_mode)
	# Fenster-Schließen-Gadget (Professional oben rechts)
	if pro:
		_close_btn = _hit(_close)
	# Laufwerke DF0–DF3
	var max_drive: int = 1 if PlayerStats.has_hardware("external_drive") else 0
	for i in 4:
		var b := _hit(_select_drive.bind(i))
		b.disabled = i > max_drive
		var rect := Rect2(36 + i * 66, 208, 56, 66)
		_drives.append({"idx": i, "rect": rect, "button": b})
		if pro:
			# Klickbare Glühbirnen: oben = Quelle wählen, unten = Ziel wählen
			var cx := rect.position.x + rect.size.x * 0.5
			var sb := _hit(_select_drive.bind(i))
			sb.disabled = i > max_drive
			_src_bulbs.append({"idx": i, "rect": Rect2(cx - 9, rect.position.y - 22, 18, 18), "button": sb})
			var tb := _hit(_select_dst.bind(i))
			tb.disabled = i > max_drive
			_dst_bulbs.append({"idx": i, "rect": Rect2(cx - 9, rect.position.y + rect.size.y + 4, 18, 18), "button": tb})


var _close_btn: Button
var _mode_btn: Button


func _hit(cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.pressed.connect(cb)
	add_child(b)
	return b


# ----------------------------------------------------------------- Skala

func _sx() -> float: return size.x / VW
func _sy() -> float: return size.y / VH
func _V(x: float, y: float) -> Vector2: return Vector2(x * _sx(), y * _sy())
func _R(r: Rect2) -> Rect2: return Rect2(_V(r.position.x, r.position.y), Vector2(r.size.x * _sx(), r.size.y * _sy()))


func _layout() -> void:
	for a in _actions:
		var br: Rect2 = _R(a["rect"])
		a["button"].position = br.position
		a["button"].size = br.size
	for m in _menu_btns:
		m["button"].position = _V(m["x"] - 10, 47)
		m["button"].size = Vector2(60 * _sx(), 16 * _sy())
	for d in _drives:
		var dr: Rect2 = _R(d["rect"])
		d["button"].position = dr.position
		d["button"].size = dr.size
	for bulb in _src_bulbs + _dst_bulbs:
		var brb: Rect2 = _R(bulb["rect"])
		bulb["button"].position = brb.position
		bulb["button"].size = brb.size
	if _close_btn != null:
		_close_btn.position = _V(612, 6)
		_close_btn.size = Vector2(22 * _sx(), 14 * _sy())
	if _mode_btn != null:
		_mode_btn.position = _V(12, 68)
		_mode_btn.size = Vector2(128 * _sx(), 22 * _sy())
	if _service_btn != null:
		_service_btn.position = _V(492, 134)
		_service_btn.size = Vector2(132 * _sx(), 25 * _sy())
	queue_redraw()


# ----------------------------------------------------------------- Aktionen

func _select_drive(i: int) -> void:
	if _await_insert != "":       # Laufwerk anklicken = Diskettenwechsel bestätigen
		_confirm_insert()
		return
	_src_drive = i
	# Nicht im Kopiervorgang: Klick aufs Laufwerk öffnet die QUELLE-Auswahl
	# (Disketten anzeigen wie beim Booten).
	if not _copying:
		_open_source_picker()
	else:
		_status = "Quell-Laufwerk: DF%d:" % i if not pro else "Source drive: DF%d:" % i
	queue_redraw()


func _select_dst(i: int) -> void:
	if i < 0 or i > (0 if _single_drive else 1):
		return
	_dst_drive = i
	_status = "Ziel-Laufwerk: DF%d:" % i if not pro else "Destination drive: DF%d:" % i
	queue_redraw()


func _menu_noop(_l: String) -> void:
	pass


## Kopiermodus durchschalten (Klick aufs Modus-Feld, wie im Original).
func _cycle_mode() -> void:
	if _copying:
		return
	_mode = (_mode + 1) % MODE_NAMES.size()
	match _mode:
		0: _status = "DOSCOPY: fast backup, as it is." if pro \
			else "DOSCOPY: schnelle Kopie, wie sie ist."
		1: _status = "DOSCOPY+: rereads errors for the target; source stays unchanged." if pro \
			else "DOSCOPY+: Wiederhollesen/Fehlerkorrektur im Ziel; Quelle bleibt unveraendert."
		2: _status = "BAMCOPY+: copies used tracks only — faster." if pro \
			else "BAMCOPY+: kopiert nur belegte Spuren — schneller."
		3: _status = "NIBBLECOPY: raw copy, no DOS error check." if pro \
			else "NIBBLECOPY: Rohdaten-Kopie, keine DOS-Fehlerprüfung."
	queue_redraw()


func _contents() -> void:
	var cd := _content_disks()
	if cd.is_empty():
		_status = "No recorded disk." if pro else "Keine bespielte Diskette."
	else:
		_src_index = (_src_index + 1) % cd.size()
		_reset_diagnosis()
		_status = ("Source: %s" if pro else "Quelle: %s") % _source_disk().display_name()
	queue_redraw()


func _diskinfo() -> void:
	var d = _source_disk()
	_status = "DF%d: empty." % _src_drive if d == null else "DISK-INFO: %s" % d.display_name()
	queue_redraw()


func _verify() -> void:
	# PRÜFEN/CHECK: liest die Quelle Spur für Spur (nur Lese-Durchgänge,
	# nichts wird geschrieben) — wie im Original.
	if _copying:
		return
	if _source_disk() == null:
		_status = "DF%d: empty." % _src_drive if pro else "DF%d: leer." % _src_drive
		queue_redraw()
		return
	_begin_copy(false, true)


func _again() -> void:
	if not _copying: _start()


func _about() -> void:
	_status = "X-COPY Professional v6.7 — Homage (Cachet Software / QUASAR·LIBERTY)."
	queue_redraw()


func _last_action() -> void:
	# Standard: ZURÜCK = schließen · Professional: DEFAULT = zurücksetzen
	if pro:
		_status = "Defaults restored."
		queue_redraw()
	else:
		_close()


func _stop() -> void:
	AudioManager.stop_floppy()   # laufendes Rattern sofort beenden
	var pick := get_node_or_null("DiskPick")
	if pick != null:
		pick.queue_free()
	if _copying or _await_insert != "":
		_copying = false
		_await_insert = ""
		_phase = ""
		_result = {}
		_start_after_dest_pick = false
		# Die echte Inventartransaktion erfolgt erst nach dem letzten Verify-Schritt:
		# STOP lässt Quelle und Ziel deshalb garantiert unverändert.
		_status = "Aborted." if pro else "Abgebrochen."
		queue_redraw()


## UIManager fragt dies vor Aufstehen, HUD-Navigation und Reisen ab. Ein Picker
## während des Kopierens zählt ebenfalls als laufende Medienoperation.
func has_active_operation() -> bool:
	return _copying or _await_insert != ""


func active_operation_message() -> String:
	return "X-COPY arbeitet noch. Erst STOP drücken oder den Vorgang abschließen."


func _start() -> void:
	if _await_insert != "":       # wartet auf Diskettenwechsel → START bestätigt ihn
		_confirm_insert()
		return
	if _copying: return
	# Ein aus der Diskettenbox gestarteter Diagnoseauftrag bleibt Diagnose: START
	# darf nicht ploetzlich eine Leerdisk verlangen oder eine Kopie beginnen.
	if operation_kind == "check":
		if _source_disk() == null:
			_status = "Erst QUELLE fuer den Prueflauf einlegen."
			_open_source_picker()
		else:
			_begin_copy(false, true)
		queue_redraw()
		return
	# Quelle/Ziel werden jetzt per Disketten-Picker gewählt (wie beim Booten) —
	# hier nur prüfen, dass es überhaupt etwas zu kopieren gibt.
	if _content_disks().is_empty():
		_status = "No disk to copy." if pro else "Keine bespielte Diskette zum Kopieren da."
		queue_redraw(); return
	if DiskManager.blank_disks().is_empty():
		_status = "No blank disk available." if pro else "Keine Leerdiskette vorhanden — erst eine besorgen."
		queue_redraw(); return
	# Die Quelle wird bewusst VOR START geladen. Ihre Auswahl startet nicht mehr
	# heimlich die Lesephase und erzeugt dadurch keinen zweiten Quellenhinweis.
	if _src_chosen == null or not is_instance_valid(_src_chosen):
		_status = "Load SOURCE first." if pro else "Erst QUELLE laden, dann START drücken."
		_open_source_picker()
		queue_redraw()
		return
	# Mit DF1: liegen Quelle und Ziel gleichzeitig in den Laufwerken. START öffnet
	# einmalig die Zielwahl und beginnt nach deren Auswahl ohne Wechselpausen.
	if not _single_drive and (_dst_chosen == null or not is_instance_valid(_dst_chosen)):
		_start_after_dest_pick = true
		_open_dest_picker()
		return
	_begin_copy(false, false)


## Verlangt (nur bei EINEM Laufwerk) das Einlegen der Quelle bzw. der Leerdisk
## und pausiert die Sequenz, bis der Spieler bestätigt (Laufwerk anklicken / START).
## Mit externem Laufwerk oder im Demo-Modus läuft alles ohne Wechsel durch.
func _need_insert(which: String) -> bool:
	if not _single_drive or _demo:
		return false
	AudioManager.stop_floppy()     # laufendes Rattern beenden (Diskettenwechsel!)
	# Beim ERSTEN Mal die Diskette per Picker wählen; danach nur re-einlegen.
	if which == "source" and _src_chosen == null:
		_open_source_picker()
		return true
	if which == "dest" and _dst_chosen == null:
		_open_dest_picker()
		return true
	_await_insert = which
	_swap_blink = 0.0
	AudioManager.floppy_insert()   # das Auswurf-/Einlege-Klacken
	if which == "source":
		_status = ("Re-insert SOURCE, then click the drive."
			if pro else "Original wieder einlegen — dann Laufwerk anklicken.")
	else:
		_status = ("Re-insert BLANK, then click the drive."
			if pro else "Leerdiskette wieder einlegen — dann Laufwerk anklicken.")
	queue_redraw()
	return true


## Diskettenwechsel per Klick/START bestätigt (Disk schon gewählt).
func _confirm_insert() -> void:
	var which := _await_insert
	_await_insert = ""
	_resume_after_insert(which)


## Motor läuft an und die passende Phase startet (nach Picker ODER Re-Einlegen).
func _resume_after_insert(which: String) -> void:
	AudioManager.stop_floppy()
	AudioManager.floppy_insert()
	if which == "dest":
		_phase = "write"
		_gap = 0.7
		if _whole_disk_buffered():
			_status = ("WHOLE DISK BUFFERED · ONE WRITE PASS …" if pro \
				else "GESAMTE DISK GEPUFFERT · EIN SCHREIB-DURCHGANG …")
		else:
			_status = ("%s: writing %s …" if pro else "%s: schreibe %s …") % [
				MODE_NAMES[_mode], _source_name()]
	else:
		_phase = "read"
		_gap = 0.6
		_status = ("Reading pass %d/%d …" if pro
			else "Lese Durchgang %d/%d …") % [_pass_num, _pass_total]
	AudioManager.floppy_rattle()
	queue_redraw()


## Quelle wählen (bespielte Disketten wie beim Booten).
func _open_source_picker() -> void:
	if get_node_or_null("DiskPick") != null:
		return
	var p := DiskPicker.new()
	p.name = "DiskPick"
	var contract := _backup_contract()
	p.title = ("SCHRITT 2/3 · ROTE MASTERDISK EINLEGEN" if _space_copy_tutorial_active()
		else ("DIAGNOSE 1/2 · QUELLE EINLEGEN" if operation_kind == "check"
		else ("BACKUP 1/3 · MARKIERTE QUELLE EINLEGEN" if operation_kind == "backup" and not contract.is_empty()
		else "QUELLE einlegen - was kopieren?")))
	p.subtitle = ("ROT = geschuetzte Quelle · wird nur gelesen und bleibt bei dir" if _space_copy_tutorial_active()
		else ("PRUEFEN liest Track/CRC und meldet danach den physischen Folgeschritt" if operation_kind == "check"
		else (("AUFTRAG: genau >>%s<< - nicht alle Disks" % str(contract.get("source_name", "")))
			if operation_kind == "backup" and not contract.is_empty()
			else "Original-Diskette waehlen (wird gelesen)")))
	p.disks = _content_disks()
	var recommended := _space_master()
	p.recommended_uid = recommended.uid if recommended != null else str(contract.get("source_uid", ""))
	p.on_pick = func(d) -> void:
		_src_chosen = d
		_src_index = -1
		_reset_diagnosis()
		if _copying:
			_resume_after_insert("source")
		else:
			AudioManager.floppy_insert()
			_status = (("SOURCE loaded: %s — press START." if pro
				else "QUELLE geladen: %s — jetzt START drücken.") % d.display_name())
			queue_redraw()
	p.on_cancel = _stop
	add_child(p)


## ZIEL wählen — NUR Leerdisketten (gefilterter Dialog).
func _open_dest_picker() -> void:
	if get_node_or_null("DiskPick") != null:
		return
	var p := DiskPicker.new()
	p.name = "DiskPick"
	p.title = ("SCHRITT 2/3 · BLAUE LEERDISKETTE EINLEGEN" if _space_copy_tutorial_active()
		else "LEERDISKETTE einlegen — Ziel")
	p.subtitle = ("BLAU = neue Folgegeneration für Stefan · wird beschrieben" if _space_copy_tutorial_active()
		else "Nur leere Disketten (wird beschrieben)")
	p.disks = DiskManager.blank_disks()
	p.recommended_uid = p.disks[0].uid if _space_copy_tutorial_active() and not p.disks.is_empty() else ""
	p.on_pick = func(d) -> void:
		_dst_chosen = d
		if _start_after_dest_pick:
			_start_after_dest_pick = false
			_begin_copy(false, false)
		elif _copying:
			_resume_after_insert("dest")
		else:
			AudioManager.floppy_insert()
			_status = (("DESTINATION loaded: %s." if pro
				else "ZIEL geladen: %s.") % d.display_name())
			queue_redraw()
	p.on_cancel = _stop
	add_child(p)


func _source_name() -> String:
	return "DEMO" if _demo or _source_disk() == null else _source_disk().display_name()


## Demo-Kopiervorgang (Proof/Render): volle Sequenz ohne echte Disketten.
func demo_start() -> void:
	_begin_copy(true, false)


func _begin_copy(demo: bool, check_only: bool) -> void:
	_demo = demo
	_check_only = check_only
	_copying = true
	_phase = "read"
	_track = 0
	_read_done = 0
	_write_done = 0
	_err_cells = []
	if check_only and not demo:
		var preview: Dictionary = DiskManager.diagnose_disk(_source_disk())
		if not bool(preview.get("readable", false)):
			_err_cells = (preview.get("error_tracks", []) as Array).duplicate()
	_result = {}
	_time = 0.0
	_accum = 0.0
	_gap = 0.6   # Spin-up des Quell-Laufwerks (Motor läuft an, Kopf sucht Spur 0)
	_pass_num = 1
	_pass_total = int(ceil(float(TRACKS) / float(_tracks_per_pass())))
	_pass_to = mini(_tracks_per_pass(), TRACKS)
	# BAMCOPY+: nur belegte Spuren — unbelegte bleiben leer und kosten kaum Zeit.
	_bam_skip = {}
	if _mode == 2 and not check_only:
		var rng := RandomNumberGenerator.new()
		var src = _source_disk()
		rng.seed = 1 if src == null else hash(src.display_name())
		for t in range(TRACKS):
			# hintere Spuren sind auf halbvollen Disketten öfter unbelegt
			var p_empty := 0.06 + 0.5 * float(t) / float(TRACKS)
			if rng.randf() < p_empty * 0.55:
				_bam_skip[t] = true
	_await_insert = ""
	if check_only:
		_status = "CHECK: reading all tracks …" if pro else "PRÜFEN: lese alle Spuren …"
	elif _whole_disk_buffered():
		_status = ("WHOLE DISK BUFFER · ONE PASS · reading %s …" if pro \
			else "GESAMTE DISK IM RAM · EIN DURCHGANG · lese %s …") % _source_name()
	else:
		_status = ("%s: copying %s …" if pro else "%s: kopiere %s …") % [MODE_NAMES[_mode], _source_name()]
	# Die bereits im Quellen-Picker geladene Diskette liegt in DF0:. START lässt
	# nur den Motor anlaufen; ein redundantes »Original wieder einlegen« entfällt.
	AudioManager.floppy_rattle()
	queue_redraw()


## Eine Spur der Sequenz abarbeiten (vom _process-Takt getrieben).
## Wie im Original erscheint die grüne „0" beim LESEN der Spur; Verify-Fehler
## (rote „8") tauchen erst beim SCHREIBEN auf. BAMCOPY+ überspringt unbelegte
## Spuren, DOSCOPY+/BAMCOPY+ reparieren Fehler-Spuren (rote Ziffer → grün).
func _step_track() -> void:
	if _phase == "read":
		while _read_done < _pass_to and _bam_skip.has(_read_done):
			_read_done += 1
		if _read_done < _pass_to:
			_track = _read_done
			_read_done += 1
			if _track % 10 == 3:
				AudioManager.floppy_rattle()   # laufendes Kopf-Rattern
			if _whole_disk_buffered():
				_status = ("Reading track %02d · WHOLE DISK · ONE PASS · READ %d%% · TOTAL %d%%" if pro \
					else "Lese Spur %02d · GESAMTE DISK · EIN DURCHGANG · LESEN %d%% · GESAMT %d%%") \
					% [_track, _phase_progress(), _progress()]
			else:
				_status = ("Reading track %02d   pass %d/%d   %d%%" if pro
					else "Lese Spur %02d   Durchgang %d/%d   %d%%") % [_track, _pass_num, _pass_total, _progress()]
		if _read_done >= _pass_to:
			if _check_only:
				if _pass_to >= TRACKS:
					_finish_copy()
				else:
					_next_pass()
			else:
				# Puffer voll → LEER-Diskette (Ziel) einlegen lassen, dann schreiben.
				# Beim ERSTEN Schreiben passiert die echte Kopie.
				if not _need_insert("dest"):
					_phase = "write"
					_gap = 0.7   # Ziel-Laufwerk läuft an
					AudioManager.floppy_rattle()
	else:
		while _write_done < _pass_to and _bam_skip.has(_write_done):
			_write_done += 1
		if _write_done < _pass_to:
			_track = _write_done
			_write_done += 1
			if _track % 10 == 7:
				AudioManager.floppy_rattle()   # laufendes Kopf-Rattern
			if _whole_disk_buffered():
				_status = ("Writing track %02d · WHOLE DISK · ONE PASS · WRITE %d%% · TOTAL %d%%" if pro \
					else "Schreibe Spur %02d · GESAMTE DISK · EIN DURCHGANG · SCHREIBEN %d%% · GESAMT %d%%") \
					% [_track, _phase_progress(), _progress()]
			else:
				_status = ("Writing track %02d   pass %d/%d   %d%%" if pro
					else "Schreibe Spur %02d   Durchgang %d/%d   %d%%") % [_track, _pass_num, _pass_total, _progress()]
			if _track in _err_cells:
				if _mode == 1 or _mode == 2:
					# DOSCOPY+/BAMCOPY+: „repairs errors" — nachlesen, dann ok
					_gap = 0.5
					_err_cells.erase(_track)
					_status = ("Verify error track %02d — repaired." if pro
						else "Verify-Fehler Spur %02d — repariert.") % _track
				else:
					_gap = 0.35   # 3 Wiederholversuche des Originals
					_status = ("Verify error on track %02d!" if pro
						else "Verify-Fehler auf Spur %02d!") % _track
		if _write_done >= _pass_to:
			if _pass_to >= TRACKS:
				_finish_copy()
			else:
				_next_pass()


func _next_pass() -> void:
	_pass_num += 1
	_pass_to = mini(_pass_to + _tracks_per_pass(), TRACKS)
	# Nächstes Stück: beim Kopieren muss die ORIGINAL-Diskette wieder rein
	# (PRÜFEN liest nur → Quelle bleibt drin). Externes Laufwerk: kein Wechsel.
	if _check_only or not _need_insert("source"):
		_phase = "read"
		_gap = 0.8   # Kopf zurück zur Quelle (voller Rücklauf)
		AudioManager.floppy_rattle()


## Die echte Kopie ausführen (einmalig, zu Beginn der ersten Schreibphase).
## Bei Fehlern werden 2-3 Verify-Fehler-Spuren (Code „8") bestimmt, die beim
## Schreiben rot auflaufen. NIBBLECOPY kennt keine DOS-Prüfung — dort sieht
## man Fehler schlicht nicht (wie im Original).
func _commit_backup() -> void:
	var src = _source_disk()
	var dst = _dst_chosen if (_dst_chosen != null and is_instance_valid(_dst_chosen)) else null
	if dst == null:
		var blanks: Array = DiskManager.blank_disks()
		dst = blanks[0] if not blanks.is_empty() else null
	if src == null or dst == null:
		return
	# X-COPY ist der kulturelle Kopierweg: Software-ID, Herkunft, Generation
	# und ein eventuell vorhandenes Szene-Release müssen erhalten bleiben.
	# Das generische backup_disk() bleibt ausschließlich für Archivkopien.
	_result = DiskManager.backup_disk(src, dst) if operation_kind == "backup" \
		else DiskManager.copy_disk(src, dst)
	if operation_kind == "copy" and bool(_result.get("ok", false)):
		AchievementManager.note("made_copy")
	if not bool(_result.get("ok", true)) and _mode != 3:
		var t := randi_range(3, TRACKS - 12)
		_err_cells = [t, t + 1, t + randi_range(3, 9)]
		for e in _err_cells:
			_bam_skip.erase(e)   # Fehler-Spuren sind belegt — nie überspringen


func _finish_copy() -> void:
	_copying = false
	_phase = ""
	_track = TRACKS - 1
	if _check_only:
		_result = DiskManager.check_disk(_source_disk()) if not _demo else {"ok": true}
		_err_cells = (_result.get("error_tracks", []) as Array).duplicate()
		_build_diagnosis_result()
		_status = _diagnosis_summary()
		if not _demo:
			UIManager.toast(_status)
		queue_redraw()
		return
	if not _demo:
		_commit_backup()
	if _demo or _result.is_empty():
		_status = "Verify ok — done." if pro else "Verify ok — fertig."
		queue_redraw()
		return
	_status = str(_result.get("text", ""))
	UIManager.toast(str(_result.get("text", "")))
	# Achims X-COPY-Pro-Auftrag verlangt ausdrücklich eine ganze Disk in EINEM
	# Speicherdurchgang. Eine technisch erfolgreiche Zwei-Pass-Kopie auf dem
	# nackten 512-KB-A500 darf diese Fähigkeit nicht vortäuschen.
	if operation_kind == "copy" and bool(_result.get("ok", false)) and not pro \
			and not is_sommer_copy() \
			and _whole_disk_buffered():
		QuestManager.note_action("xcopy_standard_verified")
	if operation_kind == "copy" and bool(_result.get("ok", false)) \
			and is_sommer_copy() and _whole_disk_buffered():
		QuestManager.note_action("sommer_copy_prototype_verified")
	if operation_kind == "copy" and bool(_result.get("ok", false)) \
			and bool(_result.get("tutorial_space_copy", false)):
		UIManager.open_copy_tutorial("complete")
	_dst_chosen = null
	queue_redraw()


func _reset_diagnosis() -> void:
	_diagnosis = {}
	_service_action = ""
	_service_label = ""
	if _service_btn != null:
		_service_btn.disabled = true


func _build_diagnosis_result() -> void:
	_reset_diagnosis()
	var disk: Disk = _source_disk() as Disk
	if disk == null:
		return
	var physical: Dictionary = DiskManager.diagnose_disk(disk)
	_diagnosis = {
		"source": disk.display_name(),
		"tracks_ok": bool(_result.get("ok", false)),
		"code": str(_result.get("code", physical.get("code", "missing"))),
		"condition": int(physical.get("condition", disk.condition)),
		"virus_checked": false,
	}
	if not bool(physical.get("readable", false)):
		# 0 % ist mechanisch tot: weder das Stabilisierungs- noch das Rettungsspiel
		# darf als falsches Erfolgsversprechen angeboten werden.
		_service_action = ""
		_service_label = ""
	elif not bool(_result.get("ok", false)) and disk.condition < 75:
		_service_action = "rescue"
		_service_label = "DATEN RETTEN"
	elif disk.condition < 95:
		_service_action = "repair"
		_service_label = "MEDIUM REPARIEREN"
	else:
		_service_action = "backup"
		_service_label = "BACKUP STARTEN"
	if _service_btn != null:
		_service_btn.disabled = _service_action.is_empty()


func _diagnosis_summary() -> String:
	return Diagnosis.summary(_diagnosis, _result, _service_action)

func workflow_title() -> String:
	if not _diagnosis.is_empty():
		return "DIAGNOSE 2/2 · %s" % str(_diagnosis.get("source", "DISKETTE")).to_upper().left(32)
	if operation_kind == "check":
		return "MEDIENDIAGNOSE 1/2 · TRACK/CRC PRUEFEN"
	if operation_kind == "backup":
		var contract := _backup_contract()
		if not contract.is_empty():
			return "BACKUP-AUFTRAG · 1 QUELLE + 1 LEERDISK · NICHT ALLE"
		if QuestManager.is_active("q_disk_archive") and QuestManager.stage("q_disk_archive") == 0:
			return "ALEX' ARCHIV · %d/3 VERSCHIEDENE QUELLEN" % QuestManager.action_count("q_disk_archive", "backup_disk")
		if QuestManager.is_active("q_y2k_prep"):
			return "Y2K-VORSORGE · GENAU 1 WICHTIGE QUELLE"
		return "ARCHIV-BACKUP · 1 QUELLE + 1 ECHTE LEERDISK"
	if is_sommer_copy():
		return ("SOMMER COPY 92 · PROTOTYPTEST · EIN PASS"
			if is_sommer_copy_prototype() else
			"SOMMER COPY 92 · EIN PASS · VERIFY · EIGENBAU")
	return "X-COPY · QUELLE LESEN · ZIEL SCHREIBEN · VERIFY"


func workflow_detail() -> String:
	if not _diagnosis.is_empty():
		return _diagnosis_summary()
	if operation_kind == "check":
		return "Nur Diagnose: keine Kopie, keine Viruspruefung. Danach erscheint der passende Folgeschritt."
	if operation_kind == "backup":
		var contract := _backup_contract()
		if not contract.is_empty():
			var expected := str(contract.get("source_uid", ""))
			var chosen: Disk = _source_disk() as Disk
			if chosen != null and not expected.is_empty() and chosen.uid != expected:
				return "FALSCHE QUELLE FUER DIE NOTIZ · erwartet: %s" % str(contract.get("source_name", "?"))
			return "AUFTRAGSQUELLE: %s · Ziel: 1 leere DD · Abschluss: Verify" % str(contract.get("source_name", "?"))
		if QuestManager.is_active("q_disk_archive") and QuestManager.stage("q_disk_archive") == 0:
			return "Jede Quelle nur einmal; fuer jede eine eigene leere DD-Disk. Insgesamt genau drei."
	if is_sommer_copy():
		return "Kanalwache aus Sommer BASIC: ganze DD puffern, schreiben und Spur fuer Spur verifizieren."
	return "Quelle bleibt erhalten; nur die ausgewaehlte Leerdiskette wird als Archivkopie beschrieben."


func _backup_contract() -> Dictionary:
	return TaskManager.real_backup_contract() if operation_kind == "backup" else {}


func _run_service_action() -> void:
	if _service_action.is_empty() or _source_disk() == null or _copying:
		return
	var disk: Disk = _source_disk() as Disk
	var action := _service_action
	AudioManager.stop_floppy()
	name = "XCopyClosing"
	queue_free()
	match action:
		"repair": UIManager.call_deferred("open_disk_repair", disk)
		"rescue": UIManager.call_deferred("open_disk_rescue", disk)
		"backup": UIManager.call_deferred("open_disk_copy", disk, "backup")


func _close() -> void:
	if has_active_operation():
		_status = "Press STOP first." if pro else "Erst STOP drücken oder Kopie abschließen."
		queue_redraw()
		return
	AudioManager.stop_floppy()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_node_or_null("DiskPick") != null:
			return   # der offene Disketten-Picker behandelt Esc (Abbrechen) selbst
		get_viewport().set_input_as_handled()
		if has_active_operation():
			_status = "Press STOP first." if pro else "Erst STOP drücken oder Kopie abschließen."
			queue_redraw()
			return
		AudioManager.stop_floppy()
		queue_free()


func _process(delta: float) -> void:
	if not _copying: return
	if _await_insert != "":
		# Wartet auf Diskettenwechsel — Zeit läuft weiter (man kramt ja), aber
		# es wird nichts gelesen/geschrieben. Der Hinweis blinkt.
		_time += delta
		_swap_blink += delta
		queue_redraw()
		return
	_time += delta
	if _gap > 0.0:
		# Phasenwechsel: Kopf repositioniert, Laufwerk läuft an
		_gap -= delta
		queue_redraw()
		return
	_accum += delta
	# REALISTISCHES Tempo (User-Wunsch: langsamer): ein echter Amiga brauchte
	# pro Spur mehrere Umdrehungen; eine ganze Diskette dauerte rund eine Minute
	# je Durchgang. Schreiben ist LANGSAMER als Lesen (schreiben + verifizieren).
	# Professional kopiert etwas flotter.
	var tick: float = (0.16 if pro else 0.24) if _phase == "read" else (0.26 if pro else 0.38)
	if _mode == 3:
		tick *= 1.6   # NIBBLECOPY: Rohdaten = mehr Bytes pro Spur, langsamer
	elif _mode != 0 and _phase == "write":
		tick *= 1.15  # DOSCOPY+/BAMCOPY+: Verify-Aufwand beim Schreiben
	while _accum >= tick and _copying and _gap <= 0.0:
		_accum -= tick
		_step_track()
	queue_redraw()



# ----------------------------------------------------------------- Zeichnen
func _draw() -> void:
	XCopyDraw.render(self)
