extends RefCounted
## Gemeinsame Konstanten des DiskManager-Pakets.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Diese Datei laedt bewusst
## NICHTS — dadurch kann die preload-Kette des Pakets keinen Zirkel bilden.
## Kein class_name (Klassen-Cache-Race), nur Pfad-preload.
##
## Der Autoload re-exportiert die von aussen gelesenen Werte, damit
## DiskManager.SORT_MODES und die Fehlerfaktoren weiter erreichbar bleiben.

# Energiekosten der Aktionen; das externe Laufwerk (DF1) halbiert sie fast
# und senkt Fehler-Risiken — das erste spürbare Hardware-Upgrade.
const ENERGY_CHECK := 10
const ENERGY_CHECK_EXT := 5
const ENERGY_BACKUP := 15
const ENERGY_BACKUP_EXT := 8
const EXT_DRIVE_ERROR_FACTOR := 0.6
const READ_DIRT_ERROR_FACTOR := 0.30
const WRITE_DIRT_ERROR_FACTOR := 0.20
const READ_ALIGNMENT_ERROR_FACTOR := 0.24
const WRITE_ALIGNMENT_ERROR_FACTOR := 0.16
const COVERDISK_TEMPLATE_ID := "coverdisk_amiga_kurier"
const LEGACY_PD_TOOLS_TEMPLATE_ID := "pd_tools_92"

const SORT_MODES := ["Name", "Inhaltstyp", "Zustand", "Wert"]
