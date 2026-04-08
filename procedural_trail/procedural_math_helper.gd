class_name ProceduralMathHelper
extends RefCounted


static func bezier_curve(v0: Vector2, v1: Vector2, c0: Vector2, t: float)\
 -> Vector2:
	# 这里使用二次贝塞尔曲线公式。
	# 先把 t 限制在合法范围内，再拆出 1 - t，公式会更直观，也更方便复用。
	var clamped_t := clampf(t, 0.0, 1.0)
	var inverse_t := 1.0 - clamped_t
	return inverse_t * inverse_t * v0 \
	+ 2.0 * inverse_t * clamped_t * c0 \
	+ clamped_t * clamped_t * v1
