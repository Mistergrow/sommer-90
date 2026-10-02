extends LocationBase
## LAN-KELLER (ab 1996) — als die Modems langsam gegen Netzwerkkabel tauschen,
## veranstaltet Achim im Keller unter dem Club LAN-Partys: zwanzig Rechner, ein
## Netz, eine ganze Nacht. Hier zockt man vernetzt, zeigt seine Demos und
## verkauft Kopien an die versammelte Szene. Öffnet erst 1996 (town.json).

func background_base() -> String:
	return "LOCATION_LAN_KELLER_MASTER"


func _build() -> void:
	if has_background():
		cover_mode = true
		virtual_size = Vector2(1672, 941)
		add_hotspot(Rect2(0, 260, 650, 500), Loc.t("place.lan_keller_location.rechnerreihe_vernetzt_zocken", "Rechnerreihe — vernetzt zocken"), _lan_session)
		add_hotspot(Rect2(600, 430, 560, 430), Loc.t("place.lan_keller_location.tauschtisch_kopien_verkaufen", "Tauschtisch — Kopien verkaufen"), UIManager.open_copy_sale)
		add_hotspot(Rect2(650, 85, 450, 270), Loc.t("place.lan_keller_location.leinwand_demos_zeigen", "Leinwand — Demos zeigen"), _show_demos)
		add_hotspot(Rect2(1370, 70, 302, 700), Loc.t("place.lan_keller_location.treppe_hoch_raus_orte", "Treppe hoch — raus (Orte)"), UIManager.open_map)
		return
	# Prozeduraler Fallback (virtuelle Koordinaten 415x194).
	add_hotspot(Rect2(40, 45, 150, 90), Loc.t("place.lan_keller_location.an_einen_lan_rechner_setzen_vernetzt", "An einen LAN-Rechner setzen (vernetzt zocken)"), _lan_session)
	add_hotspot(Rect2(210, 45, 120, 90), Loc.t("place.lan_keller_location.tauschtisch_kopien_verkaufen", "Tauschtisch — Kopien verkaufen"), UIManager.open_copy_sale)
	add_hotspot(Rect2(40, 145, 290, 35), Loc.t("place.lan_keller_location.demos_zeigen_szene_beeindrucken", "Demos zeigen — Szene beeindrucken"), _show_demos)
	add_hotspot(Rect2(345, 55, 45, 110), Loc.t("place.lan_keller_location.treppe_hoch_raus_orte", "Treppe hoch — raus (Orte)"), UIManager.open_map)


## Vernetzte Runde: kostet Energie, bringt Szene-Ruf und ein bisschen Preisgeld.
func _lan_session() -> void:
	if not PlayerStats.use_energy(10):
		UIManager.toast(Loc.t("place.lan_keller_location.zu_mude_fur_nachtsession_am_lan", "Zu müde für eine Nachtsession am LAN."))
		return
	var prize := randi_range(0, 12)
	PlayerStats.add_money(prize)
	PlayerStats.change_stat("ruf", 2)
	AudioManager.play("relay")
	if prize > 0:
		UIManager.toast(Loc.t("place.lan_keller_location.gute_runde_am_lan_szene_ruf", "Gute Runde am LAN! Szene-Ruf +2, %d DM Preisgeld.") % prize)
	else:
		UIManager.toast(Loc.t("place.lan_keller_location.harte_gegner_heute_kein_preisgeld_aber", "Harte Gegner heute — kein Preisgeld, aber Respekt (Ruf +2)."))


func _show_demos() -> void:
	if not PlayerStats.use_energy(6):
		UIManager.toast(Loc.t("place.lan_keller_location.zu_mude_um_jetzt_was_vorzufuhren", "Zu müde, um jetzt was vorzuführen."))
		return
	PlayerStats.change_stat("ruf", 1)
	PlayerStats.change_stat("wissen", 1)
	UIManager.toast(Loc.t("place.lan_keller_location.du_zeigst_woran_du_gebastelt_hast", "Du zeigst, woran du gebastelt hast. Anerkennendes Nicken in der Runde."))
