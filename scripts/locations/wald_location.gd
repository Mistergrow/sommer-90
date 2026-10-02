extends LocationBase
## Waldrand & Bolzplatz (LOCATION_WALDRAND_MASTER). Der Draußen-Ort am Stadtrand —
## KEIN Laden, sondern Sommer-Stimmung, Freunde treffen, Fußball/BMX und geheime
## Ecken mit Fundstücken. Lebt von Wetter (WeatherManager), wer gerade da ist
## (NPCManager) und Zufalls-/Freundschafts-Events. Nachmittags am belebtesten.
##
## Bindet an NPCManager und WeatherManager an. Fundstücke und kleine Aktionen sind
## abgeschlossene Atmosphäre; aktive Wege bleiben an ihre Spielsysteme gekoppelt.
## Hotspot-Positionen grob gesetzt — bei Bedarf mit dem Hotspot-Editor justieren.


func background_base() -> String:
	return "LOCATION_WALDRAND_MASTER"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 130, 100), Loc.t("place.wald_location.bolzplatz_kicken", "Bolzplatz — kicken"), _football)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.wald_location.bank_freunde_treffen", "Bank — Freunde treffen"), _bench)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.wald_location.heimweg_orte", "Heimweg (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1920, 1080)
	add_hotspot(Rect2(120, 520, 620, 420), Loc.t("place.wald_location.bolzplatz_kicken", "Bolzplatz — kicken"), _football)
	add_hotspot(Rect2(70, 180, 300, 320), Loc.t("place.wald_location.waldweg_reinspazieren", "Waldweg — reinspazieren"), _forest_path)
	add_hotspot(Rect2(380, 120, 240, 260), Loc.t("place.wald_location.trampelpfad_wohin_fuhrt", "Trampelpfad — wohin führt der?"), _secret_trail)
	add_hotspot(Rect2(760, 560, 300, 340), Loc.t("place.wald_location.bmx_rampe_sprunge_uben", "BMX-Rampe — Sprünge üben"), _bmx)
	add_hotspot(Rect2(1150, 120, 360, 520), Loc.t("place.wald_location.grosse_eiche_schatten_initialen", "Große Eiche — Schatten & Initialen"), _tree)
	add_hotspot(Rect2(820, 400, 260, 150), Loc.t("place.wald_location.bank_hinsetzen", "Bank — hinsetzen"), _bench)
	add_hotspot(Rect2(1520, 640, 340, 280), Loc.t("place.wald_location.bach_steine_flitschen", "Bach — Steine flitschen"), _creek)
	add_hotspot(Rect2(1560, 260, 240, 240), Loc.t("place.wald_location.gebusch_da_liegt_was", "Gebüsch — da liegt was …"), _bush)
	# Heimweg zuletzt → gewinnt den Treffertest.
	add_hotspot(Rect2(820, 940, 320, 135), Loc.t("place.wald_location.heimweg_zu_den_orten", "Heimweg (zu den Orten)"), UIManager.open_map)


# ------------------------------------------------------------- Aktionen
func _football() -> void:
	# Wetterabhängig + wer gerade da ist.
	var here: Array = NPCManager.present_at("wald")
	match WeatherManager.state():
		"rain", "storm":
			UIManager.toast(Loc.t("place.wald_location.bolzplatz_ist_matschig_zwei_fahrrader_liegen", "Der Bolzplatz ist matschig. Zwei Fahrräder liegen am Zaun, aber heute spielt kaum jemand."))
		_:
			if here.is_empty():
				UIManager.toast(Loc.t("place.wald_location.bolzplatz_liegt_in_sonne_tor_steht", "Der Bolzplatz liegt in der Sonne. Du schießt ein paar Bälle aufs leere Tor und wartest, ob noch jemand auftaucht."))
			else:
				var names := here.map(func(id: String) -> String: return str(NPCManager.get_npc(id).get("name", "?")))
				UIManager.toast(Loc.t("place.wald_location.auf_dem_bolzplatz_wird_gekickt_s", "Auf dem Bolzplatz wird gekickt: %s. Du bleibst kurz am Rand und schaust zu.") % ", ".join(names))


func _forest_path() -> void:
	var mood := "Vögel zwitschern, es riecht nach Harz." if WeatherManager.state() == "clear" else "Zwischen den Bäumen ist es kühl und still."
	UIManager.toast(Loc.t("place.wald_location.waldweg_fuhrt_tiefer_rein_s_heute", "Der Waldweg führt tiefer rein. %s Heute bleibst du lieber in Sichtweite des Bolzplatzes.") % mood)


func _secret_trail() -> void:
	# Der Weg oben führt zum Händler — wenn er heute da ist.
	if UIManager.dealer_here():
		GameManager.goto_location("dealer_clearing", false)
	else:
		UIManager.toast(Loc.t("place.wald_location.schmaler_trampelpfad_halb_zugewachsen_heute_ist", "Ein schmaler Trampelpfad, halb zugewachsen. Heute ist niemand hier. (Komm mal wieder vorbei.)"))


func _bmx() -> void:
	UIManager.toast(Loc.t("place.wald_location.bmx_ramp", "Die selbstgebaute BMX-Rampe knarzt. Du rollst an, ziehst kurz am Lenker und landest staubig, aber sicher."))


func _tree() -> void:
	UIManager.toast(Loc.t("place.wald_location.grosse_eiche_schatten_ast_zum_klettern", "Die große Eiche spendet Schatten. Zwischen unzähligen Initialen findest du Namen, die du vom Schulhof kennst."))


func _bench() -> void:
	# Freunde treffen: wer da ist, freut sich — kleines Vertrauen.
	var here: Array = NPCManager.present_at("wald")
	if here.is_empty():
		var line := "Die Bank steht in der Sonne — gut zum Abhängen." if WeatherManager.state() == "clear" else "Die Bank ist noch feucht vom Regen."
		UIManager.toast(line + " (Freunde tauchen nachmittags auf.)")
		return
	var id: String = here[0]
	NPCManager.change_trust(id, 1)
	UIManager.toast(Loc.t("place.wald_location.du_setzt_dich_zu_s_auf", "Du setzt dich zu %s auf die Bank. Ihr quatscht über den Sommer.") % str(NPCManager.get_npc(id).get("name", "?")))


func _creek() -> void:
	UIManager.toast(Loc.t("place.wald_location.bach_platschert_perfekt_um_steine_flitschen", "Der Bach plätschert. Der erste flache Stein springt dreimal, der zweite geht sofort unter."))


func _bush() -> void:
	UIManager.toast(Loc.t("place.wald_location.im_gebusch_blitzt_etwas_vielleicht_fundstuck", "Im Gebüsch blitzt eine verbogene Fahrradspeiche. Kein Schatz — aber aus der Ferne sah sie überzeugend aus."))
