extends RefCounted
## Gemeinsame fachliche Einordnung fuer ALLE Diskettenansichten. Werkbank,
## HUD-Archiv und Einlegedialoge duerfen dieselbe physische Diskette niemals in
## widerspruechliche Kategorien sortieren. Die Regeln bleiben bewusst frei von
## UI-Zustand; Zugriffsrechte liegen separat in disk_access_policy.gd.

const PD_TYPES := ["pd", "coverdisk", "magazin", "magazine", "shareware"]
const TOOL_TYPES := ["tools", "tool", "data", "system", "programm", "program",
	"grafik", "compilation"]
const MUSIC_TYPES := ["musik", "mod"]
const SCENE_TYPES := ["demo", "grafik"]
const SCENE_PATCH_STATES := ["bare", "draft", "verified", "legacy_scene"]
const SCENE_RELEASE_ROLES := ["work_copy", "master", "distribution", "legacy"]


static func is_game(disk: Disk) -> bool:
	return _is_loose(disk) and disk.content_type == "spiel"


static func is_scene(disk: Disk) -> bool:
	if not _is_loose(disk):
		return false
	return disk.content_type in SCENE_TYPES or disk.cracktro \
		or disk.patch_state in SCENE_PATCH_STATES \
		or disk.release_role in SCENE_RELEASE_ROLES


static func is_system(disk: Disk) -> bool:
	return _is_loose(disk) and disk.content_type == "system"


static func is_pd_coverdisk(disk: Disk) -> bool:
	if not _is_loose(disk):
		return false
	if disk.content_type in PD_TYPES:
		return true
	if disk.content_type not in TOOL_TYPES:
		return false
	var text := "%s %s %s %s" % [disk.template_id, disk.label,
		disk.content_title, disk.notes]
	text = text.to_lower()
	return "pd" in text or "public-domain" in text or "cover" in text \
		or "heft" in text or "magazin" in text or "shareware" in text


static func is_tool_data(disk: Disk) -> bool:
	return _is_loose(disk) and disk.content_type in TOOL_TYPES \
		and not is_pd_coverdisk(disk) and not is_scene(disk) and not is_system(disk)


static func is_music(disk: Disk) -> bool:
	return _is_loose(disk) and disk.content_type in MUSIC_TYPES


static func is_blank(disk: Disk) -> bool:
	return _is_loose(disk) and disk.content_type == "leer"


static func _is_loose(disk: Disk) -> bool:
	return disk != null and not disk.is_boxed_package()


## Die Werkbank katalogisiert Medien mit Inhalt. Rohlinge bleiben physisch in
## der Diskettenbox und werden erst in X-COPY bzw. Initialize als Ziel gewählt.
static func is_workbench_visible(disk: Disk) -> bool:
	return _is_loose(disk) and not is_blank(disk)


## Der Kickstart-Schirm ist ein Boot-Menü, kein zweites Archiv. Defekte,
## unformatierte oder reine Datenträger werden in der Werkbank verwaltet.
static func is_boot_selector_visible(disk: Disk) -> bool:
	return disk != null and disk.is_bootable()


static func matches_category(disk: Disk, key: String) -> bool:
	match key.to_lower():
		"spiele", "spiel": return is_game(disk)
		"szene", "scene": return is_scene(disk)
		"tools", "tool", "daten": return is_tool_data(disk)
		"pd", "pd_hefte", "pd_cover": return is_pd_coverdisk(disk)
		"musik", "music": return is_music(disk)
		"system": return is_system(disk)
		"leer", "blank": return is_blank(disk)
	return _is_loose(disk)


static func category(disk: Disk) -> String:
	if disk == null:
		return "—"
	if disk.is_boxed_package():
		return "OVP"
	if is_blank(disk):
		return "LEER"
	if is_system(disk):
		return "SYSTEM"
	if is_scene(disk):
		return "SZENE"
	if is_game(disk):
		return "SPIEL"
	if is_pd_coverdisk(disk):
		return "PD/HEFT"
	if is_music(disk):
		return "MOD"
	match disk.content_type:
		"mystery": return "???"
	if is_tool_data(disk):
		return "TOOL"
	return disk.content_type.to_upper().left(8)
