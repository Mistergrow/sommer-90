extends RefCounted
## Peripherie, Laufwerkspflege und Joystick.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

## Modemgeschwindigkeit in Baud (0 = kein Modem angeschlossen).
static func modem_baud(mgr) -> int:
	if mgr.has_hardware("modem_14400"):
		return 14400
	if mgr.has_hardware("modem_9600"):
		return 9600
	if mgr.has_hardware("modem"):
		return 2400
	return 0


static func has_modem(mgr) -> bool:
	return modem_baud(mgr) > 0


## Mindestens ein Drucker ist im Besitz; das sichtbare/aktive Modell steht im
## gemeinsamen printer_model-Slot.
static func has_printer(mgr) -> bool:
	return mgr.has_hardware("laser_printer") or mgr.has_hardware("dot_matrix") \
		or mgr.has_hardware("dot_matrix_24") or mgr.has_hardware("dot_matrix_24_color") \
		or mgr.has_hardware("color_printer")


static func printer_name(mgr) -> String:
	if not has_printer(mgr):
		return ""
	match mgr.desk_model("printer_model"):
		"dot_matrix_24_color": return "24-Nadel-Farbdrucker LQ-Color"
		"color_inkjet": return "Farb-Tintenstrahler CJ-300"
		"laser_mono": return "Laserdrucker"
		"dot_matrix_24_mono": return "24-Nadel-Drucker LQ-2400"
		"dot_matrix_9pin": return "9-Nadel-Drucker MX-90"
	return ""


## Beste verfuegbare Etikett-Druckstufe (Kopien-Handel):
## 0 = keiner/Hand · 2 = 9-Nadel · 3 = 24-Nadel/Laser · 4 = Farbdruck mit Logo.
static func best_print_stage(mgr) -> int:
	if not has_printer(mgr):
		return 0
	match mgr.desk_model("printer_model"):
		"dot_matrix_24_color", "color_inkjet": return 4
		"dot_matrix_24_mono", "laser_mono": return 3
		"dot_matrix_9pin": return 2
		_: return 0


## Laufwerkszustand. Sauberkeit und mechanische Spurtreue sind getrennte
## Ursachen: Eine Reinigungsdiskette kann ein dejustiertes Laufwerk nicht
## reparieren; Grubers Justage entfernt umgekehrt keinen Schmutz.
static func drive_dirt(mgr) -> float:
	return clampf(float(mgr.hardware.get("drive_dirt", 0.0)), 0.0, 1.0)


static func drive_cleanliness(mgr) -> float:
	return 1.0 - drive_dirt(mgr)


static func drive_alignment(mgr) -> float:
	return clampf(float(mgr.hardware.get("drive_alignment", 1.0)), 0.0, 1.0)


## Spielerlesbarer Gesamtzustand: Der schwächere der beiden Faktoren begrenzt
## die Zuverlässigkeit. So kann niemals „100 %“ erscheinen, wenn DF0 schmutzig
## oder dejustiert ist.
static func drive_condition(mgr) -> float:
	return minf(drive_cleanliness(mgr), drive_alignment(mgr))


static func set_drive_alignment(mgr, value: float) -> void:
	mgr.hardware["drive_alignment"] = clampf(value, 0.0, 1.0)
	mgr.stats_changed.emit()


## Laufwerksverschmutzung ändern (Ereignisse) bzw. zurücksetzen (Reinigung).
static func add_drive_dirt(mgr, amount: float) -> void:
	# Alte Spielstände vor Einführung des Wartungssystems besitzen den Schlüssel
	# noch nicht. Ein fehlender Wert entspricht einem sauberen Laufwerk.
	mgr.hardware["drive_dirt"] = clampf(drive_dirt(mgr) + amount, 0.0, 1.0)
	mgr.stats_changed.emit()


static func clean_drive(mgr) -> void:
	mgr.hardware["drive_dirt"] = 0.0
	mgr.stats_changed.emit()


## Joystick-Zustand. Fehlender Schlüssel in alten Spielständen bedeutet einen
## leicht defekten Start-Joystick, damit die neue Werkstatt spielbar bleibt.
static func joystick_condition(mgr) -> float:
	return clampf(float(mgr.hardware.get("joystick_condition", 0.45)), 0.0, 1.0)


static func damage_joystick(mgr, amount: float) -> void:
	mgr.hardware["joystick_condition"] = clampf(joystick_condition(mgr) - maxf(0.0, amount), 0.0, 1.0)
	mgr.stats_changed.emit()


static func repair_joystick(mgr) -> void:
	mgr.hardware["joystick_condition"] = 1.0
	mgr.stats_changed.emit()
