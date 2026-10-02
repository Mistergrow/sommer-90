class_name DiskSwapWindow
extends RetroWindow
## DISKETTENWECHSEL — das Amiga-Ritual bei Mehrdisketten-Spielen. Diskette 1 hat
## gebootet; jetzt verlangt der Ladevorgang nacheinander Diskette 2 … N („Please
## insert disk 2"). Jede wird per Klick eingelegt (Auswurf-Klack, Einschub, Kopf-
## rattern), am Ende übernimmt das Spiel. Rein zeitkolorierte Inszenierung — der
## vollständige Satz liegt bereits in der Box (DiskManager gated davor).

var total: int = 2                  # Gesamtzahl der Disketten des Satzes
var software_title: String = ""     # Anzeigename des Spiels
var on_complete: Callable = Callable()

var _current: int = 2               # Diskette 1 steckt schon → wir legen ab 2 nach


func _init() -> void:
	title = Loc.t("ui.disk_swap_window.diskettenwechsel", "DISKETTENWECHSEL")
	win_size = Vector2(400, 250)


func _ready() -> void:
	super._ready()
	_render()


func _render() -> void:
	for child in content.get_children():
		child.queue_free()
	# Auswurf der vorigen, Aufforderung für die nächste.
	AudioManager.floppy_eject()

	content.add_child(Bezel.dim_label(Loc.t("ui.disk_swap_window.s", "»%s«") % software_title, 12))
	content.add_child(Bezel.lcd_label(Loc.t("ui.disk_swap_window.bitte_diskette_d_von_d_einlegen", "Bitte Diskette %d von %d einlegen") % [_current, total],
		Color(1.0, 0.72, 0.2), 16))
	content.add_child(Bezel.dim_label(_progress_dots(), 15))
	content.add_child(Bezel.dim_label(Loc.t("ui.disk_swap_window.amiga_wartet_am_laufwerk_df0", "Der Amiga wartet am Laufwerk (DF0:)…"), 10))

	var btn := make_button(Loc.t("ui.disk_swap_window.diskette_d_einlegen", "⏏ Diskette %d einlegen") % _current, _insert)
	content.add_child(btn)


## Fortschritt als Diskettenreihe: ● erledigt · ◉ gerade fällig · ○ offen.
func _progress_dots() -> String:
	var out := ""
	for n in range(1, total + 1):
		if n < _current:
			out += "●"
		elif n == _current:
			out += "◉"
		else:
			out += "○"
		out += " "
	return out.strip_edges()


func _insert() -> void:
	AudioManager.floppy_insert()
	AudioManager.floppy_read()
	_current += 1
	if _current > total:
		var done := on_complete
		queue_free()
		if done.is_valid():
			done.call()
	else:
		_render()
