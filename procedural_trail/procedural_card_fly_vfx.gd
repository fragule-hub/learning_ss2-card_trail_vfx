class_name ProceduralCardFlyVfx
extends Node2D


signal finished


# 拖尾本体由单独场景承载，这里只负责生成并驱动它跟随飞行卡牌。
const TRAIL_SCENE := preload("res://procedural_trail/procedural_card_trail_vfx.tscn")
const LOOK_AHEAD_OFFSET := 0.05
const ROTATION_OFFSET := PI / 2.0
const ROTATION_SMOOTHING := 12.0
const TRAIL_FADE_PROGRESS := 0.24
const FLIGHT_END_SCALE := 0.14
const SHRINK_END_SCALE := -0.1

# 飞行阶段通过颜色和透明度渐变营造能量收束感。
const OUTER_START := Color(1.0, 0.47, 0.18, 0.34)
const OUTER_END := Color(0.29, 0.13, 0.05, 0.08)
const BODY_START := Color(1.0, 0.73, 0.34, 0.95)
const BODY_END := Color(0.44, 0.18, 0.04, 0.7)
const CORE_START := Color(1.0, 0.97, 0.86, 1.0)
const CORE_END := Color(0.86, 0.42, 0.08, 0.55)
const RIBBON_START := Color(1.0, 0.98, 0.92, 0.95)
const RIBBON_END := Color(1.0, 0.55, 0.12, 0.0)


@onready var _card_soul: Node2D = $CardSoul
@onready var _outer_glow: ColorRect = $CardSoul/OuterGlow
@onready var _body_panel: Panel = $CardSoul/BodyPanel
@onready var _core_panel: Panel = $CardSoul/CorePanel

# 起点、终点和控制点共同定义飞行贝塞尔曲线。
var _trail_vfx: ProceduralCardTrailVfx
var _start_pos := Vector2.ZERO
var _end_pos := Vector2.ZERO
var _control_point := Vector2.ZERO

# 下面这组参数不是物理意义上的速度，而是推进动画进度的系数。
var _duration := 1.0
var _speed := 1.1
var _accel := 2.0
var _arc_height := 0.0
var _trail_fading := false
var _cancelled := false


# 由外部在实例化后注入起点和终点，真正的动画会在 _ready 后开始。
func setup(start_pos: Vector2, end_pos: Vector2) -> void:
	_start_pos = start_pos
	_end_pos = end_pos


func _ready() -> void:
	# 节点先瞬移到起点，再初始化随机化的飞行参数和外观。
	global_position = _start_pos
	_configure_motion()
	_update_card_appearance(0.0)
	_create_trail()
	call_deferred("_begin_animation")


# 将真正的播放流程延迟到下一轮消息队列，避免与刚加入场景树时的初始化冲突。
func _begin_animation() -> void:
	await _play_anim()


# 每次播放都轻微随机化，让拖尾效果看起来更自然，而不是固定模板运动。
func _configure_motion() -> void:
	var arc_offset := randf_range(120.0, 280.0)
	_speed = randf_range(1.05, 1.2)
	_accel = randf_range(1.9, 2.35)
	_duration = randf_range(0.95, 1.45)
	_arc_height = -420.0 if _end_pos.y < get_viewport_rect().size.y * 0.5 else 420.0 + arc_offset
	_control_point = _build_control_point()


# 控制点位于起终点中间，并沿 Y 方向抬高或压低，用于生成明显弧线。
func _build_control_point() -> Vector2:
	var control_point := _start_pos.lerp(_end_pos, 0.5)
	control_point.y -= _arc_height
	return control_point


# 拖尾节点和主体分离，主体销毁后拖尾还可以独立淡出，视觉上更完整。
func _create_trail() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	_trail_vfx = TRAIL_SCENE.instantiate() as ProceduralCardTrailVfx
	if _trail_vfx == null:
		push_error("[ProceduralCardFlyVfx] Failed to instantiate trail scene.")
		return

	_trail_vfx.setup(self)
	_trail_vfx.z_index = z_index - 1
	parent_node.add_child(_trail_vfx)


# 总播放流程分为两段：先飞行，再在终点继续缩小并把拖尾淡出。
func _play_anim() -> void:
	var interrupted := await _play_flight_phase()
	if not interrupted:
		global_position = _end_pos
		interrupted = await _play_shrink_phase()

	finished.emit()
	if not interrupted:
		queue_free()


# 第一阶段沿二次贝塞尔曲线移动，并使用前视点平滑修正朝向。
func _play_flight_phase() -> bool:
	var elapsed := 0.0
	while elapsed < _duration:
		await get_tree().process_frame
		if _cancelled:
			return true

		var delta_f := get_process_delta_time()
		elapsed = _advance_elapsed(elapsed, delta_f, true)

		var progress := _progress_from_elapsed(elapsed)
		var look_ahead_progress := _progress_from_elapsed(elapsed + LOOK_AHEAD_OFFSET)
		_update_flight_transform(progress, look_ahead_progress, delta_f)
		_update_card_appearance(progress)

	return false

# 第二阶段不再移动位置，只做收束和拖尾淡出，让终点停留更干净。
func _play_shrink_phase() -> bool:
	var elapsed := 0.0
	while elapsed < _duration:
		await get_tree().process_frame
		if _cancelled:
			return true

		elapsed = _advance_elapsed(elapsed, get_process_delta_time(), false)
		var progress := _progress_from_elapsed(elapsed)
		_update_shrink_appearance(progress)

	return false


# 飞行阶段会持续加速，缩小阶段则沿用飞行结束时的速度自然收尾。
func _advance_elapsed(elapsed: float, delta_f: float, apply_accel: bool) -> float:
	elapsed += _speed * delta_f
	if apply_accel:
		_speed += _accel * delta_f
	return elapsed


# 将累计时间统一换算成 0 到 1 的进度，便于所有插值逻辑复用。
func _progress_from_elapsed(elapsed: float) -> float:
	return clampf(elapsed / _duration, 0.0, 1.0)


func _update_flight_transform(progress: float, look_ahead_progress: float, delta_f: float) -> void:
	# 通过前视点估算下一刻的切线方向，可以避免直接看向当前速度导致的抖动。
	var look_ahead_position := ProceduralMathHelper.bezier_curve(_start_pos, _end_pos, _control_point, look_ahead_progress)
	global_position = ProceduralMathHelper.bezier_curve(_start_pos, _end_pos, _control_point, progress)
	rotation = lerp_angle(rotation, (look_ahead_position - global_position).angle() + ROTATION_OFFSET, delta_f * ROTATION_SMOOTHING)


# 飞行过程中的颜色和尺寸变化集中在这里，后续只需要调常量就能整体改观感。
func _update_card_appearance(progress: float) -> void:
	_card_soul.scale = Vector2.ONE * lerpf(1.0, FLIGHT_END_SCALE, progress)
	_outer_glow.color = OUTER_START.lerp(OUTER_END, progress)
	_body_panel.modulate = BODY_START.lerp(BODY_END, progress)
	_core_panel.modulate = CORE_START.lerp(CORE_END, progress)


# 缩小阶段只处理终点收束，不再重复计算位置和旋转。
func _update_shrink_appearance(progress: float) -> void:
	_fade_trail_if_needed(progress)
	_card_soul.scale = Vector2.ONE * maxf(lerpf(FLIGHT_END_SCALE, SHRINK_END_SCALE, progress), 0.0)
	_outer_glow.color.a = lerpf(OUTER_END.a, 0.0, progress)
	_body_panel.modulate.a = lerpf(BODY_END.a, 0.0, progress)
	_core_panel.modulate.a = lerpf(CORE_END.a, 0.0, progress)


# 拖尾延后一点再淡出，可以保留更多飞行残影，避免起飞后马上消失。
func _fade_trail_if_needed(progress: float) -> void:
	if _trail_fading or progress <= TRAIL_FADE_PROGRESS:
		return

	if is_instance_valid(_trail_vfx):
		_trail_vfx.fade_out()

	_trail_fading = true


# 主体销毁时一并终止播放流程；如果拖尾还没进入淡出，就直接清理，避免孤儿节点残留。
func _exit_tree() -> void:
	_cancelled = true
	if is_instance_valid(_trail_vfx) and not _trail_fading:
		_trail_vfx.queue_free()
