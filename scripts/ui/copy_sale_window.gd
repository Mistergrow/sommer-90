class_name CopySaleWindow
extends RetroWindow
## KOPIEN VERKAUFEN — Markt am aktuellen Ort (Schulhof/Club/Flohmarkt).
## Zeigt alle verkäuflichen Kopien mit Angebotspreis; bessere Etiketten
## (Nadeldruck, Farbdruck-Logo) erzielen deutlich höhere Preise.

var location_id := ""


func _init() -> void:
	title = Loc.t("ui.copy_sale_window.kopien_verkaufen", "KOPIEN VERKAUFEN")
	win_size = Vector2(470, 420)


func _ready() -> void:
	super._ready()
	if not CopyTradeManager.trade_changed.is_connected(_rebuild):
		CopyTradeManager.trade_changed.connect(_rebuild)
	var scene := get_node_or_null("/root/SceneReleaseManager")
	if scene != null and scene.has_signal("scene_changed") \
			and not scene.scene_changed.is_connected(_rebuild):
		scene.scene_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()
	var m: Dictionary = CopyTradeManager.market(location_id)
	if m.is_empty():
		content.add_child(Bezel.dim_label(Loc.t("ui.copy_sale_window.hier_kauft_niemand_kopien", "Hier kauft niemand Kopien."), 11))
		return
	var left := CopyTradeManager.slots_left(location_id)
	content.add_child(Bezel.lcd_label(Loc.t("ui.copy_sale_window.s_abnehmer_heute_d", "%s — Abnehmer heute: %d") % [str(m["name"]), left],
		Color(0.4, 1.0, 0.5) if left > 0 else Color(0.9, 0.5, 0.4), 13))
	if location_id == "schoolyard":
		var scene := get_node_or_null("/root/SceneReleaseManager")
		if scene != null:
			var risk: Dictionary = {}
			if scene.has_method("school_risk"):
				var raw_risk: Variant = scene.call("school_risk")
				if raw_risk is Dictionary:
					risk = raw_risk
			var attention := int(risk.get("attention", scene.get("school_attention")))
			var level := str(risk.get("level", "RUHIG"))
			var percent := int(risk.get("percent", 2))
			content.add_child(Bezel.dim_label(Loc.t("ui.copy_sale_window.aufmerksamkeit_s_d_100_unterbrechungsrisiko_d", "Aufmerksamkeit: %s (%d/100) · Unterbrechungsrisiko %d%% · Diskette bleibt bei dir") % [
				level, attention, percent], 9))
	content.add_child(Bezel.dim_label(
		Loc.t("ui.copy_sale_window.tipp_farbdruck_etiketten_mit_logo_bringen", "Tipp: Farbdruck-Etiketten mit Logo bringen die höchsten Preise (Drucker im Bestellkatalog)."), 9))

	var disks: Array = CopyTradeManager.sellable_disks(location_id)
	var blocked: Array = DiskManager.disks.filter(func(d: Disk) -> bool:
		return d.provenance == "copy" and d.content_type != "leer" and d.condition > 0 \
			and not bool(CopyTradeManager.sale_status(d, location_id).get("ok", false)))
	var protected_sources := blocked.filter(func(d: Disk) -> bool: return d.is_protected_copy_source())
	if not protected_sources.is_empty():
		var protection_text := ("1 gekaufte Quelldiskette geschützt" if protected_sources.size() == 1 else
			"%d gekaufte Quelldisketten geschützt" % protected_sources.size())
		content.add_child(Bezel.dim_label(
			Loc.t("ui.copy_sale_window.s_bleiben_in_deiner_sammlung_mit", "%s · bleiben in deiner Sammlung · mit X-COPY Verkaufskopien erstellen.") % protection_text, 9))
	if not blocked.is_empty():
		var explained: Disk = blocked.filter(func(d: Disk) -> bool: return not d.is_protected_copy_source()).front() \
			if blocked.any(func(d: Disk) -> bool: return not d.is_protected_copy_source()) else blocked[0]
		var why := CopyTradeManager.sale_status(explained, location_id)
		content.add_child(Bezel.dim_label(Loc.t("ui.copy_sale_window.d_kopie_n_gesperrt_s", "%d Kopie(n) gesperrt — %s") % [
			blocked.size(), str(why.get("text", "noch nicht freigegeben"))], 9))
	if disks.is_empty():
		var empty_text := ("Keine eigene Verkaufskopie in der Box. Lege eine Leerdiskette ein und kopiere deine geschützte Quelldisk mit X-COPY."
			if not protected_sources.is_empty() else
			"Keine freigegebene Kopie in der Box. Geschützte Rohkopien müssen in BYTEWERK verifiziert und einmal gestartet werden.")
		content.add_child(Bezel.dim_label(empty_text, 11))
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for d: Disk in disks:
		list.add_child(_row(d))


func _row(d: Disk) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Bezel.lcd_label(d.display_name(), Palette.UI_TEXT, 12))
	col.add_child(Bezel.dim_label(Loc.t("ui.copy_sale_window.kopie_gen_d_etikett_s_zustand", "Kopie Gen %d · Etikett: %s · Zustand %s") % [
		d.copy_generation, CultureManager.label_stage_name(d.label_quality),
		("%d%%" % d.condition) if d.checked else "?"], 9))
	if d.patch_state == "verified":
		col.add_child(Bezel.dim_label(Loc.t("ui.copy_sale_window.bytewerk_intro_s_release_s", "BYTEWERK · Intro %s · Release %s") % [
			"gesehen" if d.cracktro_seen else "noch nicht gestartet",
			d.release_serial if d.release_serial != "" else "verifiziert"], 9))
	row.add_child(col)
	var price := CopyTradeManager.offer_price(d, location_id)
	row.add_child(Bezel.lcd_label(Loc.t("ui.copy_sale_window.d_dm", "%d DM") % price, Color(0.95, 0.8, 0.3), 13))
	row.add_child(make_button(Loc.t("ui.copy_sale_window.verkaufen", "Verkaufen"), func() -> void:
		var r: Dictionary = CopyTradeManager.sell(d, location_id)
		UIManager.toast(str(r.get("text", "")))))
	return row
