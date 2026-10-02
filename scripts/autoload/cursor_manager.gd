extends Node
## Zentraler Projektcursor.
##
## Ein als Control gezeichneter Software-Cursor kann nie ueber Godots
## Popup-/Subwindows liegen (zum Beispiel OptionButton-Menues). Derselbe
## Workbench-Pfeil wird deshalb als echter Systemcursor installiert. Der
## Fenstermanager zeichnet ihn garantiert ueber allen CanvasLayern, Popups,
## Dialogen und Vollbildansichten.

const CURSOR_SIZE := Vector2i(18, 22)
const HOTSPOT := Vector2(1, 1)
const CURSOR_SHAPES: Array[int] = [
	Input.CURSOR_ARROW,
	Input.CURSOR_IBEAM,
	Input.CURSOR_POINTING_HAND,
	Input.CURSOR_CROSS,
	Input.CURSOR_WAIT,
	Input.CURSOR_BUSY,
	Input.CURSOR_DRAG,
	Input.CURSOR_CAN_DROP,
	Input.CURSOR_FORBIDDEN,
	Input.CURSOR_VSIZE,
	Input.CURSOR_HSIZE,
	Input.CURSOR_BDIAGSIZE,
	Input.CURSOR_FDIAGSIZE,
	Input.CURSOR_MOVE,
	Input.CURSOR_VSPLIT,
	Input.CURSOR_HSPLIT,
	Input.CURSOR_HELP,
]

var _cursor_texture: ImageTexture
var _configured_shapes := 0
var _visible_requested := true


func _ready() -> void:
	_install_cursor()


func _exit_tree() -> void:
	# Auch normales Beenden muss die vom DisplayServer gehaltenen Texturen
	# vor dem RenderingServer freigeben, nicht nur spezielle Render-Audits.
	release_cursor()


func show_cursor() -> void:
	if _cursor_texture == null:
		_install_cursor()
	_visible_requested = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_cursor() -> void:
	_visible_requested = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func cursor_texture() -> Texture2D:
	return _cursor_texture


func configured_shape_count() -> int:
	return _configured_shapes


func is_cursor_requested_visible() -> bool:
	return _visible_requested


## Release-/Render-Audits beenden sich programmgesteuert. Vor dem Tree-Abbau
## werden alle nativen Cursorformen gelöst, damit der RenderingServer keine
## ImageTexture mehr nach seiner eigenen Finalisierung freigeben muss.
func release_cursor() -> void:
	for shape: int in CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(null, shape)
	_cursor_texture = null
	_configured_shapes = 0


func _install_cursor() -> void:
	var source := Sprites.cursor()
	var image := source.get_image()
	if image == null or image.is_empty():
		push_error("CursorManager: Workbench-Cursor konnte nicht erzeugt werden.")
		return
	image.resize(CURSOR_SIZE.x, CURSOR_SIZE.y, Image.INTERPOLATE_NEAREST)
	_cursor_texture = ImageTexture.create_from_image(image)
	_configured_shapes = 0
	for shape: int in CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(_cursor_texture, shape, HOTSPOT)
		_configured_shapes += 1
