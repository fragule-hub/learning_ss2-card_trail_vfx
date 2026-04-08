class_name ProceduralCardTrail
extends Line2D


# 单个采样点在拖尾上保留多久。
@export var point_duration := 0.72
# 采样距离过小时不新增点，避免点过密造成抖动。
@export var min_spawn_dist := 10.0
# 相邻采样点距离过大时，会自动插值补点，避免高速移动时出现断裂。
@export var max_spawn_dist := 42.0

# Line2D 自身不移动，只读取父节点的世界位置来记录拖尾轨迹。
var _anchor: Node2D
# 与点列表一一对应，记录每个点已经存在的时间。
var _point_age: Array[float] = []
# 缓存最后一次写入的点，避免每帧都反查 Line2D 末尾点位置。
var _last_point_position := Vector2.ZERO


func _ready() -> void:
	# 拖尾默认挂在被跟随节点下，因此父节点就是采样锚点。
	_anchor = get_parent() as Node2D
	visibility_changed.connect(_on_visibility_changed)


func _process(delta: float) -> void:
	if _anchor == null:
		return

	var delta_f := float(delta)
	_reset_global_transform()
	_age_points(delta_f)
	_append_sample_points(_anchor.global_position, delta_f)


# 节点隐藏时直接暂停处理并清空历史点，避免重新显示时拖尾残留旧轨迹。
func _on_visibility_changed() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED
	clear_points()
	_point_age.clear()
	_last_point_position = Vector2.ZERO


# 采样点是按世界坐标记录的，所以每帧都把自身世界变换重置掉，避免父节点位移被重复叠加。
func _reset_global_transform() -> void:
	global_position = Vector2.ZERO
	global_rotation = 0.0


# 先统一给所有点加年龄，再从头部移除过期点，逻辑上比边遍历边删除更直接。
func _age_points(delta_f: float) -> void:
	for index in range(_point_age.size()):
		_point_age[index] += delta_f

	while not _point_age.is_empty() and _point_age[0] > point_duration:
		remove_point(0)
		_point_age.remove_at(0)


# 根据当前锚点位置决定是否新增采样点，并在跨度过大时补插值点。
func _append_sample_points(point_pos: Vector2, delta_f: float) -> void:
	var point_count := get_point_count()
	if point_count == 0:
		_append_point(point_pos, 0.0)
		return

	var distance := point_pos.distance_to(_last_point_position)
	if distance < min_spawn_dist:
		return

	if point_count > 2 and distance > max_spawn_dist:
		_append_interpolated_points(point_pos, distance, delta_f, point_count)

	_append_point(point_pos, 0.0)


# 利用最近两段轨迹做一次近似平滑插值，避免高速拐弯时只出现生硬折线。
func _append_interpolated_points(point_pos: Vector2, distance: float, delta_f: float, point_count: int) -> void:
	var second_last_point := get_point_position(point_count - 2)
	var last_point := get_point_position(point_count - 1)
	var sample_distance := max_spawn_dist
	while sample_distance < distance - min_spawn_dist:
		var ratio := 0.5 + sample_distance / distance * 0.5
		var curve_start := second_last_point.lerp(last_point, ratio)
		var curve_end := last_point.lerp(point_pos, ratio)
		_append_point(curve_start.lerp(curve_end, ratio), delta_f * ratio)
		sample_distance += max_spawn_dist


# 统一从这里写入点和年龄，保持两套数组状态始终同步。
func _append_point(point_pos: Vector2, age: float) -> void:
	_point_age.append(age)
	add_point(point_pos)
	_last_point_position = point_pos
