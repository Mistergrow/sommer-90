extends RefCounted
## Gemeinsame Konstanten des PlayerStats-Pakets.
##
## Aus player_stats.gd ausgelagert (Zeilenbudget). Diese Datei laedt bewusst
## NICHTS — dadurch kann die preload-Kette des Pakets keinen Zirkel bilden.
## Kein class_name (Klassen-Cache-Race), nur Pfad-preload.
##
## Sie liegt flach in scripts/autoload/, weil tests/quest_integrity_check.gd und
## tests/campaign_mission_runtime_contract_check.gd ihren Vertragstext ueber
## DirAccess.get_files_at("res://scripts/autoload") bauen — und das ist NICHT
## rekursiv. Ein Unterordner wuerde die Helfertexte lautlos aus dem Vertrag
## nehmen. Vorbild ist disk_sort_order.gd, der einzige weitere Nicht-Autoload
## in diesem Verzeichnis.
##
## Der Autoload re-exportiert alle Werte, damit PlayerStats.DESK_MODEL_OPTIONS
## und die uebrigen Konstanten weiter erreichbar bleiben.

# Werte, die auf 0..100 begrenzt werden
const CLAMPED := ["energie", "hunger", "ruf", "wissen", "eltern_toleranz"]
const HARDWARE_SCHEMA_VERSION := 2
const HDD_SCHEMA_VERSION := 2
const HDD_SYSTEM_KB := {
	"wb13": 1700,
	"wb205": 3600,
	"wb30": 6200,
	"wb31": 8200,
}
const RAM_HARDWARE_IDS := [
	"ram_1mb", "chipram_2mb_mod", "ram_2mb", "ram_4mb",
	"a500_accel_68030",
	"a600_chipram_2mb", "a600_pcmcia_sram_2mb", "a600_pcmcia_sram_4mb",
	"a600_accel_68030",
	"a1200_pcmcia_sram_4mb", "a1200_fast_ram_4mb", "a1200_fast_ram_8mb",
	"a1200_accel_68030", "a1200_accel_68030_50",
	"a1200_accel_68040", "a1200_accel_68060",
]

## Auswahlmoeglichkeiten des Schreibtisch-Editors je Steckplatz.
const DESK_MODEL_OPTIONS := {
	"computer_model": ["amiga_500", "amiga_600", "amiga_1200"],
	"monitor_model": ["commodore_1084s", "commodore_1901", "commodore_1942",
		"multisync_17"],
	"mouse_model": ["amiga_mouse"],
	"modem_model": ["modem_2400", "modem_9600", "modem_14400"],
	"printer_model": ["dot_matrix_9pin", "dot_matrix_24_mono", "dot_matrix_24_color",
		"color_inkjet", "laser_mono"],
	"stereo_model": ["compact_cassette", "component_cassette", "compact_cd", "dual_cd"],
}
