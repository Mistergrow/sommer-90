extends LocationBase
## Musikladen — Computer Music Corner (Hinterzimmer, LOCATION_MUSIC_SHOP_COMPUTER_MUSIC_MASTER).
## Der Szene-Schrein: MOD-Sammlungen, Tracker-Software, Sample-Disks, Demo-Scene,
## Public Domain, Audio-/MIDI-Hardware, Amiga-500-Demo am CRT, Kopfhörer-Station.
## Betreten über den Musikladen (Tür), zurück ebenso. Der Keller wird über das
## Vertrauen zum Inhaber freigeschaltet; alle Regale liefern fertige Szenedetails.


func background_base() -> String:
	return "LOCATION_MUSIC_SHOP_COMPUTER_MUSIC_MASTER"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 120, 100), Loc.t("place.musikladen_computer_music_location.mod_sammlungen", "MOD-Sammlungen"), _mods)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.musikladen_computer_music_location.kopfhorer_reinhoren", "Kopfhörer — reinhören"), _listen)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.musikladen_computer_music_location.zuruck_in_den_laden", "Zurück in den Laden"), _tofront)
		return
	cover_mode = true
	virtual_size = Vector2(1920, 1080)
	add_hotspot(Rect2(40, 230, 340, 560), Loc.t("place.musikladen_computer_music_location.mod_sammlungen_szene_musik_auf_disk", "MOD-Sammlungen — Szene-Musik auf Disk"), _mods)
	add_hotspot(Rect2(390, 260, 300, 520), Loc.t("place.musikladen_computer_music_location.tracker_software_protracker_co", "Tracker-Software — ProTracker & Co."), _tracker)
	add_hotspot(Rect2(700, 300, 260, 360), Loc.t("place.musikladen_computer_music_location.sample_bibliothek_klange_auf_disk", "Sample-Bibliothek — Klänge auf Disk"), _samples)
	add_hotspot(Rect2(700, 680, 260, 260), Loc.t("place.musikladen_computer_music_location.demo_scene_disketten_cracktros_demos", "Demo-Scene-Disketten — Cracktros & Demos"), _demoscene)
	add_hotspot(Rect2(980, 680, 240, 240), Loc.t("place.musikladen_computer_music_location.public_domain_fur_n_appel_n", "Public Domain — für'n Appel & 'n Ei"), _pd)
	add_hotspot(Rect2(1000, 250, 300, 260), Loc.t("place.musikladen_computer_music_location.amiga_500_demo_lauft_am_crt", "Amiga 500 — Demo läuft am CRT"), _amiga)
	add_hotspot(Rect2(1330, 230, 300, 300), Loc.t("place.musikladen_computer_music_location.audio_hardware_wand_sampler_boxen", "Audio-Hardware-Wand — Sampler & Boxen"), _hardware)
	add_hotspot(Rect2(1330, 560, 300, 240), Loc.t("place.musikladen_computer_music_location.midi_ecke_keyboards_interfaces", "MIDI-Ecke — Keyboards & Interfaces"), _midi)
	add_hotspot(Rect2(1250, 640, 260, 240), Loc.t("place.musikladen_computer_music_location.kopfhorer_station_mods_anhoren", "Kopfhörer-Station — MODs anhören"), _listen)
	add_hotspot(Rect2(1650, 250, 250, 300), Loc.t("place.musikladen_computer_music_location.computer_musik_magazine", "Computer-Musik-Magazine"), _magazines)
	add_hotspot(Rect2(980, 470, 220, 200), Loc.t("place.musikladen_computer_music_location.tresen_des_inhabers_szene_tipps", "Tresen des Inhabers — Szene-Tipps"), _owner)
	# Kellertür + Rücktür zuletzt.
	add_hotspot(Rect2(40, 830, 300, 240), Loc.t("place.musikladen_computer_music_location.kellertur_verschlossen", "Kellertür — verschlossen …"), _cellar)
	add_hotspot(Rect2(1560, 830, 340, 240), Loc.t("place.musikladen_computer_music_location.zuruck_in_den_laden", "Zurück in den Laden"), _tofront)


func _mods() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.mod_sammlungen_auf_disk_halbe_szene", "MOD-Sammlungen auf Disk — die halbe Szene in einer Kiste. Der Inhaber verkauft sie nur an bekannte Stammkunden."))


func _tracker() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.tracker_protracker_noisetracker_fertige_mods_zerlegen", "Tracker: ProTracker, NoiseTracker … fertige MODs zerlegen oder im Pattern-Labor eigene Musik bauen."))


func _samples() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.sample_disks_drums_basse_chore_bausteine", "Sample-Disks mit Drums, Bässen und Chören. Auf jeder Hülle stehen Speicherbedarf, Tonhöhe und eine handschriftliche Bewertung."))


func _demoscene() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.demoscene_disks", "Handbeschriftete Demo-Scene-Disketten: Cracktros, Intros und Demos. Der Inhaber prüft jede davon vor dem Verkauf."))


func _pd() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.public_domain_box", "Public-Domain-Kiste: Werkzeuge, Lernprogramme und kleine Spiele. Das beiliegende Heft erklärt, was kopiert werden darf."))


func _amiga() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.auf_dem_amiga_500_lauft_demo", "Auf dem Amiga 500 läuft eine Demo — Copper-Balken und ein fetter MOD im Loop."))


func _hardware() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.sampler_aktivboxen_kabel_wand_fur_ernste", "Sampler, Aktivboxen und sauber gebündelte Kabel. Kleine Karten nennen Anschluss, Latenz und benötigten Speicher."))


func _midi() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.midi_keyboards_interfaces_amiga_wird_zum", "MIDI-Keyboards und Interfaces stehen verkabelt bereit. Eine Taste löst am Amiga hörbar denselben Ton aus — mit einem Hauch Verzögerung."))


func _magazines() -> void:
	UIManager.toast(Loc.t("place.musikladen_computer_music_location.computer_musik_hefte_mit_tracker_tutorials", "Computer-Musik-Hefte mit Tracker-Tutorials, Szene-News und abgetippten Pattern-Tricks. Einige Seiten sind voller Bleistiftnotizen."))


func _listen() -> void:
	UIManager.open_music()


func _owner() -> void:
	var t: int = int(GameManager.flags.get("music_owner_trust", 0))
	GameManager.flags["music_owner_trust"] = mini(100, t + 5)   # Vertrauen wächst durchs Gespräch
	var lines := ["»Aha, ein Kenner. Suchst du was Bestimmtes?«", ""]
	var tip := MODBible.friend_recommendation()
	lines.append("»%s«" % tip if tip != "" else "»Frag rum — auf dem Schulhof und im Club wissen sie manchmal mehr als ich.«")
	lines.append("")
	if t + 5 >= 40:
		lines.append("»Weißt du was — geh ruhig mal in den Keller runter. Du gehörst inzwischen dazu.«")
	else:
		lines.append("»Und ganz unten im Keller … na ja. Nur für die, die dazugehören.«")
	UIManager.open_info("INHABER (COMPUTER MUSIC)", "\n".join(lines))


## Keller = heiliger Gral: nur mit genug Vertrauen zum Inhaber (Gespräche im Laden).
func _cellar() -> void:
	var t: int = int(GameManager.flags.get("music_owner_trust", 0))
	if t >= 40:
		GameManager.goto_location("musikladen_keller", false)
	elif t >= 20:
		UIManager.toast(Loc.t("place.musikladen_computer_music_location.inhaber_zogert_fast_aber_noch_nicht", "Der Inhaber zögert. »Fast … aber noch nicht. Komm öfter vorbei.«"))
	else:
		UIManager.toast(Loc.t("place.musikladen_computer_music_location.kellertur_ist_verschlossen_da_kommt_nicht", "Die Kellertür ist verschlossen. »Da kommt nicht jeder rein«, sagt der Inhaber knapp."))


func _tofront() -> void:
	GameManager.goto_location("musikladen", false)
