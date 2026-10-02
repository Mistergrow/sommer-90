extends LocationBase
## Musikladen — Keller-Archiv (LOCATION_MUSIC_SHOP_BASEMENT_MASTER). Der heilige
## Gral: kein normaler Shop, sondern ein LEBENDES ARCHIV. Manches ist unverkäuflich,
## manches taucht nur einmal auf, der Inhaber erzählt die Geschichte hinter den
## Objekten — je mehr Vertrauen, desto mehr. Zugang nur auf Einladung
## (music_owner_trust ≥ 40, gesetzt über Gespräche im Laden). Betreten über die
## Kellertür im Computer-Music-Hinterzimmer; raus über die Treppe.
##
## Regale/Sammler-Kabinett prozedural (MODLibrary/CollectionManager folgen);
## vorerst Flavor + Hörstation + Inhaber-Geschichten (skalieren mit Vertrauen).


func background_base() -> String:
	return "LOCATION_MUSIC_SHOP_BASEMENT_MASTER"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 120, 100), Loc.t("place.musikladen_keller_location.raritaten_regal", "Raritäten-Regal"), _rare_mods)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.musikladen_keller_location.inhaber_geschichten", "Inhaber — Geschichten"), _owner)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.musikladen_keller_location.treppe_hoch", "Treppe hoch"), _exit)
		return
	cover_mode = true
	virtual_size = Vector2(1920, 1080)
	add_hotspot(Rect2(40, 230, 340, 560), Loc.t("place.musikladen_keller_location.raritaten_mods_legendare_szene_musik", "Raritäten-MODs — legendäre Szene-Musik"), _rare_mods)
	add_hotspot(Rect2(390, 240, 300, 340), Loc.t("place.musikladen_keller_location.demo_party_archiv_releases_von_den", "Demo-Party-Archiv — Releases von den Partys"), _demoparty)
	add_hotspot(Rect2(390, 600, 300, 340), Loc.t("place.musikladen_keller_location.sample_disks_seltene_klangbibliotheken", "Sample-Disks — seltene Klangbibliotheken"), _samples)
	add_hotspot(Rect2(700, 260, 260, 320), Loc.t("place.musikladen_keller_location.tracker_software_auch_prototypen", "Tracker-Software — auch Prototypen"), _tracker)
	add_hotspot(Rect2(700, 620, 260, 320), Loc.t("place.musikladen_keller_location.import_regal_titel_aus_aller_welt", "Import-Regal — Titel aus aller Welt"), _imports)
	add_hotspot(Rect2(1000, 250, 300, 300), Loc.t("place.musikladen_keller_location.sammler_kabinett_hinter_glas", "Sammler-Kabinett — hinter Glas"), _cabinet)
	add_hotspot(Rect2(1000, 600, 300, 260), Loc.t("place.musikladen_keller_location.prototyp_regal_nie_erschienen", "Prototyp-Regal — nie erschienen"), _prototype)
	add_hotspot(Rect2(1330, 250, 300, 300), Loc.t("place.musikladen_keller_location.amiga_workbench_lauft_am_crt", "Amiga-Workbench — läuft am CRT"), _amiga)
	add_hotspot(Rect2(1330, 600, 300, 260), Loc.t("place.musikladen_keller_location.audio_werkbank_sampler_mischer", "Audio-Werkbank — Sampler & Mischer"), _audiobench)
	add_hotspot(Rect2(1650, 250, 250, 300), Loc.t("place.musikladen_keller_location.magazin_archiv_vergriffene_hefte", "Magazin-Archiv — vergriffene Hefte"), _magazines)
	add_hotspot(Rect2(1650, 600, 250, 260), Loc.t("place.musikladen_keller_location.mystery_disk_kisten_wundertuten", "Mystery-Disk-Kisten — Wundertüten"), _mystery)
	add_hotspot(Rect2(1250, 470, 220, 200), Loc.t("place.musikladen_keller_location.kopfhorer_station_reinhoren", "Kopfhörer-Station — reinhören"), _listen)
	add_hotspot(Rect2(980, 470, 220, 180), Loc.t("place.musikladen_keller_location.tresen_des_inhabers_geschichten_horen", "Tresen des Inhabers — Geschichten hören"), _owner)
	add_hotspot(Rect2(820, 900, 320, 175), Loc.t("place.musikladen_keller_location.treppe_hoch_zuruck_ins_hinterzimmer", "Treppe hoch — zurück ins Hinterzimmer"), _exit)


# ------------------------------------------------------------- Aktionen
func _rare_mods() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.erstpressungen_signierte_disks_verschollene_tracks_manches", "Erstpressungen, signierte Disks, verschollene Tracks. Manches ist unverkäuflich."))


func _demoparty() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.releases_direkt_von_den_demo_partys", "Releases direkt von den Demo-Partys — mit Platzierung und Gruppe drauf."))


func _samples() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.sample_bibliotheken_es_sonst_nirgends_gibt", "Sample-Bibliotheken, die es sonst nirgends gibt. Gold für Tracker-Leute."))


func _tracker() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.tracker_bis_zur_beta_hier_liegen", "Tracker bis zur Beta — hier liegen auch Versionen, die nie erschienen sind."))


func _imports() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.import_titel_aus_uk_skandinavien_den", "Import-Titel aus UK, Skandinavien, den Staaten. Teuer, aber echt."))


func _cabinet() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.hinter_glas_sammler_kabinett_anschauen_ja", "Hinter Glas: das Sammler-Kabinett. »Anschauen ja — anfassen später.«"))


func _prototype() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.prototypen_vorserien_offiziell_existieren_gar_nicht", "Prototypen und Vorserien. Offiziell existieren die gar nicht."))


func _amiga() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.amiga_lauft_mit_workbench_inhaber_zeigt", "Ein Amiga läuft mit Workbench — der Inhaber zeigt dir gleich was."))


func _audiobench() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.sampler_mischpult_patchkabel_hier_wurde_manches", "Sampler, Mischpult, Patchkabel — hier wurde manches Original digitalisiert."))


func _magazines() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.vergriffene_hefte_komplette_jahrgange_szene_geschichte", "Vergriffene Hefte, komplette Jahrgänge. Szene-Geschichte zum Blättern."))


func _mystery() -> void:
	UIManager.toast(Loc.t("place.musikladen_keller_location.ungeordnete_kisten_wuhl_ruhig_manchmal_ist", "Ungeordnete Kisten — »Wühl ruhig. Manchmal ist ein Schatz drin.« (Wundertüten kommen.)"))


func _listen() -> void:
	UIManager.open_music()


## Der Inhaber erzählt — je höher das Vertrauen, desto tiefer die Geschichten.
func _owner() -> void:
	var t: int = int(GameManager.flags.get("music_owner_trust", 0))
	GameManager.flags["music_owner_trust"] = mini(100, t + 4)   # unten wächst Vertrauen schneller
	var lines := ["»Schön, dass du den Weg hier runter gefunden hast.«", ""]
	if t < 65:
		lines.append("»Das meiste hier hat eine Geschichte. Frag ruhig — mit der Zeit erzähl ich mehr.«")
	elif t < 90:
		lines.append("»Diese Disk? Die hab ich '89 von einem Coder aus Helsinki. Lange Geschichte …«")
	else:
		lines.append("»Für dich mach ich auch mal die hinterste Kiste auf. Du gehörst dazu.«")
	var tip := MODBible.friend_recommendation()
	if tip != "":
		lines.append(""); lines.append("»%s«" % tip)
	UIManager.open_info("ARCHIV-INHABER", "\n".join(lines))


func _exit() -> void:
	GameManager.goto_location("musikladen_computer_music", false)
