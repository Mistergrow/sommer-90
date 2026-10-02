extends WbApp
## VIRUS-CHECKER — Bootblock-Virenwächter im Stil der Amiga-Ära (Homage). Prüft
## deine Disketten auf (fiktive!) Bootblock-Viren, zeigt eine animierte Prüfung
## und lässt Funde „entfernen". Passt zur Disketten-Tauschkultur (Kopien konnten
## sich was einfangen).

const VISIBLE := 11
const ROW_H := 14.0
const LIST_Y := 150.0
const TRACK_TICK_SECONDS := 0.006
const TRACKS_PER_DISK := 79
const ALEX_RISKY_QUEST := "q_alex_risky_1992"
const ALEX_RISKY_UID_FLAG := "alex_risky_disk_uid"
const ALEX_RISKY_MEMORY := "1992 von Alex als riskante Wühlkisten-Disk bekommen"

var _results: Dictionary = {}   # disk_name -> "" | "clean" | "virus:<name>"
var _scanning := false
var _scan_i := 0
var _scan_track := 0
var _scan_time := 0.0
var _scroll := 0


func _init() -> void:
	app_title = Loc.t("ui.virus_checker_app.title", "VIRUS-CHECKER  V6.10   ·   BOOTBLOCK-WÄCHTER")
	app_bg = Color8(14, 20, 16)
	app_bar = Color8(30, 70, 44)
	app_accent = Color8(110, 220, 130)


func _build_app() -> void:
	# Heilt alte, bereits vollständig geprüfte Notizen beim ersten Öffnen und
	# bindet ungescannte Legacy-Aufträge an eine sichtbare physische Diskette.
	VirusManager.reconcile_scare_task()
	add_button(Loc.t("ui.virus_checker_app.scan_all", "ALLE PRÜFEN"), Rect2(20, 118, 120, 22), _scan_all, Color8(150, 230, 160))
	add_button(Loc.t("ui.virus_checker_app.remove", "ENTFERNEN"), Rect2(148, 118, 110, 22), _clean_all, Color8(240, 200, 90))
	add_button(Loc.t("ui.virus_checker_app.cancel", "ABBRECHEN"), Rect2(266, 118, 110, 22), _abort, Color8(230, 130, 120))
	_rebuild_rows()


func _rebuild_rows() -> void:
	# Nur Listenzeilen neu (Aktions-Buttons bleiben) — einfach alles neu:
	clear_widgets()
	add_button(Loc.t("ui.virus_checker_app.scan_all", "ALLE PRÜFEN"), Rect2(20, 118, 120, 22), _scan_all, Color8(150, 230, 160))
	add_button(Loc.t("ui.virus_checker_app.remove", "ENTFERNEN"), Rect2(148, 118, 110, 22), _clean_all, Color8(240, 200, 90))
	add_button(Loc.t("ui.virus_checker_app.cancel", "ABBRECHEN"), Rect2(266, 118, 110, 22), _abort, Color8(230, 130, 120))
	var disk_list := DiskManager.media_disks()
	_scroll = clampi(_scroll, 0, maxi(0, disk_list.size() - VISIBLE))
	for i in mini(VISIBLE, disk_list.size() - _scroll):
		var idx := _scroll + i
		add_button("", Rect2(20, LIST_Y + i * ROW_H, 600, ROW_H), _scan_one.bind(idx), Color.WHITE, false)
	if disk_list.size() > VISIBLE:
		add_button("▲", Rect2(600, LIST_Y, 20, 20), _scroll_up, app_accent)
		add_button("▼", Rect2(600, LIST_Y + (VISIBLE - 1) * ROW_H, 20, 20), _scroll_down, app_accent)
	_layout()


func _scroll_up() -> void:
	_scroll = maxi(0, _scroll - 1)
	_rebuild_rows()


func _scroll_down() -> void:
	_scroll += 1
	_rebuild_rows()


# ----------------------------------------------------------------- Logik

## Prüft eine Diskette gegen den ECHTEN Bootblock-Zustand (Disk.virus), macht ihn
## sichtbar (checked=true) und merkt das Ergebnis je uid.
func _scan_disk(d) -> bool:
	var physical: Dictionary = DiskManager.diagnose_disk(d)
	if d == null or d not in DiskManager.disks \
			or not bool(physical.get("readable", false)):
		if d != null:
			_results[str(d.uid)] = "unreadable"
		return false
	d.checked = true
	_results[d.uid] = ("virus:" + VirusManager.virus_name(d)) if d.virus else "clean"
	VirusManager.note_disk_scanned(d)
	if QuestManager.is_active(ALEX_RISKY_QUEST) and str(d.uid) == _alex_risky_disk_uid():
		QuestManager.note_action("scan_risky_disk")
	return true


## Alte Spielstände aus der Zeit vor der UID-Bindung besitzen den Quest-Flag
## noch nicht. Ausschließlich Alex' eindeutige Herkunftsnotiz darf die Bindung
## nachholen; irgendeine andere unbeschriftete Diskette reicht ausdrücklich nicht.
func _alex_risky_disk_uid() -> String:
	var captured := str(GameManager.flags.get(ALEX_RISKY_UID_FLAG, ""))
	if not captured.is_empty():
		return captured
	for candidate in DiskManager.media_disks():
		if str(candidate.template_id) == "mystery_unlabeled" \
				and str(candidate.memory) == ALEX_RISKY_MEMORY:
			GameManager.flags[ALEX_RISKY_UID_FLAG] = str(candidate.uid)
			return str(candidate.uid)
	return ""


func _found_count() -> int:
	var n := 0
	for k in _results:
		if str(_results[k]).begins_with("virus:"):
			n += 1
	return n


func _scan_all() -> void:
	_results.clear()
	_scanning = true
	_scan_i = 0
	_scan_track = 0
	_scan_time = 0.0


func _scan_one(idx: int) -> void:
	var disk_list := DiskManager.media_disks()
	if idx < 0 or idx >= disk_list.size():
		return
	var d = disk_list[idx]
	if not _scan_disk(d):
		UIManager.toast(Loc.t("ui.virus_checker_app.diskette_ist_mechanisch_nicht_mehr_lesbar", "Die Diskette ist mechanisch nicht mehr lesbar."))
	elif d.virus:
		UIManager.toast(VirusManager.reveal_line(d))   # SCA-Bootblock-Gruß


func _abort() -> void:
	_scanning = false


## Gefundene Viren wirklich entfernen (VirusManager.clean → Disk.virus=false).
func _clean_all() -> void:
	var n := 0
	for d in DiskManager.media_disks():
		if str(_results.get(d.uid, "")).begins_with("virus:"):
			if VirusManager.clean(d):
				n += 1
			_results[d.uid] = "clean"
	if n > 0:
		UIManager.toast(Loc.t("ui.virus_checker_app.virenwachter_d_virus_viren_entfernt_bootblocke", "Virenwächter: %d Virus/Viren entfernt, Bootblöcke neu geschrieben.") % n)
	else:
		UIManager.toast(Loc.t("ui.virus_checker_app.nichts_zu_entfernen_erst_alle_prufen", "Nichts zu entfernen — erst »ALLE PRÜFEN«."))


func _app_process(delta: float) -> void:
	if not _scanning:
		return
	_scan_time += delta
	# Zeit akkumulieren statt delta pro Frame abzurunden. Bei 144/240-Hz-
	# Displays war int(delta / 0.006) dauerhaft 0 und der Scan blieb stehen.
	var elapsed_ticks := int(_scan_time / TRACK_TICK_SECONDS)
	if elapsed_ticks <= 0:
		return
	_scan_time -= float(elapsed_ticks) * TRACK_TICK_SECONDS
	_scan_track += elapsed_ticks
	while _scan_track >= TRACKS_PER_DISK and _scanning:
		_scan_track -= TRACKS_PER_DISK
		var disk_list := DiskManager.media_disks()
		if _scan_i < disk_list.size():
			_scan_disk(disk_list[_scan_i])
			_scan_i += 1
		if _scan_i >= disk_list.size():
			_scanning = false
			VirusManager.finish_full_scan()
			var unreadable := _unreadable_count()
			UIManager.toast(Loc.t("ui.virus_checker_app.virenprufung_fertig_d_diskette_n_d", "Virenprüfung fertig: %d Diskette(n), %d Virus/Viren, %d nicht lesbar.") % [
				DiskManager.media_count(), _found_count(), unreadable])


func _unreadable_count() -> int:
	var count := 0
	for result: Variant in _results.values():
		if str(result) == "unreadable":
			count += 1
	return count


# ----------------------------------------------------------------- Zeichnen

func _content(font: Font) -> void:
	# Kopf
	rect(14, 24, VW - 28, 62, Color8(8, 16, 12))
	rect_line(14, 24, VW - 28, 62, app_accent)
	text(font, Loc.t("ui.virus_checker_app.watcher_active", "BOOTBLOCK-WÄCHTER aktiv"), 24, 42, 13, app_accent)
	text(font, Loc.t("ui.virus_checker_app.signature_note", "512 Bootblock-Signaturen + Lesbarkeit · getrennt vom X-COPY Track-Verify"), 24, 58, 10, Color8(150, 200, 160))
	# Scan-Status/Fortschritt
	if _scanning:
		var scanning_disks := DiskManager.media_disks()
		var nm := "?"
		if _scan_i < scanning_disks.size():
			var scanning_disk = scanning_disks[_scan_i]
			if _is_alex_quest_disk(scanning_disk):
				nm = Loc.t("ui.virus_checker_app.alex_quest_disk", "ALEX' DISK · AUFTRAG")
			elif _is_scare_task_disk(scanning_disk):
				nm = Loc.t("ui.virus_checker_app.virus_suspicion", "VIRUS-VERDACHT · %s") % scanning_disk.display_name()
			else:
				nm = scanning_disk.display_name()
		text(font, Loc.t("ui.virus_checker_app.scanning_track", "Prüfe: %s  ·  Track %02d/79") % [nm, _scan_track], 24, 76, 11, Color8(240, 220, 120))
		rect(360, 68, 250, 10, Color8(10, 20, 14))
		rect(360, 68, 250.0 * (float(_scan_i) / maxf(1.0, float(scanning_disks.size()))), 10, app_accent)
	else:
		var found := 0
		for k in _results:
			if str(_results[k]).begins_with("virus:"): found += 1
		var msg := Loc.t("ui.virus_checker_app.ready_hint", "Bereit. »ALLE PRÜFEN« oder eine Diskette anklicken.")
		if not _results.is_empty():
			var unreadable := _unreadable_count()
			if unreadable > 0:
				msg = Loc.t("ui.virus_checker_app.result_unreadable", "Ergebnis: %d Virus/Viren · %d Diskette(n) nicht lesbar.") % [
					found, unreadable]
			else:
				msg = Loc.t("ui.virus_checker_app.result_found", "Ergebnis: %d Virus/Viren gefunden.") % found if found > 0 \
					else Loc.t("ui.virus_checker_app.all_clean", "Alles sauber. Keine Viren.")
		text(font, msg, 24, 76, 11, Color8(230, 120, 110) if found > 0 else Color8(150, 210, 160))

	# Diskettenliste mit Status
	rect(14, LIST_Y - 8, VW - 28, VISIBLE * ROW_H + 12, Color8(8, 16, 12))
	rect_line(14, LIST_Y - 8, VW - 28, VISIBLE * ROW_H + 12, Color8(50, 90, 60))
	text(font, Loc.t("ui.virus_checker_app.disks_count", "DISKETTEN (%d)") % DiskManager.media_count(), 20, LIST_Y - 12, 9, app_accent)
	var visible_disks := DiskManager.media_disks()
	for w in _widgets:
		if w.get("auto_draw", true):
			continue
		var r: Rect2 = w["rect"]
		var i := int((r.position.y - LIST_Y) / ROW_H)
		var idx := _scroll + i
		if idx >= visible_disks.size():
			continue
		var d = visible_disks[idx]
		var is_alex_target := _is_alex_quest_disk(d)
		var is_scare_target := _is_scare_task_disk(d)
		var nm: String = Loc.t("ui.virus_checker_app.alex_quest_disk_star", "★ ALEX' DISK · AUFTRAG") if is_alex_target \
			else (Loc.t("ui.virus_checker_app.virus_suspicion_star", "★ VIRUS-VERDACHT · %s") % d.display_name()).left(38) if is_scare_target \
			else d.display_name()
		if is_alex_target or is_scare_target:
			rect(r.position.x, r.position.y, r.size.x, ROW_H - 1, Color8(48, 38, 12))
		if widget_hovered(w):
			rect(r.position.x, r.position.y, r.size.x, ROW_H - 1, Color8(20, 34, 24))
		if is_alex_target or is_scare_target:
			rect_line(r.position.x, r.position.y, r.size.x, ROW_H - 1, Color8(238, 194, 72))
		var res: String = str(_results.get(d.uid, ""))
		var status := Loc.t("ui.virus_checker_app.click_to_scan", "ANKLICKEN / PRÜFEN") if is_alex_target or is_scare_target else "—"
		var col: Color = Color8(238, 194, 72) if is_alex_target or is_scare_target \
			else Color8(140, 160, 150)
		if res == "clean":
			status = Loc.t("ui.virus_checker_app.clean", "✔ sauber"); col = Color8(120, 220, 140)
		elif res.begins_with("virus:"):
			status = Loc.t("ui.virus_checker_app.virus_found", "⚠ VIRUS: %s") % VirusManager.virus_name(d); col = Color8(240, 110, 100)
		elif res == "unreadable":
			status = Loc.t("ui.virus_checker_app.unreadable", "✖ NICHT LESBAR"); col = Color8(230, 150, 90)
		text(font, nm, r.position.x + 6, r.position.y + 11, 10, Color8(200, 214, 206))
		text(font, status, r.position.x + 380, r.position.y + 11, 10, col)

	text(font, Loc.t("ui.virus_checker_app.footer", "Fiktive Viren — nur Zeitkolorit. Esc = zurück."), 20, VH - 8, 9, Color8(110, 150, 120))


func _is_alex_quest_disk(d) -> bool:
	if not QuestManager.is_active(ALEX_RISKY_QUEST):
		return false
	var target_uid := _alex_risky_disk_uid()
	return not target_uid.is_empty() and str(d.uid) == target_uid


func _is_scare_task_disk(d) -> bool:
	return VirusManager.is_scare_disk(d)
