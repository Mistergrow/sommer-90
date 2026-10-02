class_name AnsweringMachineWindow
extends RetroWindow
## Anrufbeantworter — spielt aufgezeichnete Nachrichten ab. Drei Zustände:
## (1) kein Gerät gekauft, (2) gekauft aber nicht angeschlossen, (3) angeschlossen
## → Nachrichtenliste. Realistisch: erst kaufen (Laden) UND anschließen.

func _init() -> void:
	title = Loc.t("ui.answering_machine_window.anrufbeantworter", "ANRUFBEANTWORTER")
	win_size = Vector2(430, 380)


func _ready() -> void:
	super._ready()
	if not PhoneManager.messages_changed.is_connected(_rebuild):
		PhoneManager.messages_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()

	if not PhoneManager.owns_machine():
		content.add_child(Bezel.dim_label(
			Loc.t("ui.answering_machine_window.kein_anrufbeantworter_vorhanden_es_gibt_einen", "Kein Anrufbeantworter vorhanden.\n\nEs gibt einen im Computerladen (TAM-30). Ohne Gerät verpasst du Anrufe einfach."), 12))
		return

	if not PhoneManager.machine_connected:
		content.add_child(Bezel.dim_label(
			Loc.t("ui.answering_machine_window.anrufbeantworter_tam_30_vorhanden_aber_noch", "Anrufbeantworter TAM-30 vorhanden — aber noch nicht ans Telefon angeschlossen.\n\nSchließ ihn an, damit er Anrufe aufzeichnet, wenn du unterwegs bist."), 12))
		var b := make_button(Loc.t("ui.answering_machine_window.ans_telefon_anschliessen", "Ans Telefon anschließen"), func() -> void:
			PhoneManager.connect_machine()
			AudioManager.play("tam_on"))   # Gerät fährt hoch
		content.add_child(b)
		return

	var n := PhoneManager.unheard_count()
	var head := Bezel.lcd_label(
		(Loc.t_plural("ui.answering_machine_window.new_messages",
			"%d neue Nachricht", "%d neue Nachrichten", n) if n > 0 else
		Loc.t("ui.answering_machine_window.no_new_messages", "Keine neuen Nachrichten")),
		Color(0.4, 1.0, 0.5) if n > 0 else Palette.UI_TEXT, 14)
	content.add_child(head)

	if PhoneManager.messages.is_empty():
		content.add_child(Bezel.dim_label(Loc.t("ui.answering_machine_window.band_ist_leer_niemand_hat_angerufen", "Das Band ist leer. Niemand hat angerufen."), 12))
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	content.add_child(scroll)

	for m: Dictionary in PhoneManager.messages:
		list.add_child(_message_card(m))


func _message_card(m: Dictionary) -> Control:
	var heard: bool = bool(m.get("heard", false))
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	var head := HBoxContainer.new()
	var led := Label.new()
	led.text = "●"
	led.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45) if heard else Color(0.9, 0.25, 0.25))
	head.add_child(led)
	head.add_child(Bezel.lcd_label(Loc.t("ui.answering_machine_window.anruf_von_s", "Anruf von %s") % str(m.get("from", "?")), Palette.UI_TEXT, 13))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	box.add_child(head)

	if heard:
		box.add_child(Bezel.dim_label(PhoneManager.localized_message_text(m), 11))
		box.add_child(make_button(Loc.t("ui.answering_machine_window.loschen", "Löschen"), func() -> void:
			AudioManager.play("tam_rewind")
			PhoneManager.delete_message(str(m.get("id", "")))))
	else:
		var play := make_button(Loc.t("ui.answering_machine_window.abspielen", "▶ Abspielen"), func() -> void:
			AudioManager.play("tam_play")   # echtes AB-Abspielen (Piepser/Klicks/Brummen)
			PhoneManager.mark_heard(str(m.get("id", ""))))
		box.add_child(play)
	return card
