# res://Scripts/PieceNode.gd
extends Area2D
class_name PieceNode

signal piece_dropped(piece_node, drop_position)
signal piece_picked_up(piece_node)

@export var piece_data: PieceData

const CELL_SIZE: float = 64.0
const JOINT_BASE_SIZE: float = 16.0
const JOINT_DEPTH: float = 12.0

@onready var character_sprite: Sprite2D = $CharacterSprite
@onready var info_ui: Node2D = $InfoUI
@onready var name_label: Label = $InfoUI/NameLabel
@onready var effect_label: Label = $InfoUI/EffectLabel

var dragging: bool = false
var is_hovered: bool = false
var original_position: Vector2
var offset: Vector2
var board_pos: Vector2i = Vector2i(-1, -1)

var is_enemy: bool = false

var conn_top: Array = [false, false, false]
var conn_bottom: Array = [false, false, false]
var conn_left: Array = [false, false, false]
var conn_right: Array = [false, false, false]

var target_rotation: float = 0.0
var original_data: PieceData


func _ready() -> void:
	input_pickable = true
	
	character_sprite.show_behind_parent = true
	
	if piece_data != null:
		original_data = piece_data
	
	if piece_data:
		update_visuals()

func update_visuals() -> void:
	if not is_inside_tree() or piece_data == null: return
	
	if piece_data.texture:
		character_sprite.texture = piece_data.texture
		var tex_size = piece_data.texture.get_size()
		character_sprite.scale = Vector2(CELL_SIZE / tex_size.x, CELL_SIZE / tex_size.y)
	else:
		character_sprite.texture = null
	
	if name_label: name_label.text = piece_data.piece_name
	if effect_label: effect_label.text = str(piece_data.effect_value)
	
	queue_redraw()

func set_connections(in_top: Array, in_bottom: Array, in_left: Array, in_right: Array) -> void:
	# ==========================================
	# 1. 自分の回転状態に合わせて受け取る光を自動変換
	# ==========================================
	var rot_steps = int(round(target_rotation / 90.0)) % 4
	if rot_steps < 0:
		rot_steps += 4
		
	var c_top = in_top
	var c_bottom = in_bottom
	var c_left = in_left
	var c_right = in_right
	
	if rot_steps == 1: # 90度時計回り
		c_top = in_right
		c_bottom = in_left
		c_left = _reverse_array(in_top)
		c_right = _reverse_array(in_bottom)
	elif rot_steps == 2: # 180度
		c_top = _reverse_array(in_bottom)
		c_bottom = _reverse_array(in_top)
		c_left = _reverse_array(in_right)
		c_right = _reverse_array(in_left)
	elif rot_steps == 3: # 270度
		c_top = _reverse_array(in_left)
		c_bottom = _reverse_array(in_right)
		c_left = in_bottom
		c_right = in_top

	# ==========================================
	# 2. 変換された結果を元の変数に代入して再描画
	# ==========================================
	conn_top = c_top
	conn_bottom = c_bottom
	conn_left = c_left
	conn_right = c_right
	
	queue_redraw() # 状態が変わったので再描画をリクエスト	

func _on_mouse_entered() -> void:
	is_hovered = true
	if not dragging:
		info_ui.visible = true
		z_index = 5

func _on_mouse_exited() -> void:
	is_hovered = false
	info_ui.visible = false
	if not dragging:
		z_index = 0

func _draw() -> void:
	if not piece_data: return
	
	var half = CELL_SIZE / 2.0
	var rect = Rect2(-half, -half, CELL_SIZE, CELL_SIZE)
	draw_rect(rect, Color.BLACK, false, 2.0)
	
	# ==========================================
	# 1. キャンバスの傾き（ノードの回転）に合わせてデータを補正（逆算）する
	# ==========================================
	var rot_steps = int(round(target_rotation / 90.0)) % 4
	if rot_steps < 0:
		rot_steps += 4
		
	var draw_top = piece_data.top_joints
	var draw_bottom = piece_data.bottom_joints
	var draw_left = piece_data.left_joints
	var draw_right = piece_data.right_joints
	
	if rot_steps == 1: # 90度
		draw_top = piece_data.right_joints
		draw_bottom = piece_data.left_joints
		draw_left = _reverse_array(piece_data.top_joints)
		draw_right = _reverse_array(piece_data.bottom_joints)
	elif rot_steps == 2: # 180度
		draw_top = _reverse_array(piece_data.bottom_joints)
		draw_bottom = _reverse_array(piece_data.top_joints)
		draw_left = _reverse_array(piece_data.right_joints)
		draw_right = _reverse_array(piece_data.left_joints)
	elif rot_steps == 3: # 270度
		draw_top = _reverse_array(piece_data.left_joints)
		draw_bottom = _reverse_array(piece_data.right_joints)
		draw_left = piece_data.bottom_joints
		draw_right = piece_data.top_joints

	# ==========================================
	# 2. 補正済みのデータを使って描画リストを作成
	# ==========================================
	# ★修正：piece_data ではなく、上で計算した draw_xxx を使います
	var sides = [
		{"data": draw_top,    "connected": conn_top,    "angle": -90.0},
		{"data": draw_bottom, "connected": conn_bottom, "angle": 90.0},
		{"data": draw_left,   "connected": conn_left,   "angle": 180.0},
		{"data": draw_right,  "connected": conn_right,  "angle": 0.0}
	]
	
	# ==========================================
	# 3. 描画の実行
	# ==========================================
	for side in sides:
		_draw_side_joints(side["data"], side["connected"], side["angle"], half)

# ★修正：引数に connected_array を追加し、色を変える処理を入れる
func _draw_side_joints(joints_array: Array, connected_array: Array, angle: float, dist: float) -> void:
	var pos_step = CELL_SIZE / 4.0
	var start_pos = -CELL_SIZE / 2.0
	
	for i in range(3):
		var type = joints_array[i]
		if type == Joint.Type.FLAT: continue
		
		# ★追加：このジョイントがはまっているか？
		var is_connected: bool = connected_array[i]
		
		var base_p = Vector2(dist, start_pos + pos_step * (i + 1))
		var p_left = base_p + Vector2(0, -JOINT_BASE_SIZE / 2.0)
		var p_right = base_p + Vector2(0, JOINT_BASE_SIZE / 2.0)
		var p_tip = base_p
		
		if type == Joint.Type.CONVEX:
			p_tip += Vector2(JOINT_DEPTH, 0)
			var points = PackedVector2Array([
				p_left.rotated(deg_to_rad(angle)),
				p_right.rotated(deg_to_rad(angle)),
				p_tip.rotated(deg_to_rad(angle))
			])
			# ★修正：繋がっていたらゴールド、そうでなければ緑
			var color = Color(1.0, 0.9, 0.1, 1.0) if is_connected else Color(0, 0.8, 0, 1.0)
			draw_colored_polygon(points, color)
			draw_polyline(PackedVector2Array([points[0], points[2], points[1]]), Color.BLACK, 1.0)
			
		elif type == Joint.Type.CONCAVE:
			p_tip += Vector2(-JOINT_DEPTH, 0)
			var points = PackedVector2Array([
				p_left.rotated(deg_to_rad(angle)),
				p_right.rotated(deg_to_rad(angle)),
				p_tip.rotated(deg_to_rad(angle))
			])
			# ★修正：繋がっていたらゴールド、そうでなければ赤
			var color = Color(1.0, 0.9, 0.1, 1.0) if is_connected else Color(1.0, 0.2, 0.2, 1.0)
			draw_colored_polygon(points, color)
			draw_polyline(PackedVector2Array([points[0], points[2], points[1]]), Color.BLACK, 1.0)


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if is_enemy:
		return
	
	# --- 左クリックの処理（ドラッグ＆ドロップ） ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			original_position = global_position
			offset = global_position - get_global_mouse_position()
			z_index = 10 
			info_ui.visible = false
			
			piece_picked_up.emit(self)
				
	# --- 右クリックの処理（戻す or 回転） ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if board_pos != Vector2i(-1, -1):
				reset_rotation_state()
				
				# 盤面にいる時に右クリック：盤面から手札に戻す
				piece_picked_up.emit(self)
				piece_dropped.emit(self, Vector2(-1000, -1000)) # 盤面外の座標を飛ばす
			else:
				# ★追加：手札にいる時に右クリック：90度回転させる！
				_rotate_90_degrees()

func _process(_delta: float) -> void:
	if dragging:
		global_position = get_global_mouse_position() + offset

func _on_drop() -> void:
	piece_dropped.emit(self, global_position)

func return_to_original() -> void:
	global_position = original_position

func _rotate_90_degrees() -> void:
	piece_data = piece_data.duplicate()
	var old_top = piece_data.top_joints.duplicate()
	var old_bottom = piece_data.bottom_joints.duplicate()
	var old_left = piece_data.left_joints.duplicate()
	var old_right = piece_data.right_joints.duplicate()

	# ★重要：90度回転すると、視覚的に「左から右」だったものが「下から上」になる等、
	# 配列の並び順が逆転する辺があるため、一部 reverse() が必須になります！
	
	piece_data.right_joints = old_top
	
	piece_data.bottom_joints = old_right
	piece_data.bottom_joints.reverse() # 反転！
	
	piece_data.left_joints = old_bottom
	
	piece_data.top_joints = old_left
	piece_data.top_joints.reverse() # 反転！

	target_rotation += 90.0
	var tween = create_tween()
	tween.tween_property(self, "rotation_degrees", target_rotation, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ★追加：UIノードは「マイナス」を付けて逆回転させ、常に真っ直ぐを保つ
	if info_ui:
		tween.tween_property(info_ui, "rotation_degrees", -target_rotation, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
func _reverse_array(arr: Array) -> Array:
	var new_arr = arr.duplicate()
	new_arr.reverse()
	return new_arr

func reset_rotation_state() -> void:
	# 1. 見た目の角度を0に戻す
	rotation_degrees = 0
	target_rotation = 0
	
	# 2. UIも0に戻す
	if info_ui:
		info_ui.rotation_degrees = 0
	
	# 3. 接続エフェクト（光）をすべて消す
	set_connections([false,false,false], [false,false,false], [false,false,false], [false,false,false])
	
	# 4. Zインデックスなども初期値に戻しておくと安全
	z_index = 0
	
	if original_data:
		piece_data = original_data

func _input(event: InputEvent) -> void:
	# ドロップ処理（左クリックを離した時）
	if dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
			z_index = 0
			_on_drop()
			if is_hovered:
				info_ui.visible = true
