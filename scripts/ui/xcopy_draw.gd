class_name XCopyDraw
## XCopyDraw — reine Zeichenschicht des X-COPY-Bildschirms (aus xcopy_screen.gd
## ausgelagert, Zeilen-Budget). Statische Maler, die den XCopyScreen als `ed`
## erhalten: zeichnen über ed.draw_* und lesen dessen Zustand (ed._track,
## ed._phase, ed.marble_cache …). Einstieg: XCopyDraw.render(ed) aus ed._draw().
# ----------------------------------------------------------------- Zeichnen

static func render(ed) -> void:
	if ed.size.x < 8.0 or ed.size.y < 8.0:
		return  # noch nicht ausgelegt (SubViewport-Größe kommt später)
	var font: Font = ed.get_theme_default_font()
	if ed.is_sommer_copy():
		_draw_sommer_copy_background(ed)
	elif ed.pro:
		ed.draw_rect(Rect2(Vector2.ZERO, ed.size), Color8(6, 6, 10))
		ed.draw_rect(ed._R(Rect2(4, 4, 632, 392)), Color(0, 0, 0, 0), false)
		ed.draw_rect(ed._R(Rect2(4, 4, 632, 392)), Color8(120, 150, 170), false, 1.0)
	else:
		_draw_marble(ed)
	_draw_title(ed, font)
	_draw_menu(ed, font)
	_draw_lcd(ed, font)
	_draw_actions(ed, font)
	_draw_workflow(ed, font)
	_draw_drives(ed, font)
	var accent: Color = Color8(102, 242, 202) if ed.is_sommer_copy() else (Color8(150, 180, 210) if ed.pro else ed.WHITE)
	_draw_grid(ed, font, "UPPER" if ed.pro else "OBERSEITE", 330, 150)
	_draw_grid(ed, font, "LOWER" if ed.pro else "UNTERSEITE", 486, 150)
	_text(ed, font, "TIME: %02d:%02d" % [floori(ed._time / 60.0), int(ed._time) % 60], 556, 366, 10, ed.GREEN)
	# Status + freier Speicher
	if ed.pro or ed.is_sommer_copy():
		ed.draw_rect(ed._R(Rect2(8, 372, 624, 24)), Color8(4, 8, 16))
		ed.draw_rect(ed._R(Rect2(8, 372, 624, 24)), Color8(90, 120, 150), false, 1.0)
	else:
		ed.draw_rect(ed._R(Rect2(8, 372, 624, 24)), Color(0, 0, 0, 0.45))
	_text(ed, font, ed._status, 16, 383, 9, accent)
	_text(ed, font, ed._free_mem(), 16, 395, 12, Color8(102, 242, 202) if ed.is_sommer_copy() else (ed.CYAN if ed.pro else ed.GREEN))
	if ed._await_insert != "":
		_draw_insert_prompt(ed, font)
	_draw_scanlines(ed)


## Moderner Bedienvertrag innerhalb der historischen Oberflaeche: Das Original-
## Layout bleibt erhalten, aber Auftrag, Diagnoseachsen und naechster Schritt
## sind nicht mehr in einer winzigen Statuszeile versteckt.
static func _draw_workflow(ed, font: Font) -> void:
	var frame := Rect2(10, 130, 620, 34)
	var accent: Color = ed.CYAN
	if ed.operation_kind == "backup":
		accent = ed.YELLOW
	if not ed._diagnosis.is_empty():
		accent = ed.RED if ed._service_action == "rescue" else ed.GREEN
	ed.draw_rect(ed._R(frame), Color(0.015, 0.025, 0.055, 0.92))
	ed.draw_rect(ed._R(frame), accent, false, 1.0)
	_text(ed, font, ed.workflow_title(), 16, 143, 10, accent)
	var detail_width: int = 465 if not ed._service_action.is_empty() else 600
	var detail: String = str(ed.workflow_detail()).left(floori(float(detail_width) / 5.0))
	_text(ed, font, detail, 16, 158, 8, ed.WHITE)
	if not ed._service_action.is_empty():
		var action_rect := Rect2(492, 134, 132, 25)
		_button3d(ed, action_rect, Color8(42, 86, 104), ed._service_btn.button_pressed)
		_text_c(ed, font, ed._service_label, 492, 624, 151, 8, accent)


## Disketten-Wechsel-Aufforderung (Einlaufwerk): großer blinkender Kasten mit
## Diskettensymbol — QUELLE (orange) oder ZIEL/leer (cyan) einlegen.
static func _draw_insert_prompt(ed, font: Font) -> void:
	var src: bool = ed._await_insert == "source"
	var col: Color = Color8(240, 170, 60) if src else Color8(120, 210, 240)
	var box := Rect2(150, 150, 340, 96)
	ed.draw_rect(ed._R(box), Color8(8, 8, 14))
	var blink: bool = fmod(ed._swap_blink, 0.9) < 0.55
	ed.draw_rect(ed._R(box), col if blink else Color8(90, 96, 112), false, 2.0)
	# Diskettensymbol links
	var dx := box.position.x + 24.0
	var dy := box.position.y + 28.0
	ed.draw_rect(ed._R(Rect2(dx, dy, 40, 40)), col)
	ed.draw_rect(ed._R(Rect2(dx + 8, dy + 2, 24, 12)), Color8(8, 8, 14))          # Schieber
	ed.draw_rect(ed._R(Rect2(dx + 20, dy + 3, 5, 10)), col)
	ed.draw_rect(ed._R(Rect2(dx + 6, dy + 20, 28, 16)), Color8(236, 236, 228))    # Etikett
	var line1: String = ("INSERT SOURCE DISK" if ed.pro else "ORIGINAL EINLEGEN") if src \
		else ("INSERT BLANK DISK" if ed.pro else "LEERDISKETTE EINLEGEN")
	var line2: String = ("(the disk you copy FROM)" if ed.pro else "(die Disk, die du KOPIERST)") if src \
		else ("(the disk you copy TO)" if ed.pro else "(die Disk, die BESPIELT wird)")
	var line3: String = "click drive / press START" if ed.pro else "Laufwerk anklicken / START"
	_text(ed, font, line1, box.position.x + 84, box.position.y + 30, 12, col)
	_text(ed, font, line2, box.position.x + 84, box.position.y + 48, 9, ed.WHITE)
	if blink:
		_text(ed, font, line3, box.position.x + 84, box.position.y + 74, 10, Color8(200, 210, 225))



## Auflösungs-Emulation: dezente Scanlines über dem ganzen Bild (dazu der globale
## CRT-Shader, der automatisch angeht, wenn man am Monitor sitzt).
static func _draw_scanlines(ed) -> void:
	if not bool(SettingsManager.value("scanlines")):
		return
	var step := maxf(2.0, round(ed._sy() * 3.0))   # ~alle 3 virtuellen Pixel
	var y := 0.0
	while y < ed.size.y:
		ed.draw_rect(Rect2(0, y, ed.size.x, maxf(1.0, step * 0.34)), Color(0, 0, 0, 0.14))
		y += step



static func _draw_marble(ed) -> void:
	ed.draw_rect(Rect2(Vector2.ZERO, ed.size), Color8(126, 78, 140))
	# Deterministisches Muster (fester Seed): nur bei Größenänderung neu rechnen,
	# statt ed.pro Frame RNG + 40 randf zu allozieren.
	if ed.marble_cache.is_empty() or ed.marble_cache_size != ed.size:
		_rebuild_marble(ed)
	for m: Dictionary in ed.marble_cache:
		ed.draw_circle(m["p"], m["r"], m["c"])


static func _draw_sommer_copy_background(ed) -> void:
	ed.draw_rect(Rect2(Vector2.ZERO, ed.size), Color8(3, 12, 28))
	# ECS-inspirierte Rasterflaeche: bewusst ruhiger als das spaetere AGA-UI,
	# aber deutlich als eigener 1992er Build lesbar.
	for y in range(0, 400, 16):
		var phase := float(y) / 400.0
		var col := Color(0.02, 0.18 + phase * 0.08, 0.25 + phase * 0.12, 0.26)
		ed.draw_rect(ed._R(Rect2(0, y, 640, 8)), col)
	for x in range(0, 640, 32):
		ed.draw_rect(ed._R(Rect2(x, 0, 1, 400)), Color(0.15, 0.8, 0.75, 0.08))



static func _rebuild_marble(ed) -> void:
	ed.marble_cache.clear()
	ed.marble_cache_size = ed.size
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0C0FFEE
	for i in 40:
		var p := Vector2(rng.randf() * ed.size.x, rng.randf() * ed.size.y)
		var rad: float = rng.randf_range(20, 70) * ed._sy()
		var c: Color = Color(0.62, 0.42, 0.68, 0.10) if i % 2 == 0 else Color(0.36, 0.21, 0.43, 0.12)
		ed.marble_cache.append({"p": p, "r": rad, "c": c})



static func _draw_title(ed, font: Font) -> void:
	if ed.is_sommer_copy():
		ed.draw_rect(ed._R(Rect2(4, 2, 632, 40)), Color8(5, 27, 49))
		ed.draw_rect(ed._R(Rect2(4, 2, 632, 40)), Color8(68, 226, 210), false, 1.0)
		_text_c(ed, font, "SOMMER COPY 92", 8, 632, 27, 24, Color8(226, 255, 246))
		_text_c(ed, font,
			"PROTOTYP · ECS · EIN-PASS · VERIFY" if ed.is_sommer_copy_prototype() else "EIGENBAU · ECS · EIN-PASS · VERIFY",
			8, 632, 39, 8, Color8(102, 242, 202))
	elif ed.pro:
		# Titelleiste mit Gadgets (kompakt, damit die Menüleiste bei y44 passt)
		ed.draw_rect(ed._R(Rect2(4, 2, 632, 12)), Color8(38, 74, 96))
		ed.draw_rect(ed._R(Rect2(4, 2, 632, 12)), Color8(120, 150, 170), false, 1.0)
		ed.draw_rect(ed._R(Rect2(6, 4, 8, 8)), Color8(120, 150, 170))
		_text_c(ed, font, "X-COPY V6.7      BY  QUASAR/LIBERTY", 8, 632, 11, 8, Color8(206, 224, 238))
		ed.draw_rect(ed._R(Rect2(610, 4, 9, 8)), Color8(120, 150, 170))
		ed.draw_rect(ed._R(Rect2(621, 4, 9, 8)), Color8(120, 150, 170))
		# ABOUT / INFO beveled Buttons
		_bevel(ed, Rect2(66, 16, 112, 26), Color8(158, 182, 200))
		_text_c(ed, font, "ABOUT", 66, 178, 33, 14, Color8(20, 30, 40))
		_bevel(ed, Rect2(462, 16, 112, 26), Color8(158, 182, 200))
		_text_c(ed, font, "INFO", 462, 574, 33, 14, Color8(20, 30, 40))
		# Chrom-Logo „X-COPY professional" — zentriert in der Lücke dazwischen
		_chrome_logo(ed, font)
	else:
		_text(ed, font, "X-COPY", 236, 34, 34, ed.WHITE)
		var letters := "Cachet"
		for i in letters.length():
			_text(ed, font, letters[i], 14 + i * 15, 22, 15, ed.CACHET[i % ed.CACHET.size()])
		_text(ed, font, "ASi", 596, 22, 15, Color8(242, 212, 64))
		_text(ed, font, "©1988-1993", 556, 40, 9, ed.WHITE)



static func _chrome_logo(ed, font: Font) -> void:
	# Dunkles, geripptes Logo-Panel zwischen ABOUT und INFO (kompakt: y15–43)
	var panel := Rect2(190, 15, 260, 28)
	ed.draw_rect(ed._R(panel), Color8(14, 18, 26))
	for gx in range(int(panel.position.x) + 4, int(panel.position.x + panel.size.x) - 2, 6):
		ed.draw_rect(ed._R(Rect2(gx, panel.position.y + 2, 1, panel.size.y - 4)), Color8(30, 40, 54))
	ed.draw_rect(ed._R(panel), Color8(90, 110, 130), false, 1.0)
	# Chrom-„X-COPY" (Schatten → Mittelton → Highlight), zentriert im Panel
	var l := panel.position.x
	var r := panel.position.x + panel.size.x
	_text_c(ed, font, "X-COPY", l + 1, r + 1, 34, 19, Color8(16, 22, 34))
	_text_c(ed, font, "X-COPY", l, r, 33, 19, Color8(120, 140, 160))
	_text_c(ed, font, "X-COPY", l - 1, r - 1, 32, 19, Color8(238, 244, 252))
	_text_c(ed, font, "professional", l, r, 41, 8, Color8(150, 170, 190))



static func _draw_menu(ed, font: Font) -> void:
	var bar: Color = Color8(5, 31, 50) if ed.is_sommer_copy() else (Color8(8, 14, 26) if ed.pro else Color8(28, 38, 92))
	ed.draw_rect(ed._R(Rect2(8, 44, 624, 18)), bar)
	var dot: Color = Color8(102, 242, 202) if ed.is_sommer_copy() else (Color8(240, 150, 50) if ed.pro else Color8(84, 202, 240))
	for m in ed._menu_btns:
		ed.draw_circle(ed._V(m["x"] - 8, 54), 2.5 * ed._sy(), dot)
		_text(ed, font, m["label"], m["x"], 57, 10, ed.WHITE)



static func _draw_lcd(ed, font: Font) -> void:
	ed.draw_rect(ed._R(Rect2(8, 66, 624, 26)), Color8(6, 12, 28) if ed.pro else Color8(18, 22, 46))
	if ed.pro:
		ed.draw_rect(ed._R(Rect2(8, 66, 624, 26)), Color8(90, 120, 150), false, 1.0)
	var col: Color = ed._lcd_color()
	_text(ed, font, ed.MODE_NAMES[ed._mode], 16, 84, 13, col)
	var vals: Array = ed._lcd_values()
	if ed._copying or ed._track > 0:
		vals[0] = "%02d" % mini(ed._track, ed.TRACKS - 1)   # Spurzähler läuft mit
	var vx := [176.0, 214.0, 258.0, 306.0, 350.0, 456.0, 546.0]
	var arrow: Color = Color8(120, 180, 240) if ed.pro else Color8(206, 120, 220)
	for i in vals.size():
		_text(ed, font, vals[i], vx[i], 85, 13, col)
		if i in [0, 1, 2, 3, 5]:  # Spin-Felder: Auf/Ab-Pfeile
			_text(ed, font, "▲", vx[i] + 2, 74, 7, arrow)
			_text(ed, font, "▼", vx[i] + 2, 92, 7, arrow)
	# Cursor-/Richtungspfeil links neben den Werten
	_text(ed, font, "←" if not ed.pro else "↕", 150, 85, 12, ed.CYAN)



static func _draw_actions(ed, font: Font) -> void:
	for a in ed._actions:
		var r: Rect2 = a["rect"]
		var b: Button = a["button"]
		var down: bool = b.button_pressed
		var base: Color = Color8(24, 78, 88) if ed.is_sommer_copy() else (Color8(52, 66, 88) if ed.pro else Color8(52, 62, 118))
		if b.is_hovered():
			base = base.lightened(0.16)
		_button3d(ed, r, base, down)
		var oy: float = 16.0 if down else 15.0
		_text_c(ed, font, a["id"], r.position.x, r.position.x + r.size.x, r.position.y + oy, 10, a["color"])



## Erhabener 3D-Knopf (Amiga-GUI-Stil): Licht oben/links, Schatten unten/rechts;
## beim Drücken invertiert.
static func _button3d(ed, r: Rect2, base: Color, down: bool) -> void:
	UiPaint.button3d(ed, ed._R, r, base, down)



static func _draw_drives(ed, font: Font) -> void:
	var top_y: float = 176.0 if ed.pro else 190.0
	var bot_y: float = 306.0 if ed.pro else 292.0
	_text(ed, font, "SOURCE DRIVES" if ed.pro else "QUELL LAUFWERK", 30, top_y, 11, ed.WHITE)
	for d in ed._drives:
		_draw_drive(ed, font, d)
	_text(ed, font, "DESTINATION DRIVES" if ed.pro else "ZIEL LAUFWERKE", 30, bot_y, 11, ed.WHITE)



static func _draw_drive(ed, font: Font, d: Dictionary) -> void:
	var r: Rect2 = d["rect"]
	var sel: bool = int(d["idx"]) == ed._src_drive
	var avail: bool = not d["button"].disabled
	# Laufwerks-Aktivität wie am echten Gerät: beim LESEN leuchtet die Quelle,
	# beim SCHREIBEN das Ziel (Lämpchen/LED an, solange der Motor läuft).
	var src_busy: bool = avail and ed._copying and ed._phase == "read" and sel
	var dst_busy: bool = avail and ed._copying and ed._phase == "write" \
		and int(d["idx"]) == ed._dst_drive
	if ed.pro:
		# Klickbare Lämpchen: oben Quelle, unten Ziel (leuchten je nach Auswahl)
		_bulb(ed, r.position.x + r.size.x * 0.5, r.position.y - 13,
			avail and (sel or src_busy))
		_bulb(ed, r.position.x + r.size.x * 0.5, r.position.y + r.size.y + 13,
			avail and (int(d["idx"]) == ed._dst_drive or dst_busy))
		# Diskette (blau) mit grünem Reiter bei Auswahl
		ed.draw_rect(ed._R(r), Color8(70, 100, 200) if avail else Color8(40, 56, 110))
		ed.draw_rect(ed._R(Rect2(r.position.x + 6, r.position.y + 3, r.size.x - 12, 10)),
			Color8(90, 220, 110) if sel else Color8(200, 200, 200))
		ed.draw_rect(ed._R(Rect2(r.position.x + 10, r.position.y + 44, r.size.x - 20, r.size.y - 50)), Color8(30, 40, 70))
		_text_c(ed, font, "DF%d" % d["idx"], r.position.x, r.position.x + r.size.x, r.position.y + 28, 10, ed.WHITE)
	else:
		var body := Color8(234, 152, 52) if sel else (Color8(74, 104, 204) if avail else Color8(48, 66, 110))
		ed.draw_rect(ed._R(r), body)
		ed.draw_rect(ed._R(r), Color(0, 0, 0, 0.5), false, 1.0)
		# LED: leuchtet grün, solange dieses Laufwerk arbeitet (Lesen/Schreiben)
		var led: Color = Color8(60, 70, 90)
		if src_busy or dst_busy:
			led = Color8(120, 240, 120)
		elif sel:
			led = Color8(240, 170, 60)
		ed.draw_circle(ed._V(r.position.x + 8, r.position.y + 8), 3.0 * ed._sy(), led)
		ed.draw_rect(ed._R(Rect2(r.position.x + 8, r.position.y + 34, r.size.x - 16, 8)), Color8(20, 24, 40))
		_text_c(ed, font, "DRIVE", r.position.x, r.position.x + r.size.x, r.position.y + 22, 9, ed.WHITE)
		_text_c(ed, font, str(d["idx"]), r.position.x, r.position.x + r.size.x, r.position.y + 60, 11, ed.WHITE)



static func _bulb(ed, x: float, y: float, on: bool) -> void:
	ed.draw_circle(ed._V(x, y), 5.0 * ed._sy(), Color8(240, 160, 50) if on else Color8(150, 155, 165))
	ed.draw_rect(ed._R(Rect2(x - 2, y + 3, 4, 4)), Color8(90, 90, 100))



## Spur-Raster exakt wie das Original (recherchiert: Cachet-Handbuch +
## X-Copy Shrine): 80 Spuren = 10 Spalten × 8 Reihen (Spur 34 = Reihe 3,
## Spalte 4). Pro Spur erscheint eine „0": GELB nach dem Lesen (Spur liegt im
## RAM-Puffer), GRÜN sobald sie geschrieben ist — so sieht man bei mehreren
## Durchgängen genau, wo die Kopie steht. Bei Fehlern steht statt ihr eine
## ROTE Ziffer (Fehlercode, „8" = Verify-Fehler beim Schreiben). BAMCOPY+
## lässt unbelegte Spuren leer; PRÜFEN färbt direkt grün (Lese-Check ok).
## Die gerade bearbeitete Spur trägt einen hellen Cursor-Rahmen.
static func _draw_grid(ed, font: Font, label: String, gx: float, gy: float) -> void:
	_text(ed, font, label, gx + 6, gy + 10, 10, ed.WHITE)
	var cols := 10
	var rows := 8
	var cell := 13.0
	var ox := gx + 12
	var oy := gy + 26
	for c in cols:
		_text(ed, font, str(c), ox + c * cell + 2, oy - 3, 8, ed.CYAN)
	for rr in rows:
		_text(ed, font, str(rr), gx + 2, oy + rr * cell + 10, 8, ed.CYAN)
	ed.draw_rect(ed._R(Rect2(ox, oy, cols * cell, rows * cell)), ed.GRID_BG)
	var n := 0
	for rr in rows:
		for c in cols:
			var cr := Rect2(ox + c * cell, oy + rr * cell, cell, cell)
			if n < ed._read_done and not ed._bam_skip.has(n):
				var error_reached: bool = n in ed._err_cells \
					and (ed._check_only or n < ed._write_done)
				if error_reached:
					_text_c(ed, font, "8", cr.position.x, cr.position.x + cr.size.x,
						cr.position.y + 10.5, 10, ed.RED)
				else:
					var written: bool = n < ed._write_done or ed._check_only
					_text_c(ed, font, "0", cr.position.x, cr.position.x + cr.size.x,
						cr.position.y + 10.5, 10, ed.GREEN if written else ed.YELLOW)
			ed.draw_rect(ed._R(cr), ed.GRID_LINE, false, 1.0)
			if ed._copying and ed._gap <= 0.0 and n == ed._track:
				ed.draw_rect(ed._R(cr), ed.WHITE, false, maxf(1.0, ed._sy()))
			n += 1



static func _bevel(ed, r: Rect2, base: Color) -> void:
	ed.draw_rect(ed._R(r), base)
	ed.draw_rect(ed._R(Rect2(r.position.x, r.position.y, r.size.x, 1)), base.lightened(0.4))
	ed.draw_rect(ed._R(Rect2(r.position.x, r.position.y, 1, r.size.y)), base.lightened(0.4))
	ed.draw_rect(ed._R(Rect2(r.position.x, r.position.y + r.size.y - 1, r.size.x, 1)), base.darkened(0.4))
	ed.draw_rect(ed._R(Rect2(r.position.x + r.size.x - 1, r.position.y, 1, r.size.y)), base.darkened(0.4))



static func _text(ed, font: Font, s: String, x: float, y: float, fsize: int, col: Color) -> void:
	ed.draw_string(font, ed._V(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, int(fsize * ed._sy())), col)



static func _text_c(ed, font: Font, s: String, x0: float, x1: float, y: float, fsize: int, col: Color) -> void:
	ed.draw_string(font, ed._V(x0, y), s, HORIZONTAL_ALIGNMENT_CENTER, (x1 - x0) * ed._sx(), maxi(1, int(fsize * ed._sy())), col)
