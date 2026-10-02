extends RefCounted
## Kanonische, rein physische Diagnose einer Diskette.
##
## Virus-Checker, Werkbank/DF0 und X-COPY duerfen denselben Medienzustand nicht
## unterschiedlich auslegen. Bootblock-Infektion und Track-Lesbarkeit bleiben
## dabei bewusst getrennte Achsen: X-COPY prueft Tracks, der Virus-Checker
## Signaturen im Bootblock.

const TRACKS := 80


static func inspect(disk: Disk, loose_media: bool) -> Dictionary:
	if disk == null:
		return {
			"readable": false,
			"code": "missing",
			"condition": 0,
			"error_tracks": [],
			"virus_known": false,
		}
	if not loose_media or disk.is_boxed_package():
		return {
			"readable": false,
			"code": "sealed",
			"condition": clampi(int(disk.condition), 0, 100),
			"error_tracks": [],
			"virus_known": bool(disk.virus),
		}
	var condition := clampi(int(disk.condition), 0, 100)
	if condition <= 0:
		return {
			"readable": false,
			"code": "unreadable",
			"condition": condition,
			"error_tracks": error_tracks(disk, "unreadable"),
			"virus_known": bool(disk.virus),
		}
	return {
		"readable": true,
		"code": "track_ok",
		"condition": condition,
		"error_tracks": [],
		"virus_known": bool(disk.virus),
	}


## Stabile Fehlerpositionen statt voneinander abweichender Zufallsraster.
## Ein vollstaendig totes Medium scheitert bereits an Spur 0; ein CRC-Fehler
## markiert reproduzierbar drei weitere betroffene Spuren.
static func error_tracks(disk: Disk, code: String) -> Array[int]:
	if disk == null:
		return []
	if code == "unreadable":
		return [0]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s" % [disk.uid, code])
	var tracks: Array[int] = []
	while tracks.size() < 3:
		var track := rng.randi_range(1, TRACKS - 1)
		if track not in tracks:
			tracks.append(track)
	tracks.sort()
	return tracks


static func track_verify_text(disk: Disk, _infected: bool) -> String:
	var title := disk.content_title if not disk.content_title.is_empty() else "leer"
	var base := "Track-Verify ok. Zustand: %d%%. Inhalt: %s." % [
		clampi(int(disk.condition), 0, 100), title]
	# Keine versteckte Virusinformation leaken: Ein physisch korrekter Bootblock
	# kann infiziert sein. Erst der separate Virenwaechter kennt Signaturen.
	return base + " Nur Track/CRC geprüft; Bootblock-Viren wurden NICHT geprüft."
