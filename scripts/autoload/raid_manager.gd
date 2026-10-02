extends Node
## RaidManager — das Razzia-Risiko des Kopien-Handels (User-Design 13.7.2026).
##
## Kopien-Umsatz wird PRO JAHR verfolgt. Die Grenze STEIGT mit der Ära
## (data/raid.json: 1990 → 10.000 DM … 1998 → 30.000 DM — mehr Geld im
## Umlauf, größere Szene). Auf dem Weg dorthin gibt es GESTUFTE Warnzeichen
## (50 % Gerücht → 75 % konkrete Warnung → 90 % dringender Zettel), dann die
## RAZZIA: Amiga + Bargeld-Anteil beschlagnahmt, zurück zum Karton
## (Aufbau-Flags). 1. Vergehen: Kopien werden BLANK gelöscht (Disketten
## bleiben) · 2.: Kopien komplett weg · 3.+: höherer Bargeld-Anteil.
## Originale/Freunde/Wissen bleiben IMMER (Zeit-Bibel: Rückschlag, keine
## Spielstand-Strafe). Nach der 2. Razzia nennt der Anwalt die aktuelle Grenze.
##
## UI-Anbindung (Notizblock/HUD): risk_ratio() 0..1 und risk_level() 0..3.
signal raid_happened
signal risk_changed

const CONFIG := "res://data/raid.json"

var year_revenue := 0    # Kopien-Umsatz im laufenden Jahr (DM)
var raids := 0           # wie oft wurde der Spieler schon erwischt?
var warn_level := 0      # höchste bereits gezeigte Warnstufe dieses Jahr (0..n)

var _cfg: Dictionary = {}


func _ready() -> void:
	_load_config()
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and not tm.year_changed.is_connected(_on_year_changed):
		tm.year_changed.connect(_on_year_changed)


func _load_config() -> void:
	if not _cfg.is_empty():
		return
	if FileAccess.file_exists(CONFIG):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if parsed is Dictionary:
			_cfg = parsed
	if _cfg.is_empty():   # Fallback: Verhalten wie die erste Ausbaustufe
		_cfg = {"eras": [{"from": 1990, "raid_at": 10000}],
			"warnings": [{"at": 0.5, "text": Loc.t("sys.raid_manager.man_munkelt_gvu_schaut_sich_um", "Man munkelt, die GVU schaut sich um …")}],
			"cash_seize": [0.5]}


func _on_year_changed(_year: int) -> void:
	year_revenue = 0
	warn_level = 0
	risk_changed.emit()


## Razzia-Grenze der AKTUELLEN Ära (steigt über die Dekade, data/raid.json).
func raid_at() -> int:
	var best := 10000
	for era: Dictionary in _cfg.get("eras", []):
		if TimeManager.year >= int(era.get("from", 1990)):
			best = int(era.get("raid_at", best))
	return best


## Risiko-Anteil 0..1 (Umsatz vs. Ära-Grenze) — für Notizblock/HUD.
func risk_ratio() -> float:
	return clampf(float(year_revenue) / float(raid_at()), 0.0, 1.0)


## Risiko-Stufe 0..3 = wie viele Warnschwellen überschritten sind (Anzeige).
func risk_level() -> int:
	var level := 0
	for w: Dictionary in _cfg.get("warnings", []):
		if risk_ratio() >= float(w.get("at", 1.0)):
			level += 1
	return level


## Jeden Kopien-Verkauf melden (DealerManager.deliver, CopyTradeManager.sell).
func track_sale(amount: int) -> void:
	if amount <= 0 or GameManager.state != GameManager.State.PLAYING:
		return
	year_revenue += amount
	if year_revenue >= raid_at():
		_raid()
		return
	# Gestufte Warnzeichen: jede Schwelle genau einmal pro Jahr, in Reihenfolge.
	var warnings: Array = _cfg.get("warnings", [])
	while warn_level < warnings.size() \
			and risk_ratio() >= float((warnings[warn_level] as Dictionary).get("at", 1.0)):
		UIManager.toast(str((warnings[warn_level] as Dictionary).get("text", "")))
		warn_level += 1
	risk_changed.emit()


## Die Razzia: Beschlagnahmung statt Spielstand-Strafe — der Spieler packt
## wieder einen Karton aus, aber Originale/Freunde/Wissen bleiben.
## 1. Vergehen: Kopien werden BLANK gelöscht (Disketten bleiben) ·
## 2.: Kopien komplett MITGENOMMEN · 3.+: zusätzlich höherer Bargeld-Anteil.
func _raid() -> void:
	raids += 1
	year_revenue = 0
	warn_level = 0
	# 1) Kopien: beim 1. Mal blank gelöscht, ab dem 2. Mal beschlagnahmt.
	var seized := 0
	for disk in DiskManager.disks.duplicate():
		if str(disk.provenance) != "copy" or str(disk.content_type) == "leer":
			continue   # Originale und Leerdisketten fassen sie nicht an
		# Ein laufender Storyauftrag darf durch einen Zufalls-Raid niemals seine
		# einzige physische Pflichtdisk verlieren. Sie bleibt als Beweisstück beim
		# Spieler; alle normalen Kopien folgen weiterhin der Razzia-Regel.
		if bool(QuestManager.disk_requirement(disk).get("required", false)):
			continue
		seized += 1
		if raids <= 1:
			_wipe(disk)
		else:
			DiskManager.remove_disk(disk)
	# 2) Bargeld-Anteil weg (Erlöse) — steigt mit jedem Vergehen (cash_seize).
	var seize: Array = _cfg.get("cash_seize", [0.5])
	var factor := float(seize[clampi(raids - 1, 0, seize.size() - 1)])
	var cash := int(PlayerStats.geld * factor)
	if cash > 0:
		PlayerStats.spend_money(cash)
	# 3) Der Amiga wird mitgenommen: zurück zum Karton (Aufbau-Flags zurücksetzen).
	#    Ein neues Gerät steht als Karton bereit (Papa/Erspartes — erzählt im Info).
	for fl: String in ["starter_carton_opened", "amiga_placed", "monitor_placed", "booted_amiga"]:
		GameManager.flags.erase(fl)
	UIManager.reset_computer()
	# 4) Eltern sind entsetzt.
	PlayerStats.change_stat("eltern_toleranz", -30)
	MemoryManager.record_once("razzia_%d" % raids,
		"Razzia Nummer %d — sie haben den Amiga mitgenommen. Papa hat wortlos einen neuen Karton hingestellt." % raids)
	var what := ("%d Kopien werden vor deinen Augen GELÖSCHT — die leeren Disketten lassen sie dir." % seized) if raids <= 1 \
		else ("%d Kopien wandern in Asservatenkisten — diesmal nehmen sie ALLES mit." % seized)
	var hint := ("Der Anwalt später, trocken: »Faustregel: Wer mit Kopien über %s Mark im Jahr umsetzt, landet auf dem Radar. Bleiben Sie drunter — oder lassen Sie es.«" % _fmt_dm(raid_at())) if raids >= 2 \
		else "Woher wussten die das? Jemand muss geredet haben … oder du warst einfach zu auffällig."
	UIManager.open_info("RAZZIA!",
		"Es klingelt Sturm. Zwei Herren in grauen Anzügen, ein Durchsuchungsbeschluss. Sie nehmen deinen Amiga und %d DM »Erlöse« mit. %s\n\nPapa sagt eine Woche lang gar nichts. Dann stellt er wortlos einen neuen Karton ins Zimmer — vom Ersparten. »Bau ihn auf. Und denk nach.«\n\n%s" % [cash, what, hint])
	raid_happened.emit()
	risk_changed.emit()


## Diskette blank löschen (Razzia, 1. Vergehen): Inhalt weg, Trägermedium bleibt.
func _wipe(disk) -> void:
	disk.content_type = "leer"
	disk.content_title = ""
	disk.software_id = ""
	disk.template_id = ""
	disk.cracktro = false
	disk.cracktro_seen = false
	disk.patch_state = "none"
	disk.checked = true
	disk.enforce_master_color()
	DiskManager.disks_changed.emit()


## Tausender mit Punkt (10.000) — für die Anwalts-Faustregel.
func _fmt_dm(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func to_dict() -> Dictionary:
	return {"year_revenue": year_revenue, "raids": raids, "warn_level": warn_level}


func from_dict(d: Dictionary) -> void:
	year_revenue = int(d.get("year_revenue", 0))
	raids = int(d.get("raids", 0))
	# Alt-Saves (bool "warned") sauber übernehmen.
	warn_level = int(d.get("warn_level", 1 if bool(d.get("warned", false)) else 0))
	risk_changed.emit()


func reset() -> void:
	year_revenue = 0
	raids = 0
	warn_level = 0
	risk_changed.emit()
