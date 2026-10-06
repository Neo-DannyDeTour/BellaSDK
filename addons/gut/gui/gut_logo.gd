@tool
extends Node2D

class GutEyeball:
	extends Node2D

	var _should_draw_laser: bool = false
	var _laser_end_pos: Vector2 = Vector2.ZERO
	var _laser_timer : Timer = null
	var _color_tween : Tween
	var _size_tween : Tween

	var sprite : Sprite2D = null
	var default_position: Vector2 = Vector2(0, 0)
	var move_radius: int = 25
	var move_center: Vector2 = Vector2(0, 0)
	var default_color: Color = Color(0.31, 0.31, 0.31)
	var _color: Variant = default_color :
		set(val):
			_color = val
			queue_redraw()
	var color: Variant = _color :
		set(val):
			_start_color_tween(_color, val)
		get(): return _color
	var default_size: int = 70
	var _size: Variant = default_size :
		set(val):
			_size = val
			queue_redraw()
	var size: Variant = _size :
		set(val):
			_start_size_tween(_size, val)
		get(): return _size


	func _init(node: Variant) -> void:
		sprite = node
		default_position = sprite.position
		move_center = sprite.position
		# hijack the original sprite, because I want to draw it here but keep
		# the original in the scene for layout.
		position = sprite.position
		sprite.get_parent().add_child(self)
		sprite.visible = false


	func _ready() -> void:
		_laser_timer = Timer.new()
		_laser_timer.wait_time = .1
		_laser_timer.one_shot = true
		add_child(_laser_timer)
		_laser_timer.timeout.connect(func():  _should_draw_laser = false)


	func _process(_delta: float) -> void:
		if(_should_draw_laser):
			queue_redraw()


	func _start_color_tween(old_color: Variant, new_color: Variant) -> void:
		if(_color_tween != null and _color_tween.is_running()):
			_color_tween.kill()
		_color_tween = create_tween()
		_color_tween.tween_property(self, '_color', new_color, .3).from(old_color)
		_color_tween.play()


	func _start_size_tween(old_size: Variant, new_size: Variant) -> void:
		if(_size_tween != null and _size_tween.is_running()):
			_size_tween.kill()
		_size_tween = create_tween()
		_size_tween.tween_property(self, '_size', new_size, .3).from(old_size)
		_size_tween.play()


	var _laser_size: float = 20.0
	func _draw() -> void:
		draw_circle(Vector2.ZERO, size, color, true, -1, true)
		if(_should_draw_laser):
			var end_pos: Variant = (_laser_end_pos - global_position) * 2
			var laser_size: Variant = _laser_size * (float(size)/float(default_size))
			draw_line(Vector2.ZERO, end_pos, color, laser_size)
			draw_line(Vector2.ZERO, end_pos, Color(1, 1, 1, .5), laser_size * .8)


	# There's a bug in here where the eye shakes like crazy.  It's a feature
	# now.  Don't fix it.
	func look_at_local_position(local_pos: Variant) -> void:
		var dir: Variant = position.direction_to(local_pos)
		var dist: Variant = position.distance_to(local_pos)
		position = move_center + (dir * min(dist, move_radius))
		position.x = clamp(position.x, move_center.x - move_radius, move_center.x + move_radius)
		position.y = clamp(position.y, move_center.y - move_radius, move_center.y + move_radius)


	func reset() -> void:
		color = default_color
		size = default_size


	func eye_laser(global_pos: Variant) -> void:
		_should_draw_laser = true
		_laser_end_pos = global_pos
		_laser_timer.start()


	func _stop_laser() -> void:
		_should_draw_laser = false



# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
const GutEditorGlobals = preload('res://addons/gut/gui/editor_globals.gd')
# Active means it's actively doing stuff.  When this is not active the eyes
# won't follow, but you can still make the sizes change by calling methods on
# this.
@export var active: Variant = false :
	set(val):
		active = val
		if(!active and is_inside_tree()):
			left_eye.position = left_eye.default_position
			right_eye.position = right_eye.default_position
# When disabled, this will reset to default and you can't make it do anything.
@export var disabled: Variant = false :
	set(val):
		disabled = val
		if(disabled and is_inside_tree()):
			left_eye.position = left_eye.default_position
			right_eye.position = right_eye.default_position
			left_eye.reset()
			right_eye.reset()
			modulate = Color.GRAY
			$BaseLogo.texture = _no_shine
		else:
			$BaseLogo.texture = _normal
			modulate = Color.WHITE

@onready var _reset_timer: Node = $ResetTimer
@onready var _face_button: Control = $FaceButton
@onready var left_eye : GutEyeball = GutEyeball.new($BaseLogo/LeftEye)
@onready var right_eye : GutEyeball = GutEyeball.new($BaseLogo/RightEye)

var _no_shine: Variant = load("res://addons/gut/images/GutIconV2_no_shine.png")
var _normal: Variant = load("res://addons/gut/images/GutIconV2_base.png")
var _is_in_edited_scene: bool = false

signal pressed

func _debug_ready() -> void:
	position = Vector2(500, 500)
	active = true


func _ready() -> void:
	_is_in_edited_scene = GutEditorGlobals.is_being_edited_in_editor(self)

	if(get_parent() == get_tree().root):
		_debug_ready()

	disabled = disabled
	active = active
	left_eye.move_center.x -= 20
	right_eye.move_center.x += 10
	_face_button.modulate.a = 0.0


func _process(_delta: float) -> void:
	if(active and !disabled and !_is_in_edited_scene):
		left_eye.look_at_local_position(get_local_mouse_position())
		right_eye.look_at_local_position(get_local_mouse_position())


# ----------------
# Events
# ----------------
func _on_reset_timer_timeout() -> void:
	left_eye.reset()
	right_eye.reset()


func _on_face_button_pressed() -> void:
	pressed.emit()


# ----------------
# Public
# ----------------
func set_eye_scale(left: Variant, right: Variant = left) -> void:
	if(disabled or _is_in_edited_scene):
		return
	left_eye.size = left_eye.default_size * left
	right_eye.size = right_eye.default_size * right
	_reset_timer.start()


func reset_eye_size() -> void:
	if(disabled or _is_in_edited_scene):
		return
	left_eye.size = left_eye.default_size
	right_eye.size = right_eye.default_size


func set_eye_color(left: Variant, right: Variant = left) -> void:
	if(disabled or _is_in_edited_scene):
		return
	left_eye.color = left
	right_eye.color = right
	_reset_timer.start()


func reset_eye_color() -> void:
	if(disabled or _is_in_edited_scene):
		return
	left_eye.color = left_eye.default_color
	right_eye.color = right_eye.default_color


# I removed the eye lasers because they aren't ready yet.  I've already spent
# too much time on this logo.  It's great, I love it...but it's been long
# enough.  This gives me, or someone else, something to do later.
#func eye_lasers(global_pos):
	#left_eye.eye_laser(global_pos)
	#right_eye.eye_laser(global_pos)
