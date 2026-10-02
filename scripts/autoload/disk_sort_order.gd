class_name DiskSortOrder
extends RefCounted
## Eine einzige kanonische Totalordnung fuer DiskManager, Box-Puzzle und Tests.
## Jeder Modus endet mit Anzeigename und stabiler UID als Tie-Breaker; dadurch
## bleiben selbst identische Leer-/Tool-Disketten ueber alle Wege deterministisch.


static func sorted(source: Array, mode: int) -> Array:
	# Schluessel einmal je Disk statt je Vergleich: display_name() baut Strings,
	# value() fragt den Markt ab. Die Ordnung ist exakt dieselbe wie less().
	var m := clampi(mode, 0, 3)
	var keyed: Array = []
	for disk: Disk in source:
		var primary: Variant = null
		match m:
			1: primary = disk.content_type
			2: primary = disk.condition
			3: primary = disk.value()
		keyed.append([primary, disk.display_name(), disk.uid, disk])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return _less_keys(a, b, m))
	var result: Array = []
	for entry: Array in keyed:
		result.append(entry[3])
	return result


static func _less_keys(a: Array, b: Array, mode: int) -> bool:
	match mode:
		1:
			var type_cmp := str(a[0]).naturalnocasecmp_to(str(b[0]))
			if type_cmp != 0:
				return type_cmp < 0
		2, 3:
			if int(a[0]) != int(b[0]):
				return int(a[0]) > int(b[0])
	var name_cmp := str(a[1]).naturalnocasecmp_to(str(b[1]))
	if name_cmp != 0:
		return name_cmp < 0
	return str(a[2]).naturalnocasecmp_to(str(b[2])) < 0


static func less(a: Disk, b: Disk, mode: int) -> bool:
	match clampi(mode, 0, 3):
		1:
			var type_cmp := a.content_type.naturalnocasecmp_to(b.content_type)
			if type_cmp != 0:
				return type_cmp < 0
		2:
			if a.condition != b.condition:
				return a.condition > b.condition
		3:
			var av := a.value()
			var bv := b.value()
			if av != bv:
				return av > bv
	var name_cmp := a.display_name().naturalnocasecmp_to(b.display_name())
	if name_cmp != 0:
		return name_cmp < 0
	return a.uid.naturalnocasecmp_to(b.uid) < 0


static func same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


static func uid_signature(source: Array) -> String:
	var ids: Array[String] = []
	for disk: Disk in source:
		ids.append(disk.uid)
	return "|".join(ids)
