class_name ProceduralCardTrailVfx
extends Node2D


# 这层节点只负责拖尾视觉，不参与路径计算。
const INTRO_SCALE := Vector2.ONE * 1.28
const INTRO_DURATION := 0.2
const FADE_OUT_DURATION := 0.45
const FADE_OUT_SCALE := Vector2.ONE * 1.24


@onready var _trails: Node2D = $Trails
@onready var _particles: Node2D = $Particles
@onready var _glow_shapes: Node2D = $GlowShapes

# 拖尾始终跟随主体，因此这里只缓存一个被跟随节点引用。
var _node_to_follow: Node2D
var _visual_targets: Array[CanvasItem] = []
var _tween: Tween


# 由外部注入主体节点，拖尾会在 _process 中持续同步它的位置与朝向。
func setup(node_to_follow: Node2D) -> void:
	_node_to_follow = node_to_follow


func _ready() -> void:
	if _node_to_follow == null:
		push_error("[ProceduralCardTrailVfx] No node to follow. Removing VFX instance.")
		queue_free()
		return

	_visual_targets = [_trails, _particles, _glow_shapes]
	_set_targets_alpha(0.0)
	_glow_shapes.scale = INTRO_SCALE
	_sync_follow_transform()
	_start_intro_tween()


func _process(_delta: float) -> void:
	if not is_instance_valid(_node_to_follow):
		queue_free()
		return

	_sync_follow_transform()


# 淡出时停止继续跟随，这样拖尾会保留最后一帧姿态，自然消散。
func fade_out() -> void:
	set_process(false)
	_replace_tween()
	_tween_targets_alpha(0.0, FADE_OUT_DURATION, Tween.EASE_IN, Tween.TRANS_CUBIC)
	_tween.tween_property(_glow_shapes, "scale", FADE_OUT_SCALE, FADE_OUT_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_fade_particles()
	await _tween.finished
	queue_free()


# 入场时先快速显现，再让发光轮廓回弹到正常尺寸。
func _start_intro_tween() -> void:
	_replace_tween()
	_tween_targets_alpha(1.0, INTRO_DURATION, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	_tween.tween_property(_glow_shapes, "scale", Vector2.ONE, INTRO_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


# 跟随主体时只同步世界坐标和旋转，拖尾自身的局部结构保持不变。
func _sync_follow_transform() -> void:
	global_position = _node_to_follow.global_position
	rotation = _node_to_follow.rotation


# 将一组可视节点统一设置透明度，避免在多个生命周期函数里重复写同样的赋值。
func _set_targets_alpha(alpha: float) -> void:
	for target in _visual_targets:
		_set_canvas_item_alpha(target, alpha)


# 入场和淡出都会批量做透明度补间，这里统一封装，后面只关心目标值和曲线参数。
func _tween_targets_alpha(alpha: float, duration: float, ease_type: int, transition: int) -> void:
	for target in _visual_targets:
		_tween.tween_property(target, "modulate:a", alpha, duration).set_ease(ease_type).set_trans(transition)


func _set_canvas_item_alpha(target: CanvasItem, alpha: float) -> void:
	var color := target.modulate
	color.a = alpha
	target.modulate = color


# 粒子停止发射后仍可保留少量残留，因此这里逐步降低 amount，而不是瞬间关闭。
func _fade_particles() -> void:
	for child in _particles.get_children():
		if child is CPUParticles2D:
			_tween.tween_property(child, "amount", 1, FADE_OUT_DURATION)


# 每次开始新补间前先杀掉旧补间，避免多个 tween 同时改同一批属性。
func _replace_tween() -> void:
	if _tween != null:
		_tween.kill()

	_tween = create_tween().set_parallel()


func _exit_tree() -> void:
	if _tween != null:
		_tween.kill()
