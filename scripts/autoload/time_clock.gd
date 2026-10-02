extends RefCounted
## Reine Zeitarithmetik der Tagesuhr — zustandslos, ohne Signale, ohne Autoloads.
##
## Ausgelagert aus time_manager.gd, damit der Autoload beim Minuten-Umbau schlank
## bleibt. Liegt flach in scripts/autoload/: zwei Tests bauen ihren Vertragstext
## ueber DirAccess.get_files_at("res://scripts/autoload"), und das ist NICHT
## rekursiv. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

## Ankerzeiten der fuenf Zeitfenster in Minuten seit Mitternacht:
## 8:10 Morgen · 13:00 Mittag · 15:40 Nachmittag · 19:30 Abend · 23:10 Nacht.
## Die vier Abstaende 290/160/230/220 ergeben exakt 900 Handlungsminuten pro Tag —
## daraus ist die gesamte Kostenleiter kalibriert. Diese Werte sind die Wahrheit;
## TimeManager.SLOT_CLOCK_MINUTES verweist nur noch hierher.
const SLOT_ANCHORS := [8 * 60 + 10, 13 * 60, 15 * 60 + 40, 19 * 60 + 30, 23 * 60 + 10]
const NIGHT_SLOT := 4
const MINUTES_PER_DAY := 24 * 60


## Zu welchem Zeitfenster gehoert diese Minute? Vor dem ersten Anker gilt der
## Morgen — ein Spielstand kann nie in ein Fenster zeigen, das es nicht gibt.
static func slot_for_minute(minute: int) -> int:
	var found := 0
	for i in SLOT_ANCHORS.size():
		if minute >= int(SLOT_ANCHORS[i]):
			found = i
	return found


## Erste Minute eines Zeitfensters.
static func slot_start(slot: int) -> int:
	return int(SLOT_ANCHORS[clampi(slot, 0, NIGHT_SLOT)])


## Letzte Minute, die der Tag hergibt: Nachtanker plus Nachtbudget. Mit Budget 0
## steht die Uhr am Nachtanker still — exakt das Verhalten vor der Umstellung.
## Die Uhr rollt NIE von selbst in den naechsten Tag; das tut nur sleep().
static func day_end(night_budget: int) -> int:
	return int(SLOT_ANCHORS[NIGHT_SLOT]) + maxi(0, night_budget)


## Wie viele Minuten bleiben bis zum Ende des aktuellen Zeitfensters?
## Im Nachtfenster zaehlt das Nachtbudget.
static func minutes_left_in_slot(minute: int, night_budget: int) -> int:
	var slot := slot_for_minute(minute)
	var ende := day_end(night_budget) if slot >= NIGHT_SLOT else slot_start(slot + 1)
	return maxi(0, ende - minute)


## Uhrzeit als Text. Minuten jenseits von 24:00 laufen sichtbar in den naechsten
## Tag (01:30 an der Kiste ist die richtige Amiga-Nacht, nicht 25:30).
static func format(minute: int) -> String:
	var m := ((minute % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
	return "%02d:%02d" % [floori(m / 60.0), m % 60]


## Rundet eine Kostenangabe auf das 5er-Raster. Es gibt keine Handlung unter fuenf
## Minuten, also gibt es auch nichts zu mikro-optimieren.
static func round_cost(minutes: float) -> int:
	return maxi(0, roundi(minutes / 5.0) * 5)
