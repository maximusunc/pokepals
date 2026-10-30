class_name TestPathShape
## Tests for PathShape — the pure geometry that turns a spec's straight path segments into the curved
## trails the pixel ground draws. Its promises: segments meeting end to end chain into one trail, a
## fork (three or more meeting) ends chains so trails still join there, smoothing and wandering keep
## both ends exactly where they were authored, and resampling spaces points evenly.


static func run_all() -> int:
	var fails := 0
	print("TestPathShape")
	fails += _test_chains_join_end_to_end()
	fails += _test_fork_splits_chains()
	fails += _test_smooth_keeps_ends()
	fails += _test_resample_is_even()
	fails += _test_curves_keep_endpoints()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _seg(a: Vector2, b: Vector2) -> Dictionary:
	return { "from": a, "to": b }


static func _test_chains_join_end_to_end() -> int:
	# authored out of order and one reversed: still one trail through all four points
	var segs := [_seg(Vector2(100, 0), Vector2(200, 50)), _seg(Vector2(0, 0), Vector2(100, 0)), _seg(Vector2(300, 0), Vector2(200, 50))]
	var ch := PathShape.chains(segs)
	var one: bool = ch.size() == 1 and (ch[0] as PackedVector2Array).size() == 4
	return _ok(one, "segments meeting end to end chain into one trail")


static func _test_fork_splits_chains() -> int:
	# a Y: three arms meet at the origin, so three chains, each touching the junction
	var segs := [_seg(Vector2.ZERO, Vector2(-100, 0)), _seg(Vector2.ZERO, Vector2(100, 0)), _seg(Vector2.ZERO, Vector2(0, 100))]
	var ch := PathShape.chains(segs)
	var all_touch := true
	for c in ch:
		var pts: PackedVector2Array = c
		if pts[0] != Vector2.ZERO and pts[pts.size() - 1] != Vector2.ZERO:
			all_touch = false
	return _ok(ch.size() == 3 and all_touch, "a fork ends chains at the junction")


static func _test_smooth_keeps_ends() -> int:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	var s := PathShape.smooth(pts, 3)
	var ends: bool = s[0] == pts[0] and s[s.size() - 1] == pts[2]
	# the elbow at (100, 0) is rounded off: no smoothed point sits on it
	var cut := true
	for q in s:
		if q.distance_to(Vector2(100, 0)) < 1.0:
			cut = false
	return _ok(ends and cut and s.size() > pts.size(), "smoothing rounds the elbow and keeps the ends")


static func _test_resample_is_even() -> int:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(35, 0), Vector2(100, 0)])
	var r := PathShape.resample(pts, 10.0)
	var even := true
	for k in range(1, r.size() - 1):
		if absf(r[k].distance_to(r[k - 1]) - 10.0) > 0.01:
			even = false
	var ends: bool = r[0] == pts[0] and r[r.size() - 1] == pts[2]
	return _ok(even and ends and r.size() == 11, "resampling spaces points evenly, ends kept")


static func _test_curves_keep_endpoints() -> int:
	var segs := [_seg(Vector2(0, 0), Vector2(200, 80)), _seg(Vector2(200, 80), Vector2(400, 0))]
	var cv := PathShape.curves(segs)
	var pts: PackedVector2Array = cv[0]
	var ends: bool = pts[0].distance_to(Vector2(0, 0)) < 0.01 and pts[pts.size() - 1].distance_to(Vector2(400, 0)) < 0.01
	var wandered := false
	for q in pts:
		if absf(q.y - 0.0) > 0.5 and q.x > 20.0 and q.x < 380.0:
			wandered = true
	return _ok(cv.size() == 1 and ends and wandered, "curves meander but still end where authored")
