class_name IncomingCallWindow
extends RetroWindow
## EINGEHENDER ANRUF — bist du zu Hause, wenn das Telefon klingelt, kannst du
## selbst rangehen (Live-Gespräch) oder es klingeln lassen (Anrufbeantworter, wenn
## angeschlossen — sonst nehmen die Eltern ab und du rufst später zurück).
## Wer anruft, siehst du; WAS er will, erst wenn du rangehst.

var call_def: Dictionary = {}


func _init() -> void:
	title = Loc.t("ui.incoming_call_window.telefon_klingelt", "☎ TELEFON KLINGELT")
	win_size = Vector2(360, 210)


func _ready() -> void:
	super._ready()
	AudioManager.play("phone_ring", 0.0)
	content.add_child(Bezel.lcd_label(Loc.t("ui.incoming_call_window.rrrring_rrrring", "☎  Rrrring … Rrrring …"), Color(0.4, 1.0, 0.5), 16))
	content.add_child(Bezel.dim_label(Loc.t("ui.incoming_call_window.anruf_von_s", "Anruf von %s.") % str(call_def.get("from", "?")), 12))
	content.add_child(Bezel.dim_label(Loc.t("ui.incoming_call_window.gehst_du_ran", "Gehst du ran?"), 11))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var go := make_button(Loc.t("ui.incoming_call_window.rangehen", "☎  Rangehen"), func() -> void:
		PhoneManager.answer_call(call_def)
		queue_free())
	row.add_child(go)
	var no := make_button(Loc.t("ui.incoming_call_window.klingeln_lassen", "Klingeln lassen"), func() -> void:
		PhoneManager.decline_call(call_def)
		UIManager.toast(Loc.t("ui.incoming_call_window.du_lasst_es_klingeln", "Du lässt es klingeln."))
		queue_free())
	row.add_child(no)


func _exit_tree() -> void:
	# Sicherheitsnetz fuer Esc/Fenster-Schliessen: Ein unsichtbares Telefon darf
	# nicht weiterklingeln. stop_sfx fasst ausschliesslich den Klingelton an.
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("stop_sfx", "phone_ring")
