extends LocationBase
## Stadtbank (LOCATION_BANK_MASTER) — Filiale mit 24-Stunden-Automatenraum und
## getrennten Schalterzeiten. Das Sparbuch ist ab 1990 nutzbar; Giro und EC-Karte
## folgen historisch gestaffelt ueber BankManager.
##
## Hotspots (virtual_size 1920×1080): Schalter, Geldautomat, Einzahlung, Auszahlung,
## Überweisung, Sparbuch, Kreditschalter, Schwarzes Brett, Ausgangstür.


func background_base() -> String:
	return "LOCATION_BANK_MASTER"


func uses_generic_npcs() -> bool:
	# Herr Wolf wird ueber den Schalter angesprochen. So steht nachts kein
	# schwebender NPC-Chip im leeren 24-Stunden-Automatenraum.
	return false


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 120, 100), Loc.t("place.stadtbank_location.schalter", "Schalter"), _counter)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.stadtbank_location.geldautomat", "Geldautomat"), _atm)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.stadtbank_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1920, 1080)
	# Große Flächen zuerst, kleine (am Tresen) zuletzt → kleine gewinnen den Treffertest.
	add_hotspot(Rect2(0, 40, 195, 900), Loc.t("place.stadtbank_location.tur_raus_zu_den_orten", "Tür — raus (zu den Orten)"), UIManager.open_map)
	add_hotspot(Rect2(225, 255, 190, 405), Loc.t("place.stadtbank_location.geldautomat_kontostand_abheben", "Geldautomat — Kontostand & Abheben"), _atm)
	add_hotspot(Rect2(415, 470, 280, 260), Loc.t("place.stadtbank_location.stehpult_uberweisungstrager_ausfullen", "Stehpult — Überweisungsträger ausfüllen"), _transfer)
	add_hotspot(Rect2(1370, 290, 200, 380), Loc.t("place.stadtbank_location.prospektstander_schwarzes_brett_anzeigen_geruchte", "Prospektständer / Schwarzes Brett — Anzeigen & Gerüchte"), _board)
	add_hotspot(Rect2(585, 360, 780, 270), Loc.t("place.stadtbank_location.schalter_kassiererin_ansprechen", "Schalter — Kassiererin ansprechen"), _counter)
	add_hotspot(Rect2(620, 410, 200, 160), Loc.t("place.stadtbank_location.einzahlung", "Einzahlung"), _deposit)
	add_hotspot(Rect2(840, 410, 200, 160), Loc.t("place.stadtbank_location.auszahlung", "Auszahlung"), _withdraw)
	add_hotspot(Rect2(1055, 410, 180, 160), Loc.t("place.stadtbank_location.sparbuch", "Sparbuch"), _savings)
	add_hotspot(Rect2(1245, 375, 150, 230), Loc.t("place.stadtbank_location.kreditschalter_beratung", "Kreditschalter — Beratung"), _loan)
	if not BankManager.counter_open():
		_add_closed_sign()


# ------------------------------------------------------------- Aktionen

func _counter() -> void:
	if not _require_counter():
		return
	UIManager.open_bank("sparbuch")


func _atm() -> void:
	UIManager.open_bank_atm()


func _deposit() -> void:
	if _require_counter():
		UIManager.open_bank("sparbuch")


func _withdraw() -> void:
	if _require_counter():
		UIManager.open_bank("sparbuch")


func _transfer() -> void:
	if _require_counter():
		UIManager.open_bank("giro")


func _savings() -> void:
	if _require_counter():
		UIManager.open_bank("sparbuch")


func _loan() -> void:
	if not _require_counter():
		return
	UIManager.open_info("KREDITBERATUNG",
		"Herr Wolf legt den Fueller beiseite.\n\n»Fuer kurzlebige Computerwuensche rate ich keinem Schueler zu Schulden. Erst Sparziel, dann Ruecklage, dann Kauf. Ihr Sparbuch ist der bessere Anfang.«\n\nDie Stadtbank vergibt im Kampagnenzeitraum bewusst keinen leicht ausnutzbaren Sofortkredit.")


func _board() -> void:
	UIManager.open_rumors("board")


func _require_counter() -> bool:
	if BankManager.counter_open():
		return true
	UIManager.open_info("SCHALTER GESCHLOSSEN",
		"Die Rollos am Schalter sind unten.\n\nOeffnungszeiten: %s\n\nDer Geldautomat links bleibt rund um die Uhr in Betrieb. Mit EC-Karte kannst du dort abheben, den Kontostand abrufen und eine Belegeinzahlung vornehmen."
		% BankManager.counter_hours_text())
	return false


func _add_closed_sign() -> void:
	var closed_sign := Label.new()
	closed_sign.text = Loc.t("place.stadtbank_location.schalter_geschlossen_geldautomat_geoffnet", "SCHALTER GESCHLOSSEN  ·  GELDAUTOMAT GEÖFFNET")
	closed_sign.add_theme_font_size_override("font_size", 22)
	closed_sign.add_theme_color_override("font_color", Color8(255, 212, 105))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.05, 0.92)
	style.border_color = Color8(134, 102, 51)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	closed_sign.add_theme_stylebox_override("normal", style)
	closed_sign.z_index = 15
	add_child(closed_sign)
	_layout_closed_sign.call_deferred(closed_sign)
	resized.connect(_layout_closed_sign.bind(closed_sign))


func _layout_closed_sign(closed_sign: Label) -> void:
	if not is_instance_valid(closed_sign):
		return
	var s := view_scale()
	closed_sign.position = view_offset() + Vector2(650, 205) * s
	closed_sign.scale = Vector2(s, s)
