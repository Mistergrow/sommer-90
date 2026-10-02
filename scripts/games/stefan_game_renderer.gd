class_name StefanGameRenderer
extends RefCounted
## Gemeinsame Amiga-Zeichenpipeline der Stefan-Anthologie. Die neun Modi
## besitzen eigene Spielfeldsprache; nur Raster, Schrift und Hardwarevertrag
## werden geteilt. OCS -> ECS -> AGA ist eine echte visuelle Entwicklung.
## Logische Aufloesung: 320x200, danach ausschliesslich Nearest-Neighbour.
##
## Diese Datei ist seit dem Zeilenbudget-Split nur noch die Fassade. Der Inhalt
## liegt in vier Teilen mit streng linearer preload-Kette (keine Zirkel):
##   stefan_game_render_base.gd  Palette, Schrift, Primitive
##   stefan_game_sprites.gd      Blitter-Sprites            (braucht Base)
##   stefan_game_modes.gd        Spielfeld + neun Genres    (braucht Base, Sprites)
##   stefan_game_screens.gd      Vollbild-Masken            (braucht Base)
## Die Teile tragen bewusst KEIN class_name (Klassen-Cache-Race mit dem
## laufenden Editor); sie werden ausschliesslich per Pfad-preload eingebunden.

const Base := preload("res://scripts/games/stefan_game_render_base.gd")
const Modes := preload("res://scripts/games/stefan_game_modes.gd")
const Screens := preload("res://scripts/games/stefan_game_screens.gd")

## stefan_game.gd liest diese beiden Farben direkt ueber die Fassade
## (Renderer.GREEN / Renderer.RED fuer die Partikelstoesse). Sie bleiben deshalb
## hier sichtbar, auch wenn die Palette selbst in Base liegt.
const GREEN := Base.GREEN
const RED := Base.RED


static func accent(definition: Dictionary) -> Color:
	return Base.accent(definition)


static func draw_boot(canvas: CanvasItem, definition: Dictionary, phase: float) -> void:
	Screens.draw_boot(canvas, definition, phase)


static func draw_title(canvas: CanvasItem, texture: Texture2D, definition: Dictionary,
		menu: Array[String], selected: int, pulse: float, record: Dictionary) -> void:
	Screens.draw_title(canvas, texture, definition, menu, selected, pulse, record)


static func draw_briefing(canvas: CanvasItem, texture: Texture2D, definition: Dictionary) -> void:
	Screens.draw_briefing(canvas, texture, definition)


static func draw_play(canvas: CanvasItem, _texture: Texture2D, definition: Dictionary,
		model: StefanGameModel, anim: float, flash: float, particles: Array[Dictionary]) -> void:
	Modes.draw_play(canvas, _texture, definition, model, anim, flash, particles)


static func draw_pause(canvas: CanvasItem, definition: Dictionary) -> void:
	Screens.draw_pause(canvas, definition)


static func draw_results(canvas: CanvasItem, texture: Texture2D, definition: Dictionary,
		model: StefanGameModel, record: Dictionary, selected: int) -> void:
	Screens.draw_results(canvas, texture, definition, model, record, selected)


static func draw_records(canvas: CanvasItem, definition: Dictionary, record: Dictionary) -> void:
	Screens.draw_records(canvas, definition, record)


static func draw_help(canvas: CanvasItem, definition: Dictionary) -> void:
	Screens.draw_help(canvas, definition)


static func draw_exit_confirm(canvas: CanvasItem, definition: Dictionary, selected: int) -> void:
	Screens.draw_exit_confirm(canvas, definition, selected)
