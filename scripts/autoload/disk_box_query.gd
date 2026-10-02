extends RefCounted
## Rein lesende Selektoren auf der Diskettenbox.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

static func capacity(_mgr) -> int:
	return RoomManager.BASE_DISK_CAPACITY + RoomManager.disk_capacity_bonus()


## Tatsächlich aus der Diskettenbox entnehmbare Medien. OVP-Sätze liegen als ein
## physischer Sammlungsgegenstand in der Vitrine und dürfen nie stillschweigend
## als lose Teile in DF0: oder X-COPY erscheinen.
static func media_disks(mgr) -> Array:
	return mgr.disks.filter(func(disk: Disk) -> bool: return not disk.is_boxed_package())


static func media_count(mgr) -> int:
	return media_disks(mgr).size()


static func is_loose_media(mgr, disk: Disk) -> bool:
	return disk != null and disk in mgr.disks and not disk.is_boxed_package()


static func sealed_package_count(mgr) -> int:
	return boxed_collection(mgr).filter(func(disk: Disk) -> bool:
		return disk.is_sealed_package()).size()


static func free_slots(mgr) -> int:
	return maxi(0, capacity(mgr) - media_count(mgr))


static func can_store_disks(mgr, amount: int) -> bool:
	return amount >= 0 and amount <= free_slots(mgr)


## Ein Eintrag je physischem OVP-Satz fuer Vitrine/Sammlungsbrowser. Mehrteilige
## Spiele erscheinen genau einmal; unvollstaendige Saetze bleiben im Archiv,
## werden aber nicht als ausstellungsfertige Box gemeldet.
static func boxed_collection(mgr) -> Array:
	var groups: Dictionary = {}
	for disk: Disk in mgr.disks:
		if disk.provenance != "original_box" or disk.software_id.is_empty():
			continue
		var key := disk.software_set_id if not disk.software_set_id.is_empty() else disk.uid
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(disk)
	var result: Array = []
	for key: String in groups:
		var set_disks: Array = groups[key]
		if set_disks.is_empty():
			continue
		var representative: Disk = set_disks[0]
		if set_disks.size() < representative.disk_count:
			continue
		for candidate: Disk in set_disks:
			if candidate.disk_number == 1:
				representative = candidate
				break
		result.append(representative)
	result.sort_custom(func(a: Disk, b: Disk) -> bool:
		if a.package_condition != b.package_condition:
			return a.package_condition == "sealed"
		return a.display_name().naturalnocasecmp_to(b.display_name()) < 0)
	return result


## Unterschiedliche, vollstaendige OVP-Spieltitel. Physische Dubletten bleiben in
## boxed_collection() sichtbar und wertvoll, zaehlen fuer Archivfortschritt aber
## nur einmal.
static func unique_boxed_game_count(mgr) -> int:
	var ids := {}
	for disk: Disk in boxed_collection(mgr):
		ids[disk.software_id] = true
	return ids.size()


## Besitzt der Spieler Inhalt dieses Templates? (Quest-Prüfungen)
static func has_template(mgr, template_id: String) -> bool:
	return get_disk_by_template(mgr, template_id) != null


static func get_disk_by_template(mgr, template_id: String) -> Disk:
	for disk in mgr.disks:
		if disk.template_id == template_id and disk.condition > 0:
			return disk
	return null


## Zentraler Selektor fuer physische Uebergaben. Ein gemeinsames Praedikat
## verhindert, dass Dialogbedingung, Transaktionspruefung und echte Abbuchung
## unterschiedliche Disketten meinen. `unresolved_mystery` bezeichnet bewusst
## nur eine noch unbekannte, unbeschriftete ???-Diskette; bereits gepruefte
## Inhalte behalten zwar ihre Template-ID, duerfen aber nicht mehr als Mystery
## abgegeben werden.
static func matching_media(mgr, criteria: Dictionary) -> Array[Disk]:
	var wanted_template := str(criteria.get("id",
		criteria.get("template_id", ""))).strip_edges()
	var uid_flag := str(criteria.get("uid_flag", "")).strip_edges()
	var wanted_uid := str(criteria.get("uid", "")).strip_edges()
	if wanted_uid.is_empty() and not uid_flag.is_empty():
		wanted_uid = str(GameManager.flags.get(uid_flag, "")).strip_edges()
		if wanted_uid.is_empty():
			return []
	var wanted_software := str(criteria.get("software_id", "")).strip_edges()
	var wanted_content_type := str(criteria.get("content_type", "")).strip_edges()
	var wanted_release_role := str(criteria.get("release_role", "")).strip_edges()
	var release_serial_prefix := str(criteria.get("release_serial_prefix", "")).strip_edges()
	var release_project_kind := str(criteria.get("release_project_kind", "")).strip_edges()
	var minimum_condition := maxi(1, int(criteria.get("condition_min", 1)))
	var player_copy_only := bool(criteria.get("player_copy_only", false))
	var unresolved_mystery := bool(criteria.get("unresolved_mystery", false))
	var exclude_quest_required := bool(criteria.get("exclude_quest_required", false))
	var result: Array[Disk] = []
	for disk: Disk in media_disks(mgr):
		if disk.condition < minimum_condition:
			continue
		if not wanted_uid.is_empty() and disk.uid != wanted_uid:
			continue
		if not wanted_template.is_empty() and disk.template_id != wanted_template:
			continue
		if not wanted_software.is_empty() and disk.software_id != wanted_software:
			continue
		if not wanted_content_type.is_empty() and disk.content_type != wanted_content_type:
			continue
		if not wanted_release_role.is_empty() and disk.release_role != wanted_release_role:
			continue
		if not release_serial_prefix.is_empty() \
				and not disk.release_serial.begins_with(release_serial_prefix):
			continue
		if not release_project_kind.is_empty() \
				and str(disk.release_data.get("project_kind", "")) != release_project_kind:
			continue
		if player_copy_only and (not disk.is_player_made_copy() or disk.is_game_master()):
			continue
		if unresolved_mystery and (disk.content_type != "mystery" \
				or not disk.label.strip_edges().is_empty() \
				or disk.content_title.strip_edges() not in ["", "???"]):
			continue
		if exclude_quest_required \
				and bool(QuestManager.disk_requirement(disk).get("required", false)):
			continue
		result.append(disk)
	return result


static func blank_disks(mgr) -> Array:
	return media_disks(mgr).filter(func(d: Disk) -> bool:
		return d.content_type == "leer" and d.condition > 0)


## Echte, im eigenen Laufwerk erzeugte Folgegenerationen eines Titels. Fremde
## Flohmarkt-Kopien ohne source_uid sind geschuetzte Quellen und zaehlen nicht.
static func player_copies_of(mgr, software_id: String) -> Array:
	return mgr.disks.filter(func(d: Disk) -> bool:
		return d.software_id == software_id and d.condition > 0 \
			and d.is_player_made_copy() and not d.is_game_master())


static func has_player_copy_of(mgr, software_id: String) -> bool:
	return not player_copies_of(mgr, software_id).is_empty()


## Alle vorhandenen, lesbaren Teile eines Software-Titels, pro Teilnummer nur
## einmal. Damit kann eine verlorene Originaldisk durch eine Sicherung ersetzt werden.
static func software_parts(mgr, software_id: String) -> Dictionary:
	var parts := {}
	for disk: Disk in media_disks(mgr):
		if disk.software_id != software_id or disk.condition <= 0:
			continue
		var number := clampi(disk.disk_number, 1, maxi(1, disk.disk_count))
		if not parts.has(number) or int((parts[number] as Disk).condition) < disk.condition:
			parts[number] = disk
	return parts


static func missing_software_parts(mgr, software_id: String) -> Array[int]:
	var required := SoftwareBible.disk_count(software_id)
	for disk: Disk in media_disks(mgr):
		if disk.software_id == software_id:
			required = maxi(required, disk.disk_count)
	var owned := software_parts(mgr, software_id)
	var missing: Array[int] = []
	for number in range(1, required + 1):
		if not owned.has(number):
			missing.append(number)
	return missing


static func has_complete_software(mgr, software_id: String) -> bool:
	return not software_id.is_empty() and missing_software_parts(mgr, software_id).is_empty()


## Fehlende Teile beim Start einer konkret eingelegten Diskette. Die eingelegte
## Disk kann bereits in DF0 liegen und muss deshalb nicht zugleich in der Box sein.
static func missing_parts_for_disk(mgr, disk: Disk) -> Array[int]:
	if disk == null or disk.software_id.is_empty():
		return []
	var required := maxi(SoftwareBible.disk_count(disk.software_id), disk.disk_count)
	var owned := software_parts(mgr, disk.software_id)
	if disk.condition > 0:
		owned[clampi(disk.disk_number, 1, required)] = disk
	var missing: Array[int] = []
	for number in range(1, required + 1):
		if not owned.has(number):
			missing.append(number)
	return missing


## Teile genau dieses physischen Satzes, sortiert nach Diskettennummer.
static func disk_set_parts(mgr, disk: Disk, usable_only: bool = true) -> Array:
	if disk == null:
		return []
	if disk.disk_count <= 1:
		return [disk] if disk in mgr.disks and (not usable_only or disk.condition > 0) else []
	var out: Array = []
	for candidate: Disk in mgr.disks:
		if candidate.software_id != disk.software_id or candidate.software_set_id != disk.software_set_id:
			continue
		if usable_only and candidate.condition <= 0:
			continue
		out.append(candidate)
	out.sort_custom(func(a: Disk, b: Disk) -> bool: return a.disk_number < b.disk_number)
	return out


static func has_complete_disk_set(mgr, disk: Disk) -> bool:
	if disk == null:
		return false
	var found := {}
	for part: Disk in disk_set_parts(mgr, disk):
		found[part.disk_number] = true
	for number in range(1, disk.disk_count + 1):
		if not found.has(number):
			return false
	return true


static func collection_value(mgr) -> int:
	var total := 0
	for disk in mgr.disks:
		total += disk.value()
	return total
