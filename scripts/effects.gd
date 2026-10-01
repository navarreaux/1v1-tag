extends Node3D
## Chase clues that only one side gets:
##  - the Hunter sees the Runner's scratch marks, blood (when injured) and loud-noise alerts;
##  - the Runner hears a heartbeat that speeds up as the Hunter gets closer (the terror radius).

const TUNING := preload("res://tuning.tres")
const Role := preload("res://scripts/player.gd").Role

const SCRATCH_INTERVAL := 0.15
const BLOOD_INTERVAL := 1.1
const NOISE_TIME := 2.5

var game: Node

var _marks: Array = []  # [{node, time_left, life}]
var _scratch_timer := 0.0
var _blood_timer := 0.0
var _scratch_mat: StandardMaterial3D
var _blood_mat: StandardMaterial3D
var _heart: AudioStreamPlayer
var _beat_timer := 0.0


func _ready() -> void:
	_scratch_mat = _mark_material(Color(1.0, 0.35, 0.1))
	_blood_mat = _mark_material(Color(0.55, 0.0, 0.0))
	_heart = AudioStreamPlayer.new()
	_heart.stream = _make_heartbeat()
	add_child(_heart)


func _mark_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process(delta: float) -> void:
	_fade_marks(delta)
	var me = game.local_player()
	if me == null or not game.is_chasing():
		return
	if me.role == Role.HUNTER:
		_spawn_trail(delta)
	else:
		_heartbeat(delta, me)


# --- Hunter: scratch marks and blood -------------------------------------

func _spawn_trail(delta: float) -> void:
	var runner = game.get_runner()
	if runner == null or runner.downed:
		return
	if runner.sprinting and not runner.vaulting:
		_scratch_timer -= delta
		if _scratch_timer <= 0.0:
			_scratch_timer = SCRATCH_INTERVAL * randf_range(0.7, 1.4)
			_scratch(runner.global_position)
	if runner.injured:
		_blood_timer -= delta
		if _blood_timer <= 0.0:
			_blood_timer = BLOOD_INTERVAL * randf_range(0.6, 1.3)
			var drop := _quad(Vector2(0.18, 0.18), _blood_mat)
			drop.global_position = runner.global_position + Vector3(randf_range(-0.3, 0.3), 0.02, randf_range(-0.3, 0.3))
			drop.rotation = Vector3(-PI / 2.0, randf() * TAU, 0)
			_marks.append({"node": drop, "time_left": TUNING.blood_time, "life": TUNING.blood_time})


## Scratch marks land near (not exactly on) the Runner's path, on the floor or a nearby wall.
func _scratch(at: Vector3) -> void:
	var offset := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
	var mark := _quad(Vector2(0.6, 0.12), _scratch_mat)
	var from := at + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + offset * 1.2, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and randf() < 0.7:
		# On a wall, facing out from it.
		mark.global_position = hit.position + hit.normal * 0.02 + Vector3(0, randf_range(-0.6, 0.6), 0)
		mark.look_at(mark.global_position + hit.normal, Vector3.UP if absf(hit.normal.y) < 0.9 else Vector3.FORWARD)
		mark.rotate_object_local(Vector3.FORWARD, randf_range(-0.8, 0.8))
	else:
		mark.global_position = at + offset + Vector3(0, 0.02, 0)
		mark.rotation = Vector3(-PI / 2.0, randf() * TAU, 0)
	_marks.append({"node": mark, "time_left": TUNING.scratch_mark_time, "life": TUNING.scratch_mark_time})


func _quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	m.mesh = qm
	m.material_override = mat.duplicate()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _fade_marks(delta: float) -> void:
	for i in range(_marks.size() - 1, -1, -1):
		var mk: Dictionary = _marks[i]
		mk.time_left -= delta
		if mk.time_left <= 0.0:
			mk.node.queue_free()
			_marks.remove_at(i)
		else:
			mk.node.material_override.albedo_color.a = clampf(mk.time_left / mk.life * 1.5, 0.0, 1.0)


## Called when the Runner fast-vaults. Shows a yellow "!" (through walls) to the Hunter.
func noise_alert(pos: Vector3) -> void:
	var me = game.local_player()
	if me == null or me.role != Role.HUNTER:
		return
	var label := Label3D.new()
	label.text = "!"
	label.font_size = 64
	label.modulate = Color(1, 0.85, 0.1)
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true  # seen through walls
	label.pixel_size = 0.01
	add_child(label)
	label.global_position = pos + Vector3(0, 1.6, 0)
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 0.0, NOISE_TIME)
	tw.finished.connect(label.queue_free)


# --- Runner: heartbeat ---------------------------------------------------

func _heartbeat(delta: float, me) -> void:
	var hunter = game.players.get(game.hunter_id)
	if hunter == null:
		return
	var d: float = me.global_position.distance_to(hunter.global_position)
	var r: float = TUNING.terror_radius
	if d > r:
		_beat_timer = 0.0
		return
	# Faster and louder the closer the Hunter is.
	var closeness := 1.0 - d / r
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		_beat_timer = lerpf(1.2, 0.42, closeness)
		_heart.volume_db = lerpf(-22.0, 0.0, closeness)
		_heart.play()


## Makes a "lub-dub" sound in code so the project needs no audio files.
func _make_heartbeat() -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * 0.45)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / rate
		var v := _thump(t, 0.0, 1.0) + _thump(t, 0.2, 0.7)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


func _thump(t: float, start: float, amp: float) -> float:
	var x := t - start
	if x < 0.0:
		return 0.0
	return amp * sin(TAU * 55.0 * x) * exp(-x * 18.0) * minf(1.0, x * 200.0)
