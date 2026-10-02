class_name DiskRepairMinigame
extends "res://scripts/ui/disk_rescue_minigame.gd"
## Physische Diskettenstabilisierung auf derselben AGA-Match-3-Engine wie der
## Disk Doctor. Kein zweites Kalibriertray, keine abstrakte Werkstattmechanik:
## zwei sichtbare Seiten, je 0:30 Startzeit plus Block-Zeitgewinn, 100 % und Bonusphase.


func _init() -> void:
	repair_mode = true
	title = Loc.t("ui.disk_repair_minigame.disk_doctor_aga_media_repair",
		"DISK DOCTOR AGA · MEDIENREPARATUR")
	win_size = Vector2(1080, 690)


static func can_start(disk: Disk) -> Dictionary:
	var diagnosis := diagnosis_gate(disk)
	if not bool(diagnosis.get("ok", false)):
		return diagnosis
	if not disk.checked:
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.check_in_xcopy_first", "Diskette zuerst in X-COPY mit PRUEFEN diagnostizieren.")}
	if disk.condition <= 0:
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.medium_ist_mechanisch_unlesbar_0_andere", "Das Medium ist mechanisch unlesbar (0%). Eine andere Quelle oder Archivkopie wird benoetigt.")}
	if disk.condition >= 95:
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.diese_diskette_ist_bereits_vollstaendig_stabil", "Diese Diskette ist bereits vollstaendig stabil.")}
	if disk.last_repair_day == TimeManager.day_counter:
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.diskette_wurde_heute_bereits_stabilisiert", "Die Diskette wurde heute bereits stabilisiert.")}
	if PlayerStats.energie < ENERGY_COST:
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.too_tired", "Zu muede fuer den Disk Doctor (%d Energie).") % ENERGY_COST}
	return {"ok": true, "reason": ""}


## Die sichtbare X-COPY-Diagnose bleibt eine nachvollziehbare Vorstufe. Der
## eigentliche Spielzugang hängt weiter am freigeschalteten Werkstattwissen.
static func diagnosis_gate(disk: Disk) -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.nur_im_laufenden_spiel_verfuegbar", "Nur im laufenden Spiel verfuegbar.")}
	if TimeManager.year < 1991:
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.medienreparatur_wird_erst_im_praktikum_1991", "Die Medienreparatur wird erst im Praktikum 1991 freigeschaltet.")}
	if not bool(GameManager.flags.get("gruber_workshop_basic", false)):
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.learn_workshop_first", "Zuerst den beaufsichtigten Werkstattbereich kennenlernen.")}
	if disk != null and disk.is_boxed_package():
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.ovp_ist_versiegelt_ihre_disketten_wurden", "Die OVP ist versiegelt; ihre Disketten wurden nicht ausgepackt.")}
	if disk == null or disk.content_type == "leer":
		return {"ok": false, "reason": Loc.t("ui.disk_repair_minigame.belegte_beschaedigte_diskette_auswaehlen", "Eine belegte, beschaedigte Diskette auswaehlen.")}
	return {"ok": true, "reason": ""}
