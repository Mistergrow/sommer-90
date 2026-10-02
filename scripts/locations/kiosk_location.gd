extends LocationBase
## Kiosk am Markt (LOCATION_KIOSK_MASTER). Kein reiner Shop — das INFORMATIONS-
## ZENTRUM der Stadt: Computer-/Spielemagazine, Zeitungen (Wetter/News), Süßkram &
## Getränke, Bustickets für die beiden Linien, und vor allem das Schwarze Brett +
## die Gerüchte. Täglich lange offen → jeden Morgen ein echter Grund vorbeizuschauen.
##
## Bindet an vorhandene Systeme an (RumorManager/WeatherManager/MODBible) statt neue
## zu erfinden. Magazine-/Anzeigen-Inhalte kommen später aus eigenen Systemen bzw.
## den Bibeln — hier wird NICHTS an historischen Fakten erfunden (Flavor + Hooks).
## Hotspot-Positionen grob gesetzt — bei Bedarf mit dem Hotspot-Editor justieren.

const KioskMagazineLayerScript := preload("res://scripts/gfx/kiosk_magazine_layer.gd")


## Frau Oez steht als echte Weltfigur hinter dem Verkaufstresen. Der Kiosk darf
## deshalb nicht zusaetzlich den generischen NPC-Chip am oberen Bildrand bauen.
func uses_generic_npcs() -> bool:
	return false


func background_base() -> String:
	return "LOCATION_KIOSK_MASTER"


func _build() -> void:
	AudioManager.play("shop_bell")   # Türglocke
	if not has_background():
		add_hotspot(Rect2(30, 40, 120, 100), Loc.t("place.kiosk_location.zeitschriften", "Zeitschriften"), _computer_mags)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.kiosk_location.schwarzes_brett_anzeigen_geruchte", "Schwarzes Brett — Anzeigen & Gerüchte"), _board)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.kiosk_location.raus_zu_den_orten", "Raus (zu den Orten)"), UIManager.open_map)
		return
	cover_mode = true
	# Das Master ist 1672x941. Die alte 1920x1080-Annahme verschob Figuren,
	# Hotspots und die Telefonzelle sichtbar gegen das Artwork.
	virtual_size = Vector2(1672, 941)
	add_hotspot(Rect2(60, 70, 240, 150), Loc.t("place.kiosk_location.schwarzes_brett_kleinanzeigen_geruchte", "Schwarzes Brett — Kleinanzeigen & Gerüchte"), _board)
	add_hotspot(Rect2(60, 250, 320, 470), Loc.t("place.kiosk_location.computer_zeitschriften_tests_listings_coverdisks", "Computer-Zeitschriften — Tests, Listings, Coverdisks"), _computer_mags)
	add_hotspot(Rect2(400, 250, 300, 470), Loc.t("place.kiosk_location.spielemagazine_previews_cheats", "Spielemagazine — Previews & Cheats"), _gaming_mags)
	add_hotspot(Rect2(720, 300, 260, 300), Loc.t("place.kiosk_location.zeitungen_heute_morgen", "Zeitungen — heute Morgen"), _newspapers)
	add_hotspot(Rect2(720, 620, 260, 240), Loc.t("place.kiosk_location.sussigkeiten", "Süßigkeiten"), _candy)
	add_hotspot(Rect2(1000, 620, 240, 240), Loc.t("place.kiosk_location.getranke_kuhlschrank", "Getränke-Kühlschrank"), _drinks)
	add_hotspot(Rect2(1260, 620, 240, 240), Loc.t("place.kiosk_location.eistruhe", "Eistruhe"), _icecream)
	add_hotspot(Rect2(1300, 300, 300, 260), Loc.t("place.kiosk_location.bustickets_linie_1_2", "Bustickets — Linie 1 & 2"), _bus_tickets)
	# Gelbe Telefonzelle vor dem Kiosk — unterwegs telefonieren (Kleingeld nötig).
	add_hotspot(Rect2(1530, 180, 142, 610), Loc.t("place.kiosk_location.gelbe_telefonzelle_d_dm_pro_gesprach", "Gelbe Telefonzelle — %d DM pro Gespräch") % PhoneManager.BOOTH_COST, _phone_booth)
	# Kasse zuletzt → gewinnt den Treffertest, wenn sie mit einem Regal überlappt.
	add_hotspot(Rect2(730, 290, 310, 250), Loc.t("place.kiosk_location.kasse_kioskbesitzer_ansprechen", "Kasse — Kioskbesitzerin ansprechen"), _register)
	add_hotspot(Rect2(690, 820, 350, 121), Loc.t("place.kiosk_location.ausgang_zu_den_orten", "Ausgang (zu den Orten)"), UIManager.open_map)
	if "npc_oez" in NPCManager.present_now("kiosk"):
		# Nur Kopf und Oberkoerper bleiben oberhalb der eingebrannten Theke
		# sichtbar; die volle Klickflaeche bleibt fuer Maus und Editor erhalten.
		add_npc_actor("npc_oez", Rect2(790, 300, 168, 284), _on_oez, 0.74)
	# Aufrecht stehende Magazine (Regale) mit dem Cover der aktuellen Ausgabe.
	var mags := KioskMagazineLayerScript.new()
	mags.location = self
	mags.edit_mode = false
	add_child(mags)


# ------------------------------------------------------------- Info-Hub
func _board() -> void:
	UIManager.toggle_window("win_bulletin", func() -> Control:
		var w := BulletinBoardWindow.new()
		w.board_id = "kiosk"
		return w)


func _register() -> void:
	_on_oez()


func _on_oez() -> void:
	# Der Narrative-Pool enthaelt Jahrzehnt-, Wetter-, Magazin- und
	# Geruechtvarianten. So bleibt die sichtbare Haendlerin ein Charakter statt
	# eines statischen Infofensters.
	NarrativeManager.talk("npc_oez")


func _newspapers() -> void:
	# Zeitungsständer: beide Tagesblätter des Morgens (Tagesbote + Stadtblitz) mit
	# echtem Cover, eigener Schlagzeile & Preis — jahr-/saisonrichtig.
	UIManager.toggle_window("win_newspapers", func() -> Control: return NewspaperWindow.new())


func _computer_mags() -> void:
	UIManager.toast(Loc.t("place.kiosk_location.amiga_spass_jahrgang_d_nur_erschienene", "Amiga Spass, Jahrgang %d — nur erschienene Ausgaben und deine gekauften Hefte.") % TimeManager.year)
	UIManager.open_magazines()


func _gaming_mags() -> void:
	UIManager.toast(Loc.t("place.kiosk_location.spielemagazine_am_kiosk_blatter_durch_ausgaben", "Spielemagazine am Kiosk — blätter durch die Ausgaben."))
	UIManager.open_magazines()


## Das Erinnerungsregal fragt immer sichtbar: hier essen/trinken oder mitnehmen.
## Produktjahr, Asset, Museumstext und Preis stammen aus history_shops.json.
func _open_history_shop(category: String) -> void:
	UIManager.toggle_window("win_history_kiosk_%s" % category, func() -> Control:
		var window := HistoryShopWindow.new()
		window.shop_id = "kiosk"
		window.category_filter = category
		return window)


func _candy() -> void:
	_open_history_shop("suess")


func _drinks() -> void:
	_open_history_shop("getraenk")


func _icecream() -> void:
	_open_history_shop("eis")


func _bus_tickets() -> void:
	# Bindet ans neue Bus-System an: zwei Linien, Fahrt planst du auf der Karte.
	UIManager.open_info("BUSTICKETS",
		"Zwei Linien fahren durch die Stadt: Linie 1 und Linie 2, mit Halt an den Haltestellen.\n\n"
		+ "Ein Ticket löst du beim Einsteigen — wohin es geht, planst du auf der Stadtkarte (Verkehrsmittel »Bus«).")


## Gelbe Telefonzelle: das Telefon-Fenster im Zellen-Modus (kostet Kleingeld).
func _phone_booth() -> void:
	UIManager.open_phone(true)
