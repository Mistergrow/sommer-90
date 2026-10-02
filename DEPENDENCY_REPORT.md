# Missing runtime dependencies

Excluded dependencies are intentional. REQUIRED-FOR-PARSE identifies direct preloads; REQUIRED-FOR-RUNTIME identifies direct loads, scene/resource references, autoloads and configuration. UNKNOWN paths can be data-driven resource references, directories, patterns, comments or generated outputs. Dynamic calls are recorded in DEPENDENCIES.json. Reachability and constructed paths are not proven.

| Path | Classification | References |
|---|---|---|
| `res://Content/Magazine/assets/` | UNKNOWN | `addons/export_runtime_assets/export_runtime_assets.gd:19` |
| `res://Content/Magazine/index.json` | UNKNOWN | `scripts/data/magazine_production_catalog.gd:8` |
| `res://Content/Software` | UNKNOWN | `scripts/autoload/software_bible.gd:17`; `addons/export_runtime_assets/export_runtime_assets.gd:12` |
| `res://assets/audio/ambient/` | UNKNOWN | `scripts/autoload/ambient_manager.gd:11` |
| `res://assets/audio/music/` | UNKNOWN | `addons/export_runtime_assets/export_runtime_assets.gd:232` |
| `res://assets/audio/music/MUS_SPACE_DEBRIS_V01.mod` | UNKNOWN | `scripts/autoload/export_health.gd:109` |
| `res://assets/audio/sfx/SFX_BAG_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:57` |
| `res://assets/audio/sfx/SFX_BIRDS_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:159` |
| `res://assets/audio/sfx/SFX_BIRD_CHIRP_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:33` |
| `res://assets/audio/sfx/SFX_BOX_ITEM_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:56` |
| `res://assets/audio/sfx/SFX_BOX_TAPE_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:55` |
| `res://assets/audio/sfx/SFX_CAMERA_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:62` |
| `res://assets/audio/sfx/SFX_CASH_COUNT_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:61` |
| `res://assets/audio/sfx/SFX_CASH_REGISTER_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:59` |
| `res://assets/audio/sfx/SFX_COINS_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:60` |
| `res://assets/audio/sfx/SFX_CRT_STARTUP_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:29` |
| `res://assets/audio/sfx/SFX_DOOR_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:47` |
| `res://assets/audio/sfx/SFX_FAX_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:30` |
| `res://assets/audio/sfx/SFX_FLOPPY_EJECT_V01.mp3` | UNKNOWN | `scripts/autoload/audio_manager.gd:14` |
| `res://assets/audio/sfx/SFX_FLOPPY_INSERT_V01.mp3` | UNKNOWN | `scripts/autoload/audio_manager.gd:11` |
| `res://assets/audio/sfx/SFX_FLOPPY_READ_A_V01.mp3` | UNKNOWN | `scripts/autoload/audio_manager.gd:12` |
| `res://assets/audio/sfx/SFX_FLOPPY_READ_B_V01.mp3` | UNKNOWN | `scripts/autoload/audio_manager.gd:13` |
| `res://assets/audio/sfx/SFX_FOOTSTEPS_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:48` |
| `res://assets/audio/sfx/SFX_HAGGLE_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:49` |
| `res://assets/audio/sfx/SFX_KEY_CLICK_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:16`; `scripts/autoload/export_health.gd:7` |
| `res://assets/audio/sfx/SFX_KEY_ENTER_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:17` |
| `res://assets/audio/sfx/SFX_KNOCK_FAST_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:51` |
| `res://assets/audio/sfx/SFX_KNOCK_SOFT_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:52` |
| `res://assets/audio/sfx/SFX_KNOCK_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:50` |
| `res://assets/audio/sfx/SFX_MODEM_DIAL_B_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:22` |
| `res://assets/audio/sfx/SFX_MODEM_DIAL_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:21` |
| `res://assets/audio/sfx/SFX_MODEM_USROBOTICS_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:23` |
| `res://assets/audio/sfx/SFX_PAGE_TURN_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:53` |
| `res://assets/audio/sfx/SFX_PAPER_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:54` |
| `res://assets/audio/sfx/SFX_PHONE_BUSY_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:41` |
| `res://assets/audio/sfx/SFX_PHONE_DIALTONE_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:27` |
| `res://assets/audio/sfx/SFX_PHONE_HANGUP_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:43` |
| `res://assets/audio/sfx/SFX_PHONE_PICKUP_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:42` |
| `res://assets/audio/sfx/SFX_PHONE_RINGBACK_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:26` |
| `res://assets/audio/sfx/SFX_PHONE_RING_OFFICE_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:25` |
| `res://assets/audio/sfx/SFX_PHONE_RING_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:24` |
| `res://assets/audio/sfx/SFX_RAIN_ROOM_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:151` |
| `res://assets/audio/sfx/SFX_RAIN_STORM_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:152` |
| `res://assets/audio/sfx/SFX_SHOP_BELL_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:46` |
| `res://assets/audio/sfx/SFX_TAM_ON_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:38` |
| `res://assets/audio/sfx/SFX_TAM_PLAY_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:36` |
| `res://assets/audio/sfx/SFX_TAM_REWIND_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:37` |
| `res://assets/audio/sfx/SFX_THUNDER_V02.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:31` |
| `res://assets/audio/sfx/SFX_TYPING_FAST_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:18` |
| `res://assets/audio/sfx/SFX_TYPING_V01.ogg` | UNKNOWN | `scripts/autoload/audio_manager.gd:19` |
| `res://assets/audio/sfx/SFX_VACUUM_CLEANER_LOOP_V01.ogg` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/autoload/audio_manager.gd:65`; `scripts/ui/household_sprint_stage.gd:31` |
| `res://assets/audio/soundtrack/` | UNKNOWN | `scripts/autoload/export_health.gd:92`; `addons/export_runtime_assets/export_runtime_assets.gd:48` |
| `res://assets/backgrounds/foregrounds/LOCATION_BANK_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:66` |
| `res://assets/backgrounds/foregrounds/LOCATION_COMPUTER_CLUB_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:46` |
| `res://assets/backgrounds/foregrounds/LOCATION_COMPUTER_SHOP_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:41` |
| `res://assets/backgrounds/foregrounds/LOCATION_DEALER_CLEARING_FOREGROUND_V01.png` | UNKNOWN | `data/asset_registry.json:1513`; `data/location_25d.json:11` |
| `res://assets/backgrounds/foregrounds/LOCATION_FLEA_MARKET_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:26` |
| `res://assets/backgrounds/foregrounds/LOCATION_FRIEND_ROOM_ALEX_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:101` |
| `res://assets/backgrounds/foregrounds/LOCATION_FRIEND_ROOM_DANIEL_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:106` |
| `res://assets/backgrounds/foregrounds/LOCATION_FRIEND_ROOM_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:86` |
| `res://assets/backgrounds/foregrounds/LOCATION_FRIEND_ROOM_LISA_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:111` |
| `res://assets/backgrounds/foregrounds/LOCATION_FRIEND_ROOM_MIKE_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:96` |
| `res://assets/backgrounds/foregrounds/LOCATION_FRIEND_ROOM_SVEN_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:91` |
| `res://assets/backgrounds/foregrounds/LOCATION_IMBISS_FOREGROUND_V01.png` | UNKNOWN | `data/asset_registry.json:1722`; `data/location_25d.json:36` |
| `res://assets/backgrounds/foregrounds/LOCATION_INTERNETCAFE_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:76` |
| `res://assets/backgrounds/foregrounds/LOCATION_KIOSK_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:31` |
| `res://assets/backgrounds/foregrounds/LOCATION_LAN_KELLER_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:81` |
| `res://assets/backgrounds/foregrounds/LOCATION_MUSIC_SHOP_BASEMENT_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:56` |
| `res://assets/backgrounds/foregrounds/LOCATION_MUSIC_SHOP_COMPUTER_MUSIC_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:61` |
| `res://assets/backgrounds/foregrounds/LOCATION_MUSIC_SHOP_FRONT_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:51` |
| `res://assets/backgrounds/foregrounds/LOCATION_POST_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:71` |
| `res://assets/backgrounds/foregrounds/LOCATION_RETRO_MUSEUM_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:116` |
| `res://assets/backgrounds/foregrounds/LOCATION_SCHOOLYARD_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:16`; `data/location_25d.json:21` |
| `res://assets/backgrounds/foregrounds/LOCATION_WALDRAND_FOREGROUND_V01.png` | UNKNOWN | `data/location_25d.json:6` |
| `res://assets/backgrounds/layers/` | UNKNOWN | `scripts/gfx/room_assets.gd:11`; `scripts/gfx/room_device_catalog.gd:9` |
| `res://assets/backgrounds/layers/%s_V%02d.png` | UNKNOWN | `scripts/ui/monitor_profile.gd:282` |
| `res://assets/backgrounds/layers/A1200_ACCEL_68030_16MB_V01.png` | UNKNOWN | `data/asset_registry.json:1793`; `data/shop.json:365` |
| `res://assets/backgrounds/layers/A1200_ACCEL_68030_50_32MB_V01.png` | UNKNOWN | `data/shop.json:382` |
| `res://assets/backgrounds/layers/A1200_ACCEL_68040_32MB_V01.png` | UNKNOWN | `data/shop.json:399` |
| `res://assets/backgrounds/layers/A1200_ACCEL_68060_64MB_V01.png` | UNKNOWN | `data/shop.json:416` |
| `res://assets/backgrounds/layers/A1200_FASTRAM_4MB_RTC_V01.png` | UNKNOWN | `data/asset_registry.json:1777`; `data/shop.json:331` |
| `res://assets/backgrounds/layers/A1200_FASTRAM_8MB_RTC_V01.png` | UNKNOWN | `data/asset_registry.json:1785`; `data/shop.json:348` |
| `res://assets/backgrounds/layers/A1200_HDD_25_IDE_1200MB_V01.png` | UNKNOWN | `data/shop.json:297` |
| `res://assets/backgrounds/layers/A1200_HDD_25_IDE_420MB_V01.png` | UNKNOWN | `data/shop.json:280` |
| `res://assets/backgrounds/layers/A1200_HDD_25_IDE_80MB_V01.png` | UNKNOWN | `data/asset_registry.json:1769`; `data/shop.json:263` |
| `res://assets/backgrounds/layers/A1200_PCMCIA_SRAM_4MB_V01.png` | UNKNOWN | `data/shop.json:314` |
| `res://assets/backgrounds/layers/A1200_SCSI_CDROM_4X_V01.png` | UNKNOWN | `data/shop.json:450` |
| `res://assets/backgrounds/layers/A1200_SCSI_MODULE_V01.png` | UNKNOWN | `data/shop.json:433` |
| `res://assets/backgrounds/layers/A500_ACCEL_68030_8MB_SCSI_V01.png` | UNKNOWN | `data/shop.json:645` |
| `res://assets/backgrounds/layers/A500_SCSI_CDROM_2X_V01.png` | UNKNOWN | `data/shop.json:662` |
| `res://assets/backgrounds/layers/A501_RAM_EXPANSION_V01.png` | UNKNOWN | `data/shop.json:580` |
| `res://assets/backgrounds/layers/A600_ACCEL_68030_32MB_V01.png` | UNKNOWN | `data/shop.json:230` |
| `res://assets/backgrounds/layers/A600_CHIPRAM_A601_V01.png` | UNKNOWN | `data/shop.json:145` |
| `res://assets/backgrounds/layers/A600_HDD_25_IDE_120MB_V01.png` | UNKNOWN | `data/shop.json:179` |
| `res://assets/backgrounds/layers/A600_HDD_25_IDE_40MB_V01.png` | UNKNOWN | `data/shop.json:162` |
| `res://assets/backgrounds/layers/A600_PCMCIA_SRAM_2MB_V01.png` | UNKNOWN | `data/shop.json:196` |
| `res://assets/backgrounds/layers/A600_PCMCIA_SRAM_4MB_V01.png` | UNKNOWN | `data/shop.json:213` |
| `res://assets/backgrounds/layers/AMIGAOS31_UPGRADE_KIT_V01.png` | UNKNOWN | `data/asset_registry.json:1801`; `data/shop.json:467` |
| `res://assets/backgrounds/layers/AMIGA_POWER_SUPPLY_MASTER_V01.png` | UNKNOWN | `scripts/startup_loader.gd:58`; `scripts/startup_loader.gd:100` |
| `res://assets/backgrounds/layers/ANSWERING_MACHINE_TAM30_V01.png` | UNKNOWN | `data/shop.json:87` |
| `res://assets/backgrounds/layers/CDROM_AMIGA_A570_V01.png` | UNKNOWN | `data/shop.json:679` |
| `res://assets/backgrounds/layers/CD_BURNER_EXTERNAL_2X_V01.png` | UNKNOWN | `data/shop.json:100` |
| `res://assets/backgrounds/layers/CHIPRAM_2MB_AGNUS_KIT_V01.png` | UNKNOWN | `data/shop.json:596` |
| `res://assets/backgrounds/layers/COFFEE_MUG_BEIGE_V01.png` | UNKNOWN | `scripts/startup_loader.gd:56`; `scripts/startup_loader.gd:98` |
| `res://assets/backgrounds/layers/COMPUTER_AMIGA1200_V02.png` | UNKNOWN | `data/asset_registry.json:1285` |
| `res://assets/backgrounds/layers/COMPUTER_AMIGA1200_V03.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/hardware_assembly_minigame.gd:314`; `data/asset_registry.json:1303`; `data/shop.json:247` |
| `res://assets/backgrounds/layers/COMPUTER_AMIGA500_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/listing_type_minigame.gd:243` |
| `res://assets/backgrounds/layers/COMPUTER_AMIGA500_V02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/startup_loader.gd:23`; `scripts/startup_loader.gd:89`; `scripts/ui/hardware_assembly_minigame.gd:312`; `scripts/ui/upgrade_tree_window.gd:10`; `data/asset_registry.json:1248` |
| `res://assets/backgrounds/layers/COMPUTER_AMIGA600_V01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/hardware_assembly_minigame.gd:313`; `data/asset_registry.json:1266`; `data/shop.json:129` |
| `res://assets/backgrounds/layers/DESK_LAMP_CLASSIC_V01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/startup_loader.gd:25`; `scripts/startup_loader.gd:91`; `scripts/ui/listing_type_minigame.gd:245` |
| `res://assets/backgrounds/layers/DISKBOX_12_SMOKED_V02.png` | REQUIRED-FOR-RUNTIME, UNKNOWN | `scripts/startup_loader.gd:28`; `scripts/startup_loader.gd:94`; `scripts/ui/flea_window.gd:457`; `data/asset_registry.json:1491`; `data/shop.json:47` |
| `res://assets/backgrounds/layers/DISKBOX_80_ARCHIVE_V01.png` | UNKNOWN | `data/asset_registry.json:1498`; `data/shop.json:771` |
| `res://assets/backgrounds/layers/DRINK_GENERIC_COLA_CAN_1990_V01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/room_tidy_minigame.gd:10`; `data/history_shops.json:92` |
| `res://assets/backgrounds/layers/DRIVE_COMMODORE_A1011_V01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/hardware_assembly_minigame.gd:315`; `data/asset_registry.json:304`; `data/shop.json:60` |
| `res://assets/backgrounds/layers/FASTRAM_AMIGA_SIDECAR_2MB_V01.png` | UNKNOWN | `data/shop.json:612` |
| `res://assets/backgrounds/layers/FLOPPY_35_DD_BLUE_FRONT_V01.png` | UNKNOWN | `scripts/gfx/disk_composer.gd:8`; `scripts/gfx/disk_editor.gd:12`; `scripts/startup_loader.gd:55`; `scripts/startup_loader.gd:97`; `data/disk_layout.json:3`; `data/shop.json:6` |
| `res://assets/backgrounds/layers/FOLDING_TOWN_MAP_MASTER_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:13`; `data/town.json:12` |
| `res://assets/backgrounds/layers/GAME_WHITE_BIGBOX_MASTER_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:18`; `scripts/gfx/box_layout_editor.gd:7`; `scripts/gfx/software_box_composer.gd:9`; `data/software_box_layout.json:4` |
| `res://assets/backgrounds/layers/HAND_SCANNER_GRAYSCALE_V01.png` | UNKNOWN | `data/shop.json:113` |
| `res://assets/backgrounds/layers/HDD_AMIGA_A590_V01.png` | UNKNOWN | `data/shop.json:628` |
| `res://assets/backgrounds/layers/ICE_ICE_CREAM_WRAPPER_GENERIC_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/room_tidy_minigame.gd:11` |
| `res://assets/backgrounds/layers/IMBISS_BRATWURST_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1658`; `data/history_shops.json:530`; `data/history_shops.json:546`; `data/history_shops.json:742` |
| `res://assets/backgrounds/layers/IMBISS_CURRYWURST_V01.png` | UNKNOWN | `data/asset_registry.json:1694`; `data/history_shops.json:422`; `data/history_shops.json:438` |
| `res://assets/backgrounds/layers/IMBISS_FRIKADELLE_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1664`; `data/history_shops.json:563`; `data/history_shops.json:579` |
| `res://assets/backgrounds/layers/IMBISS_POMMES_V01.png` | UNKNOWN | `data/asset_registry.json:1688`; `data/history_shops.json:406`; `data/history_shops.json:439`; `data/history_shops.json:461`; `data/history_shops.json:478`; `data/history_shops.json:495`; `data/history_shops.json:513`; `data/history_shops.json:547`; `data/history_shops.json:580`; `data/history_shops.json:613`; `data/history_shops.json:646` |
| `res://assets/backgrounds/layers/IMBISS_SAUCEN_EXTRAS_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1682`; `data/history_shops.json:479`; `data/history_shops.json:496`; `data/history_shops.json:514`; `data/history_shops.json:662`; `data/history_shops.json:678`; `data/history_shops.json:694`; `data/history_shops.json:710`; `data/history_shops.json:726` |
| `res://assets/backgrounds/layers/IMBISS_SCHASCHLIK_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1670`; `data/history_shops.json:596`; `data/history_shops.json:612` |
| `res://assets/backgrounds/layers/IMBISS_SCHNITZEL_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1676`; `data/history_shops.json:629`; `data/history_shops.json:645` |
| `res://assets/backgrounds/layers/IMBISS_ZIGEUNERSAUCE_1990_V01.png` | UNKNOWN | `scripts/locations/imbiss_location.gd:36`; `data/asset_registry.json:1700`; `data/history_shops.json:462` |
| `res://assets/backgrounds/layers/JOYSTICK_COMPETITION_PRO_V01.png` | UNKNOWN | `scripts/startup_loader.gd:26`; `scripts/startup_loader.gd:92` |
| `res://assets/backgrounds/layers/KIOSK_APPLAUSE_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1598`; `data/history_shops.json:200` |
| `res://assets/backgrounds/layers/KIOSK_BALISTO_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1586`; `data/history_shops.json:163` |
| `res://assets/backgrounds/layers/KIOSK_BANJO_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1580`; `data/history_shops.json:146` |
| `res://assets/backgrounds/layers/KIOSK_BRAUNER_BAER_1995_V01.png` | UNKNOWN | `data/asset_registry.json:1652`; `data/history_shops.json:369` |
| `res://assets/backgrounds/layers/KIOSK_CAPRI_SONNE_ORANGE_1990_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:16`; `data/asset_registry.json:1544`; `data/history_shops.json:23` |
| `res://assets/backgrounds/layers/KIOSK_CORNETTO_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1634`; `data/history_shops.json:317` |
| `res://assets/backgrounds/layers/KIOSK_CRUNCHIPS_1992_V01.png` | UNKNOWN | `data/asset_registry.json:1616`; `data/history_shops.json:252` |
| `res://assets/backgrounds/layers/KIOSK_FLUTSCHFINGER_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1640`; `data/history_shops.json:334` |
| `res://assets/backgrounds/layers/KIOSK_LIFT_APFELSCHORLE_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1568`; `data/history_shops.json:59` |
| `res://assets/backgrounds/layers/KIOSK_LILA_PAUSE_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1592`; `data/history_shops.json:182` |
| `res://assets/backgrounds/layers/KIOSK_MAGAZINE_SHELF_FRAME_V01.png` | UNKNOWN | `scripts/gfx/kiosk_magazine_layer.gd:17`; `data/asset_registry.json:1529` |
| `res://assets/backgrounds/layers/KIOSK_MAGNUM_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1646`; `data/history_shops.json:351` |
| `res://assets/backgrounds/layers/KIOSK_MEZZO_MIX_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1574`; `data/history_shops.json:76` |
| `res://assets/backgrounds/layers/KIOSK_NICNACS_1993_V01.png` | UNKNOWN | `data/asset_registry.json:1622`; `data/history_shops.json:269` |
| `res://assets/backgrounds/layers/KIOSK_NOGGER_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1628`; `data/history_shops.json:301` |
| `res://assets/backgrounds/layers/KIOSK_POM_BAER_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1610`; `data/history_shops.json:235` |
| `res://assets/backgrounds/layers/KIOSK_PUNICA_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1562`; `data/history_shops.json:42` |
| `res://assets/backgrounds/layers/KIOSK_RAIDER_1990_V01.png` | UNKNOWN | `data/asset_registry.json:1550`; `data/history_shops.json:110` |
| `res://assets/backgrounds/layers/KIOSK_TRIPPLE_CHOC_1992_V01.png` | UNKNOWN | `data/asset_registry.json:1604`; `data/history_shops.json:218` |
| `res://assets/backgrounds/layers/KIOSK_TWIX_1991_V01.png` | UNKNOWN | `data/asset_registry.json:1556`; `data/history_shops.json:127` |
| `res://assets/backgrounds/layers/MAGAZINE_MASTER_UPRIGHT_V01.png` | UNKNOWN | `scripts/gfx/magazine_composer.gd:11` |
| `res://assets/backgrounds/layers/MAGAZINE_MASTER_V02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/gfx/magazine_composer.gd:10`; `scripts/gfx/magazine_editor.gd:15`; `scripts/startup_loader.gd:30`; `scripts/startup_loader.gd:96`; `scripts/ui/listing_type_minigame.gd:244`; `data/asset_registry.json:1406`; `data/magazine_layout.json:3` |
| `res://assets/backgrounds/layers/MODEM_14400_MASTER_V01.png` | UNKNOWN | `data/asset_registry.json:1421`; `data/shop.json:548` |
| `res://assets/backgrounds/layers/MODEM_2400_MASTER_V01.png` | UNKNOWN | `data/shop.json:74` |
| `res://assets/backgrounds/layers/MODEM_9600_MASTER_V01.png` | UNKNOWN | `data/asset_registry.json:1414`; `data/shop.json:740` |
| `res://assets/backgrounds/layers/MONITOR_COMMODORE_1084S_REAR_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:21`; `scripts/gfx/collection_room_layout.gd:15`; `data/collection_room_layout.json:11` |
| `res://assets/backgrounds/layers/MONITOR_COMMODORE_1084S_V02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/startup_loader.gd:22`; `scripts/startup_loader.gd:88`; `scripts/ui/listing_type_minigame.gd:242`; `data/asset_registry.json:1322` |
| `res://assets/backgrounds/layers/MONITOR_COMMODORE_1901_REAR_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:22`; `scripts/gfx/collection_room_layout.gd:19`; `data/collection_room_layout.json:15` |
| `res://assets/backgrounds/layers/MONITOR_COMMODORE_1901_V01.png` | UNKNOWN | `data/asset_registry.json:1341`; `data/shop.json:484` |
| `res://assets/backgrounds/layers/MONITOR_COMMODORE_1942_V01.png` | UNKNOWN | `data/asset_registry.json:1360`; `data/shop.json:500` |
| `res://assets/backgrounds/layers/MONITOR_MULTISYNC_17_V01.png` | UNKNOWN | `data/asset_registry.json:1379`; `data/shop.json:516` |
| `res://assets/backgrounds/layers/MOUSE_AMIGA_V02.png` | UNKNOWN | `scripts/startup_loader.gd:24`; `scripts/startup_loader.gd:90`; `data/asset_registry.json:1396` |
| `res://assets/backgrounds/layers/NOTEBOOK_OPEN_V01.png` | UNKNOWN | `scripts/startup_loader.gd:57`; `scripts/startup_loader.gd:99` |
| `res://assets/backgrounds/layers/PRINTER_COLOR_INKJET_CJ300_V01.png` | UNKNOWN | `data/asset_registry.json:1449`; `data/shop.json:726` |
| `res://assets/backgrounds/layers/PRINTER_DOT_MATRIX_24PIN_COLOR_V01.png` | UNKNOWN | `data/asset_registry.json:1442`; `data/shop.json:756` |
| `res://assets/backgrounds/layers/PRINTER_DOT_MATRIX_24PIN_MONO_V01.png` | UNKNOWN | `data/asset_registry.json:1435`; `data/shop.json:711` |
| `res://assets/backgrounds/layers/PRINTER_DOT_MATRIX_9PIN_V01.png` | UNKNOWN | `data/asset_registry.json:1428`; `data/shop.json:696` |
| `res://assets/backgrounds/layers/PRINTER_LASER_MONO_V01.png` | UNKNOWN | `data/asset_registry.json:1456`; `data/shop.json:533` |
| `res://assets/backgrounds/layers/ROOM_DESK_MASTER_V02.png` | REQUIRED-FOR-RUNTIME, UNKNOWN | `scripts/gfx/object_editor.gd:240`; `scripts/gfx/surface_editor.gd:215`; `scripts/startup_loader.gd:21`; `scripts/startup_loader.gd:87`; `data/asset_registry.json:1231` |
| `res://assets/backgrounds/layers/ROOM_EMPTY_SHELVES_MASTER_V02.png` | REQUIRED-FOR-RUNTIME, UNKNOWN | `scripts/gfx/object_editor.gd:230`; `scripts/gfx/surface_editor.gd:250`; `scripts/startup_loader.gd:20`; `scripts/startup_loader.gd:86`; `data/asset_registry.json:1213` |
| `res://assets/backgrounds/layers/ROOM_GAME_DISPLAY_CABINET_MASTER_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:19`; `scripts/gfx/collection_room_layout.gd:11`; `scripts/gfx/software_box_composer.gd:10`; `data/collection_room_layout.json:7` |
| `res://assets/backgrounds/layers/ROOM_MASTER_1992_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/room_tidy_minigame.gd:8` |
| `res://assets/backgrounds/layers/ROOM_REVERSE_MASTER_1992_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:20`; `scripts/gfx/collection_room_layout.gd:8`; `data/collection_room_layout.json:4` |
| `res://assets/backgrounds/layers/STEREO_COMPACT_CASSETTE_V01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/startup_loader.gd:27`; `scripts/startup_loader.gd:93`; `scripts/ui/mixtape_minigame.gd:5`; `data/asset_registry.json:1463` |
| `res://assets/backgrounds/layers/STEREO_COMPACT_CD_V01.png` | UNKNOWN | `data/asset_registry.json:1477`; `data/shop.json:801` |
| `res://assets/backgrounds/layers/STEREO_COMPONENT_CASSETTE_V01.png` | UNKNOWN | `data/asset_registry.json:1470`; `data/shop.json:786` |
| `res://assets/backgrounds/layers/STEREO_DUAL_CD_V01.png` | UNKNOWN | `data/asset_registry.json:1484`; `data/shop.json:816` |
| `res://assets/backgrounds/layers/TELEPHONE_A1200_AGA_V03.png` | REQUIRED-FOR-PARSE | `scripts/ui/phone_window.gd:11` |
| `res://assets/backgrounds/layers/TELEPHONE_A1200_BASE_V03.png` | REQUIRED-FOR-PARSE | `scripts/ui/phone_window.gd:10` |
| `res://assets/backgrounds/layers/TELEPHONE_A1200_HANDHELD_V03.png` | REQUIRED-FOR-PARSE | `scripts/ui/phone_window.gd:12` |
| `res://assets/backgrounds/layers/TELEPHONE_MASTER_V02.png` | UNKNOWN | `scripts/startup_loader.gd:29`; `scripts/startup_loader.gd:95`; `data/asset_registry.json:1537` |
| `res://assets/backgrounds/layers/ZIP_DRIVE_100MB_V01.png` | UNKNOWN | `data/shop.json:564` |
| `res://assets/backgrounds/locations` | UNKNOWN | `scripts/gfx/object_editor.gd:7`; `scripts/gfx/surface_editor.gd:8` |
| `res://assets/backgrounds/locations/%s_V%02d.png` | UNKNOWN | `scripts/locations/location_base.gd:481` |
| `res://assets/backgrounds/locations/LOCATION_COMPUTER_CLUB_MASTER_V01.png` | UNKNOWN | `data/asset_registry.json:1132` |
| `res://assets/backgrounds/locations/LOCATION_COMPUTER_SHOP_MASTER_V01.png` | UNKNOWN | `scripts/autoload/export_health.gd:14` |
| `res://assets/backgrounds/locations/LOCATION_DEALER_CLEARING_MASTER_V01.png` | UNKNOWN | `data/asset_registry.json:1505` |
| `res://assets/backgrounds/locations/LOCATION_FLEA_MARKET_MASTER_V01.png` | REQUIRED-FOR-RUNTIME | `scenes/editors/FleaMarketActors.tscn:3` |
| `res://assets/backgrounds/locations/LOCATION_IMBISS_MASTER_V01.png` | UNKNOWN | `data/asset_registry.json:1707` |
| `res://assets/backgrounds/locations/LOCATION_IMBISS_MASTER_V02.png` | UNKNOWN | `data/asset_registry.json:1714` |
| `res://assets/backgrounds/locations/LOCATION_KIOSK_MASTER_V02.png` | UNKNOWN | `scripts/autoload/export_health.gd:15`; `data/asset_registry.json:1521` |
| `res://assets/backgrounds/locations/LOCATION_RETRO_MUSEUM_MASTER_V01.png` | UNKNOWN | `data/asset_registry.json:1817` |
| `res://assets/backgrounds/story_props/BROKEN_CRT_REPAIR_BENCH_V01.png` | UNKNOWN | `scripts/locations/sven_home_location.gd:30`; `data/asset_registry.json:48` |
| `res://assets/backgrounds/story_props/DEALER_WITH_TEST_RIG_V01.png` | REQUIRED-FOR-PARSE, REQUIRED-FOR-RUNTIME, UNKNOWN | `scripts/locations/dealer_clearing_location.gd:5`; `scripts/locations/flea_location.gd:7`; `scripts/ui/dealer_window.gd:8`; `scenes/editors/FleaMarketActors.tscn:4`; `data/asset_registry.json:8` |
| `res://assets/backgrounds/story_props/FDD_ALIGNMENT_BENCH_V01.png` | UNKNOWN | `scripts/locations/shop_location.gd:26`; `data/asset_registry.json:40` |
| `res://assets/backgrounds/story_props/FLEA_MYSTERY_CARTON_CLOSED_V01.png` | UNKNOWN | `scripts/ui/flea_window.gd:11`; `data/asset_registry.json:24` |
| `res://assets/backgrounds/story_props/STARTER_CARTON_CLOSED_V01.png` | UNKNOWN | `scripts/startup_loader.gd:59`; `data/asset_registry.json:16`; `data/room_anchors.json:1333` |
| `res://assets/backgrounds/story_props/STARTER_CARTON_OPEN_V01.png` | UNKNOWN | `scripts/startup_loader.gd:60`; `data/asset_registry.json:32`; `data/room_anchors.json:1349` |
| `res://assets/fonts/Topaz_a500_ui.ttf` | REQUIRED-FOR-PARSE, REQUIRED-FOR-RUNTIME, UNKNOWN | `scripts/dev/playtest_report_window.gd:82`; `scripts/games/amiga_game_presentation.gd:9`; `scripts/games/code_red_game_view.gd:31`; `scripts/games/space_lemming_game.gd:82`; `scripts/games/stefan_game_render_base.gd:25`; `scripts/games/turbo_kart_game_view.gd:12`; `scripts/games/wunderwerk_game.gd:15`; `scripts/games/wunderwerk_menu_renderer.gd:9`; `scripts/gfx/kickstart_screen.gd:11`; `scripts/ui/cable_untangle_minigame.gd:577`; `scripts/ui/cracktro_renderer.gd:8`; `scripts/ui/disk_rescue_board.gd:50`; `scripts/ui/listing_type_minigame.gd:299`; `scripts/ui/listing_type_minigame.gd:415`; `scripts/ui/room_tidy_minigame.gd:581`; `scripts/ui/task_board_window.gd:13`; `scripts/ui/wb13.gd:10` |
| `res://assets/icons/favicon.svg` | REQUIRED-FOR-RUNTIME | `project.godot:18` |
| `res://assets/masks/` | UNKNOWN | `scripts/gfx/room_assets.gd:12` |
| `res://assets/masks/FLOPPY_35_DD_BLUE_FRONT_V01_MASK.png` | UNKNOWN | `scripts/gfx/disk_composer.gd:9` |
| `res://assets/minigames/BBS_CARRIER_LAB_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/bbs_carrier_minigame.gd:525` |
| `res://assets/minigames/FLEA_BARGAIN_TABLE_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/bargain_minigame.gd:348` |
| `res://assets/software` | UNKNOWN | `scripts/gfx/disk_editor.gd:54`; `addons/export_runtime_assets/export_runtime_assets.gd:10` |
| `res://assets/software/` | UNKNOWN | `scripts/gfx/disk_composer.gd:62`; `addons/export_runtime_assets/export_runtime_assets.gd:212` |
| `res://assets/software/%s/disk_label.png` | UNKNOWN | `scripts/gfx/disk_editor.gd:61` |
| `res://assets/software/air_strike_usa/box_front.png` | UNKNOWN | `scripts/autoload/export_health.gd:12` |
| `res://assets/software/code_red_protocol` | UNKNOWN | `Content/Software/C/C00_code_red_protocol.json:15` |
| `res://assets/software/code_red_protocol/manual_back.png` | UNKNOWN | `scripts/startup_loader.gd:75` |
| `res://assets/software/code_red_protocol/manual_cover.png` | UNKNOWN | `scripts/startup_loader.gd:74` |
| `res://assets/software/code_red_protocol/orbit_chart_back.png` | UNKNOWN | `scripts/startup_loader.gd:77` |
| `res://assets/software/code_red_protocol/orbit_chart_front.png` | UNKNOWN | `scripts/startup_loader.gd:76` |
| `res://assets/software/syndicate/box_front.png` | UNKNOWN | `scripts/autoload/export_health.gd:11` |
| `res://assets/software/wunderwerk_94` | UNKNOWN | `Content/Software/W/W00_wunderwerk_94.json:26` |
| `res://assets/ui/MENU_TITLE_V%02d.png` | UNKNOWN | `scripts/ui/title_screen.gd:9` |
| `res://assets/ui/achievements` | UNKNOWN | `scripts/ui/achievement_window.gd:7`; `scripts/ui/trophy_wall_window.gd:9` |
| `res://assets/ui/games/code_red/cabinet_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:50` |
| `res://assets/ui/games/code_red/cabinet_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:23`; `scripts/games/code_red_screen_renderer.gd:21` |
| `res://assets/ui/games/code_red/dashboard_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:45` |
| `res://assets/ui/games/code_red/dashboard_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:19` |
| `res://assets/ui/games/code_red/ending_chaos_v01.png` | UNKNOWN | `scripts/startup_loader.gd:44` |
| `res://assets/ui/games/code_red/ending_chaos_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:18` |
| `res://assets/ui/games/code_red/ending_mixed_v01.png` | UNKNOWN | `scripts/startup_loader.gd:43` |
| `res://assets/ui/games/code_red/ending_mixed_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:17` |
| `res://assets/ui/games/code_red/ending_victory_v01.png` | UNKNOWN | `scripts/startup_loader.gd:42` |
| `res://assets/ui/games/code_red/ending_victory_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:16` |
| `res://assets/ui/games/code_red/geo_dashboard_blank_v03.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/code_red_game_view.gd:15`; `scripts/startup_loader.gd:41`; `data/asset_registry.json:1761` |
| `res://assets/ui/games/code_red/media_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:46` |
| `res://assets/ui/games/code_red/media_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:20` |
| `res://assets/ui/games/code_red/optics_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:49` |
| `res://assets/ui/games/code_red/optics_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_screen_renderer.gd:20` |
| `res://assets/ui/games/code_red/plasma_discharge_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:54` |
| `res://assets/ui/games/code_red/plasma_discharge_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:26` |
| `res://assets/ui/games/code_red/projects_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:48` |
| `res://assets/ui/games/code_red/projects_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:22`; `scripts/games/code_red_screen_renderer.gd:19` |
| `res://assets/ui/games/code_red/science_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:47` |
| `res://assets/ui/games/code_red/science_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:21` |
| `res://assets/ui/games/code_red/sky_archive_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:51` |
| `res://assets/ui/games/code_red/sky_archive_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_screen_renderer.gd:22` |
| `res://assets/ui/games/code_red/squatter_sky_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:53` |
| `res://assets/ui/games/code_red/squatter_sky_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:25` |
| `res://assets/ui/games/code_red/strange_sky_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:52` |
| `res://assets/ui/games/code_red/strange_sky_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:24` |
| `res://assets/ui/games/code_red/summit_background_v01.png` | UNKNOWN | `scripts/startup_loader.gd:40` |
| `res://assets/ui/games/code_red/summit_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/code_red_game_view.gd:14` |
| `res://assets/ui/games/code_red/title_background_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/protection_fullscreen_screen.gd:8` |
| `res://assets/ui/games/code_red/title_background_v02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/code_red_game_view.gd:13`; `scripts/startup_loader.gd:39` |
| `res://assets/ui/games/shared/amiga_disk_boot_background_v02.png` | REQUIRED-FOR-PARSE | `scripts/games/amiga_game_presentation.gd:8` |
| `res://assets/ui/games/space_lemming/airlock_runtime_atlas_v01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/space_lemming_art.gd:9`; `scripts/startup_loader.gd:37` |
| `res://assets/ui/games/space_lemming/catwalk_material_v01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/space_lemming_art.gd:10`; `scripts/startup_loader.gd:38` |
| `res://assets/ui/games/space_lemming/crew_actions_runtime_atlas_v02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/space_lemming_art.gd:8`; `scripts/startup_loader.gd:35` |
| `res://assets/ui/games/space_lemming/crew_walk_runtime_atlas_v02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/space_lemming_art.gd:7`; `scripts/startup_loader.gd:34` |
| `res://assets/ui/games/space_lemming/intro_distress_background_v01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/space_lemming_intro.gd:6`; `scripts/startup_loader.gd:36` |
| `res://assets/ui/games/space_lemming/mission_background_v01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/space_lemming_game.gd:16`; `scripts/startup_loader.gd:33` |
| `res://assets/ui/games/space_lemming/title_background_v01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/space_lemming_game.gd:15`; `scripts/startup_loader.gd:32` |
| `res://assets/ui/games/stefan_anthology/atlas_1991_1993_v02.png` | UNKNOWN | `data/stefan_games.json:9`; `data/stefan_games.json:20`; `data/stefan_games.json:31`; `data/stefan_games.json:43`; `data/stefan_games.json:54`; `data/stefan_games.json:65`; `data/stefan_games.json:77`; `data/stefan_games.json:88`; `data/stefan_games.json:99` |
| `res://assets/ui/games/stefan_anthology/atlas_1994_1996_v02.png` | UNKNOWN | `data/stefan_games.json:111`; `data/stefan_games.json:122`; `data/stefan_games.json:134`; `data/stefan_games.json:146`; `data/stefan_games.json:157`; `data/stefan_games.json:168`; `data/stefan_games.json:180`; `data/stefan_games.json:191`; `data/stefan_games.json:202` |
| `res://assets/ui/games/stefan_anthology/atlas_1997_1999_v02.png` | UNKNOWN | `data/stefan_games.json:214`; `data/stefan_games.json:225`; `data/stefan_games.json:236`; `data/stefan_games.json:248`; `data/stefan_games.json:259`; `data/stefan_games.json:271`; `data/stefan_games.json:283`; `data/stefan_games.json:294`; `data/stefan_games.json:305` |
| `res://assets/ui/games/turbo_kart/stunt_title_background_v01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/games/turbo_kart_game_view.gd:11`; `scripts/startup_loader.gd:31` |
| `res://assets/ui/games/wunderwerk_94/sprites/characters_ocs_v01.png` | UNKNOWN | `scripts/games/wunderwerk_renderer.gd:10` |
| `res://assets/ui/games/wunderwerk_94/sprites/paths_ocs_v01.png` | UNKNOWN | `scripts/games/wunderwerk_renderer.gd:14` |
| `res://assets/ui/games/wunderwerk_94/sprites/rides_extra_ocs_v01.png` | UNKNOWN | `scripts/games/wunderwerk_renderer.gd:15` |
| `res://assets/ui/games/wunderwerk_94/sprites/rides_shops_ocs_v01.png` | UNKNOWN | `scripts/games/wunderwerk_renderer.gd:9` |
| `res://assets/ui/games/wunderwerk_94/sprites/scenery_ocs_v01.png` | UNKNOWN | `scripts/games/wunderwerk_renderer.gd:12` |
| `res://assets/ui/games/wunderwerk_94/sprites/services_ocs_v01.png` | UNKNOWN | `scripts/games/wunderwerk_renderer.gd:13` |
| `res://assets/ui/games/wunderwerk_94/sprites/terrain_ocs_v01.png` | UNKNOWN | `scripts/games/wunderwerk_renderer.gd:11` |
| `res://assets/ui/games/wunderwerk_94/title_background_ocs_v01.png` | REQUIRED-FOR-PARSE | `scripts/games/wunderwerk_menu_renderer.gd:7` |
| `res://assets/ui/hud/%s.png` | UNKNOWN | `scripts/gfx/sprites.gd:66` |
| `res://assets/ui/hud/etiketten.png` | UNKNOWN | `data/shop.json:19` |
| `res://assets/ui/hud/reinigung.png` | UNKNOWN | `data/shop.json:33` |
| `res://assets/ui/kickstart_screen.png` | UNKNOWN | `data/boot.json:10` |
| `res://assets/ui/loading/SOMMER90_LOADING_MASTER_V01.png` | UNKNOWN | `scripts/startup_loader.gd:14`; `scripts/ui/loading_screen_visual.gd:7` |
| `res://assets/ui/magazines/` | UNKNOWN | `addons/export_runtime_assets/export_runtime_assets.gd:17` |
| `res://assets/ui/magazines/amiga_joker/1990` | UNKNOWN | `scripts/gfx/magazine_composer.gd:12`; `scripts/gfx/magazine_editor.gd:16` |
| `res://assets/ui/magazines/amiga_joker/1990/amiga_joker_1990_06_07_turrican.png` | UNKNOWN | `scripts/autoload/export_health.gd:17` |
| `res://assets/ui/magazines/generated_era` | UNKNOWN | `scripts/gfx/magazine_composer.gd:13` |
| `res://assets/ui/minigames/CABLE_UNTANGLE_GRUBER_BENCH_MASTER_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/cable_untangle_minigame.gd:8` |
| `res://assets/ui/minigames/HARDWARE_SERVICE_A1011_OPEN_V02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/hardware_assembly_minigame.gd:309`; `data/asset_registry.json:1737` |
| `res://assets/ui/minigames/HARDWARE_SERVICE_A1200_OPEN_V02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/hardware_assembly_minigame.gd:308`; `scripts/ui/shop_diagnosis_bench.gd:14`; `data/asset_registry.json:1753` |
| `res://assets/ui/minigames/HARDWARE_SERVICE_A500_OPEN_V02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/hardware_assembly_minigame.gd:306`; `scripts/ui/shop_diagnosis_bench.gd:12`; `data/asset_registry.json:1729` |
| `res://assets/ui/minigames/HARDWARE_SERVICE_A600_OPEN_V02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/hardware_assembly_minigame.gd:307`; `scripts/ui/shop_diagnosis_bench.gd:13`; `data/asset_registry.json:1745` |
| `res://assets/ui/minigames/LISTING_DESK_EMPTY_MASTER_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/label_designer.gd:291`; `scripts/ui/listing_type_minigame.gd:241` |
| `res://assets/ui/minigames/ROOM_TIDY_PROPS_SHEET_V01.png` | REQUIRED-FOR-PARSE | `scripts/ui/room_tidy_minigame.gd:9` |
| `res://assets/ui/minigames/box_sort_board_v01.png` | UNKNOWN | `data/asset_registry.json:1165` |
| `res://assets/ui/minigames/box_sort_board_v02.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/box_sort_minigame.gd:9`; `data/asset_registry.json:1180` |
| `res://assets/ui/minigames/drive_clean_board_v01.png` | REQUIRED-FOR-PARSE, UNKNOWN | `scripts/ui/drive_clean_minigame.gd:7`; `data/asset_registry.json:1195` |
| `res://assets/ui/minigames/household/atlases/HOUSEHOLD_GROCERIES_ATLAS_AGA_V01.png` | UNKNOWN | `data/aga_sprite_frames.json:28` |
| `res://assets/ui/minigames/household/atlases/HOUSEHOLD_PROPS_ATLAS_AGA_V02.png` | UNKNOWN | `data/aga_sprite_frames.json:6` |
| `res://assets/ui/minigames/household/household_car_wash_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:19` |
| `res://assets/ui/minigames/household/household_dishes_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:16` |
| `res://assets/ui/minigames/household/household_lawn_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:20` |
| `res://assets/ui/minigames/household/household_room_bins_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:15` |
| `res://assets/ui/minigames/household/household_shopping_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:18` |
| `res://assets/ui/minigames/household/household_vacuum_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:17` |
| `res://assets/ui/minigames/household/sprites/household_carwash_tools_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:28` |
| `res://assets/ui/minigames/household/sprites/household_grass_tuft_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:25` |
| `res://assets/ui/minigames/household/sprites/household_mower_red_aga_v02.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:24` |
| `res://assets/ui/minigames/household/sprites/household_rubbish_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:30` |
| `res://assets/ui/minigames/household/sprites/household_shopping_basket_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:27` |
| `res://assets/ui/minigames/household/sprites/household_sorting_items_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:29` |
| `res://assets/ui/minigames/household/sprites/household_vacuum_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/household_sprint_stage.gd:26` |
| `res://assets/ui/minigames/job_shift/atlases/JOB_SHIFT_PROPS_ATLAS_AGA_V01.png` | UNKNOWN | `data/aga_sprite_frames.json:46` |
| `res://assets/ui/minigames/job_shift/job_code_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/job_shift_stage.gd:25` |
| `res://assets/ui/minigames/job_shift/job_flyer_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/job_shift_stage.gd:22` |
| `res://assets/ui/minigames/job_shift/job_repair_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/job_shift_stage.gd:24` |
| `res://assets/ui/minigames/job_shift/job_route_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/job_shift_stage.gd:21` |
| `res://assets/ui/minigames/job_shift/job_stockroom_aga_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/job_shift_stage.gd:23` |
| `res://assets/ui/minigames/joystick_repair_board_v01.png` | REQUIRED-FOR-PARSE | `scripts/ui/joystick_repair_minigame.gd:7` |
| `res://assets/ui/newspapers` | UNKNOWN | `scripts/ui/newspaper_window.gd:11` |
| `res://assets/ui/newspapers/` | UNKNOWN | `addons/export_runtime_assets/export_runtime_assets.gd:18` |
| `res://assets/ui/scene/SCENE_BACKDROP_AGA_V01.png` | UNKNOWN | `scripts/ui/scene_generation_catalog.gd:41` |
| `res://assets/ui/scene/SCENE_BACKDROP_ECS_V01.png` | UNKNOWN | `scripts/ui/scene_generation_catalog.gd:27` |
| `res://assets/ui/scene/SCENE_BACKDROP_OCS_V01.png` | UNKNOWN | `scripts/ui/scene_generation_catalog.gd:13` |
| `res://assets/ui/transitions/SOMMER90_SLEEP_MASTER_V01.png` | UNKNOWN | `scripts/ui/sleep_transition_screen.gd:18` |
| `res://assets/ui/transitions/SOMMER90_SLEEP_RAIN_MASTER_V02.png` | UNKNOWN | `scripts/ui/sleep_transition_screen.gd:19` |
| `res://data/bbs_archive.json` | UNKNOWN | `scripts/autoload/bbs_scene.gd:13` |
| `res://data/mod_bible/` | UNKNOWN | `scripts/autoload/mod_bible.gd:11` |
| `res://data/narrative/lines` | UNKNOWN | `scripts/autoload/narrative_manager.gd:14` |
| `res://data/sommer_suite_implementation_map.json` | UNKNOWN | `scripts/data/sommer_suite_runtime_catalog.gd:8` |
| `res://development/uncleared_music/MUS_SPACE_DEBRIS_V01.mod` | UNKNOWN | `scripts/autoload/export_health.gd:110` |
| `res://export_runtime_manifest.json` | UNKNOWN | `scripts/autoload/export_health.gd:23`; `addons/export_runtime_assets/export_runtime_assets.gd:11` |
| `res://locale` | UNKNOWN | `scripts/autoload/localization.gd:40` |
| `res://locale/game.de.translation` | REQUIRED-FOR-RUNTIME | `project.godot:99` |
| `res://locale/game.en.translation` | REQUIRED-FOR-RUNTIME | `project.godot:99` |
| `res://scripts/autoload` | UNKNOWN | `scripts/autoload/player_stats.gd:15`; `scripts/autoload/player_stats_defs.gd:10`; `scripts/autoload/time_clock.gd:6` |
