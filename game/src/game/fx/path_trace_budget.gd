extends RefCounted
## Learn from completed render frames and GPU timestamps, never display-frame
## counts. Hysteresis and a recovery delay keep a steady scene at one budget.
const TARGETS := [0,30,45,60]
const MIN_SCALE := 0.65
const STEP := 0.05
var scale := 1.0
var target := 0
var changes := 0
var gpu_ms := 0.0
var _samples: Array[Vector2] = []
var _elapsed := 0.0
var _cooldown := 2.0
var _headroom := 0.0
var _frame := -1

func configure(selection: int) -> void:
	var next: int = TARGETS[clampi(selection,0,TARGETS.size()-1)]
	if next==target:return
	target=next;scale=1.0;changes=0;_cooldown=2.0;_headroom=0.0;_frame=-1
	clear_samples()

func clear_samples() -> void:
	_samples.clear();_elapsed=0.0

func observe(frame: int,seconds: float,total_gpu_ms: float,trace_gpu_ms: float,blocked: bool) -> float:
	if target==0:return scale
	# Loading, pause, scene preparation and isolated long CPU frames do not
	# vote to lower quality. Require fresh, finite GPU measurements as well.
	if blocked or not is_finite(seconds) or seconds<=0.0 or seconds>0.12:
		clear_samples();_headroom=0.0;return scale
	_cooldown=maxf(0.0,_cooldown-seconds)
	if frame==_frame or frame<0 or not is_finite(total_gpu_ms) or not is_finite(trace_gpu_ms) \
		or total_gpu_ms<=0.0 or total_gpu_ms>120.0 or trace_gpu_ms<=0.0:return scale
	_frame=frame
	_samples.append(Vector2(total_gpu_ms,minf(trace_gpu_ms,total_gpu_ms)));_elapsed+=seconds
	if _elapsed<0.5 or _samples.size()<12:return scale
	_samples.sort_custom(func(a: Vector2,b: Vector2):return a.x<b.x)
	var median := _samples[_samples.size()/2];var elapsed := _elapsed
	gpu_ms=median.x;clear_samples()
	var budget := 1000.0/target
	var next := minf(1.0,scale+STEP)
	var predicted := median.x-median.y+median.y*pow(next/scale,2.0)
	if median.x>budget*1.05:
		_headroom=0.0
		if _cooldown<=0.0 and scale>MIN_SCALE:
			scale=maxf(MIN_SCALE,snappedf(scale-STEP,STEP));_cooldown=2.0;changes+=1
	elif predicted<budget*0.85:
		_headroom+=elapsed
		if _headroom>=6.0 and _cooldown<=0.0 and scale<1.0:
			scale=minf(1.0,snappedf(next,STEP));_cooldown=3.0;_headroom=0.0;changes+=1
	else:_headroom=0.0
	return scale

func size(base: Vector2i) -> Vector2i:
	if scale>=1.0:return base
	# Quantize allocations, preserving the lattice's aspect to within one pixel.
	var width := maxi(2,roundi(base.x*scale/8.0)*8)
	return Vector2i(width,maxi(2,roundi(float(base.y)*width/base.x)))
