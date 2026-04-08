class_name ProceduralTrailDemo
extends Control


# 演示场景只负责选点、播放和状态提示，真正的拖尾逻辑都在具体特效节点里。
const CARD_FLY_SCENE := preload("res://procedural_trail/procedural_card_fly_vfx.tscn")
const ACTION_MOUSE_LEFT := &"mouse_left"
const ACTION_MOUSE_RIGHT := &"mouse_right"
const ACTION_QUICK_PLAY := &"a"
const EFFECT_DELAY := 0.08
const STATUS_READY := "左键先选起点再选终点。右键重播当前路径，A 以当前鼠标位置作为终点立即播放，Esc 重置。"
const STATUS_RESET := "已重置。左键先选起点再选终点。右键重播当前路径，A 以当前鼠标位置作为终点立即播放。"


@onready var _effect_layer: Node2D = $EffectLayer
@onready var _start_marker: ColorRect = $MarkerLayer/StartMarker
@onready var _end_marker: ColorRect = $MarkerLayer/EndMarker
@onready var _status_label: Label = $Ui/Panel/VBoxContainer/StatusLabel

# 缓存当前可重播的起点和终点。
var _start_position := Vector2.ZERO
var _end_position := Vector2.ZERO
var _has_start_point := false
var _has_end_point := false

# 延迟播放期间需要暂时屏蔽新输入，避免一个路径触发多个待执行计时器。
var _waiting_for_spawn := false


func _ready() -> void:
	# 全屏 Control 默认可能截获鼠标事件，这里显式忽略，确保输入能进入 _unhandled_input。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	randomize()
	_update_status(STATUS_READY)


# 左键两段式选点，右键重播，A 用当前鼠标位置快速补终点，Esc 重置。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_MOUSE_LEFT):
		_handle_left_click(_get_input_position(event))
		_consume_input()
		return

	if event.is_action_pressed(ACTION_MOUSE_RIGHT):
		_replay_current_path()
		_consume_input()
		return

	if event.is_action_pressed(ACTION_QUICK_PLAY):
		_play_to_current_mouse_position()
		_consume_input()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_reset_selection()
		_update_status(STATUS_RESET)
		_consume_input()


# 第一次左键记录起点，第二次左键记录终点并请求播放。
func _handle_left_click(click_position: Vector2) -> void:
	if _waiting_for_spawn:
		return

	if not _is_waiting_for_end_point():
		_set_start_point(click_position)
		_clear_end_point()
		_update_status("已记录起点，等待记录终点。")
		return

	_set_end_point(click_position)
	_update_status("已记录终点，正在准备程序化拖尾。")
	_request_effect_play(EFFECT_DELAY)


# 右键直接重播最近一次确认过的起点和终点。
func _replay_current_path() -> void:
	if not _can_play_effect():
		_update_status("右键重播前需要先确定起点和终点。")
		return

	_play_effect_immediately()


# A 键不需要重新点第二下，直接把当前鼠标位置作为终点立即播放。
func _play_to_current_mouse_position() -> void:
	if not _has_start_point:
		_update_status("按 A 快速播放前需要先确定起点。")
		return

	_set_end_point(_get_mouse_canvas_position())
	_play_effect_immediately()


# 支持延迟触发，便于在记录完终点后预留一点节奏感。
func _request_effect_play(delay: float) -> void:
	if not _can_play_effect():
		push_warning("[ProceduralTrailDemo] Cannot play effect without both start and end points.")
		return

	if delay <= 0.0:
		_play_effect()
		return

	_waiting_for_spawn = true
	_begin_effect_after_delay(delay)


# 这里不保存 timer 引用，只通过 _waiting_for_spawn 判断这次请求是否仍然有效。
func _begin_effect_after_delay(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not _waiting_for_spawn:
		return

	_play_effect()


func _play_effect_immediately() -> void:
	if not _can_play_effect():
		return

	_waiting_for_spawn = false
	_play_effect()


# 负责真正实例化飞行特效，并在完成后恢复演示层状态提示。
func _play_effect() -> void:
	var fly_vfx := _instantiate_fly_vfx()
	if fly_vfx == null:
		return

	fly_vfx.setup(_start_position, _end_position)
	fly_vfx.finished.connect(_on_effect_finished, CONNECT_ONE_SHOT)
	_effect_layer.add_child(fly_vfx)
	_waiting_for_spawn = false
	_update_status("程序化拖尾已开始。左键可重新选点，右键可重播当前路径。")


# 这里单独封装实例化，是为了把错误提示和类型校验集中在一处。
func _instantiate_fly_vfx() -> ProceduralCardFlyVfx:
	var fly_vfx_instance := CARD_FLY_SCENE.instantiate()
	if fly_vfx_instance == null:
		_waiting_for_spawn = false
		_update_status("特效实例化失败，请查看输出日志。")
		push_error("[ProceduralTrailDemo] Failed to instantiate CARD_FLY_SCENE.")
		return null

	var fly_vfx := fly_vfx_instance as ProceduralCardFlyVfx
	if fly_vfx == null:
		_waiting_for_spawn = false
		_update_status("特效脚本类型不匹配，请查看输出日志。")
		push_error("[ProceduralTrailDemo] Instanced scene is not ProceduralCardFlyVfx.")
		fly_vfx_instance.queue_free()
		return null

	return fly_vfx


func _on_effect_finished() -> void:
	_update_status("特效播放完成。左键可重新选点，右键可重播当前路径。")


# 重置时保留场景本身，但清空所有选点状态与标记显示。
func _reset_selection() -> void:
	_waiting_for_spawn = false
	_has_start_point = false
	_has_end_point = false
	_start_marker.visible = false
	_end_marker.visible = false


func _set_start_point(point_position: Vector2) -> void:
	_start_position = point_position
	_has_start_point = true
	_place_marker(_start_marker, _start_position)


func _set_end_point(point_position: Vector2) -> void:
	_end_position = point_position
	_has_end_point = true
	_place_marker(_end_marker, _end_position)


func _clear_end_point() -> void:
	_has_end_point = false
	_end_marker.visible = false


# 只要已经有起点但还没有终点，就表示当前正处于等待第二次点击的状态。
func _is_waiting_for_end_point() -> bool:
	return _has_start_point and not _has_end_point


func _can_play_effect() -> bool:
	return _has_start_point and _has_end_point


# 鼠标事件使用事件位置，键盘触发时退回到当前鼠标坐标。
func _get_input_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	return _get_mouse_canvas_position()


func _get_mouse_canvas_position() -> Vector2:
	return get_viewport().get_mouse_position()


func _place_marker(marker: ColorRect, marker_position: Vector2) -> void:
	marker.visible = true
	marker.position = marker_position - marker.size * 0.5


func _consume_input() -> void:
	get_viewport().set_input_as_handled()


func _update_status(text: String) -> void:
	_status_label.text = text
