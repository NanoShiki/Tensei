extends Sprite2D
## 按“动作 + 朝向”解析动作图并推进帧。攻击动作、可替换部件与武器接入时，在同一时间轴上扩展本节点。
## 节点原点对齐单格内的地面锚点，角色位置即脚下投影中心。
const ROW_BY_FACING := {"south": 0, "east": 1, "north": 2, "west": 3}

var action := "idle"
var facing := "south"
var frame_index := 0

var _actions: Dictionary = {}
var _sheets: Dictionary = {}
var _cell_size := Vector2(256, 256)
var _ground_anchor := Vector2(128, 224)
var _elapsed := 0.0


func configure(profile: Dictionary) -> void:
	_actions = profile.get("actions", {})
	_cell_size = profile.get("cell_size", _cell_size)
	_ground_anchor = profile.get("ground_anchor", _ground_anchor)
	_sheets.clear()
	for name in _actions:
		var path: String = _actions[name]["sheet"]
		if not _sheets.has(path):
			_sheets[path] = load(path) as Texture2D
	centered = false
	region_enabled = true
	scale = Vector2.ONE * float(profile.get("visual_scale", 1.0))
	_apply_frame()


func set_state(next_action: String, next_facing: String) -> void:
	if not _actions.has(next_action):
		push_warning("缺少动作配置：%s" % next_action)
		return
	if next_action == action and next_facing == facing:
		return
	if next_action != action:
		frame_index = 0
		_elapsed = 0.0
	action = next_action
	facing = next_facing
	_apply_frame()


func _process(delta: float) -> void:
	advance(delta)


## 推进当前动作的时间轴。测试可直接调用，无需依赖帧率。
func advance(delta: float) -> void:
	var config: Dictionary = _actions.get(action, {})
	var fps := float(config.get("fps", 0.0))
	var columns := int(config.get("columns", 1))
	if fps <= 0.0 or columns <= 1:
		return
	var frame_time := 1.0 / fps
	_elapsed += delta
	while _elapsed >= frame_time:
		_elapsed -= frame_time
		frame_index = (frame_index + 1) % columns
		_apply_frame()


func _apply_frame() -> void:
	var config: Dictionary = _actions.get(action, {})
	if config.is_empty():
		return
	texture = _sheets.get(config["sheet"])
	var row: int = ROW_BY_FACING.get(facing, 0)
	region_rect = Rect2(Vector2(frame_index * _cell_size.x, row * _cell_size.y), _cell_size)
	offset = -_ground_anchor
