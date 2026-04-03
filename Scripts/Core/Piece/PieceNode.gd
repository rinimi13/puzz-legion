# res://Scripts/Core/Piece/PieceNode.gd
extends Area2D
class_name PieceNode

## ピース（駒）がドラッグ＆ドロップされたときや、持ち上げられたときに
## 監督（BoardManager / HandManager）に知らせるためのシグナル。
signal piece_dropped(piece_node, drop_position)
signal piece_picked_up(piece_node)

# ==========================================
# 1. 定数・変数の宣言
# ==========================================
const CELL_SIZE: float = 64.0
const JOINT_BASE_SIZE: float = 16.0
const JOINT_DEPTH: float = 12.0

@export var piece_data: PieceData

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
var target_rotation: float = 0.0
var original_data: PieceData

# ジョイントが正しく噛み合って光るべきかを判定するフラグ
var conn_top: Array = [false, false, false]
var conn_bottom: Array = [false, false, false]
var conn_left: Array = [false, false, false]
var conn_right: Array = [false, false, false]


# ==========================================
# 2. 初期化・データ更新
# ==========================================

## ノードが生成されたときに呼ばれる初期化処理。
func _ready() -> void:
	input_pickable = true
	character_sprite.show_behind_parent = true
	
	if piece_data != null:
		original_data = piece_data
		update_visuals()

## データ（PieceData）をもとに、アイコン画像や名前、効果値の表示を更新する処理。
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

## 回転状態などを初期状態（0度）に戻し、光るエフェクトもリセットする処理。
## 盤面から手札に戻る時や、捨て札に送られる時に呼ばれる。
func reset_rotation_state() -> void:
	rotation_degrees = 0
	target_rotation = 0
	if info_ui: info_ui.rotation_degrees = 0
	
	set_connections([false,false,false], [false,false,false], [false,false,false], [false,false,false])
	z_index = 0
	
	if original_data:
		piece_data = original_data


# ==========================================
# 3. 入力・ドラッグ操作
# ==========================================

## マウスがピースの上に重なったときのUI表示処理。
func _on_mouse_entered() -> void:
	is_hovered = true
	if not dragging:
		info_ui.visible = true
		z_index = 5

## マウスがピースから離れたときのUI非表示処理。
func _on_mouse_exited() -> void:
	is_hovered = false
	info_ui.visible = false
	if not dragging:
		z_index = 0

## ピースの上でクリックされたときの処理（持ち上げ、右クリック）。
func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if is_enemy: return
	
	# 左クリック（持ち上げる）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			original_position = global_position
			offset = global_position - get_global_mouse_position()
			z_index = 10 
			info_ui.visible = false
			piece_picked_up.emit(self)
				
	# 右クリック（回転させる or 盤面から戻す）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if board_pos != Vector2i(-1, -1):
				# 盤面にいる場合：手札に戻す
				reset_rotation_state()
				piece_picked_up.emit(self)
				piece_dropped.emit(self, Vector2(-1000, -1000))
			else:
				# 手札にいる場合：90度回転させる
				_rotate_90_degrees()

## 画面のどこでクリックを離しても確実にドロップさせるための全体入力処理。
func _input(event: InputEvent) -> void:
	if dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
			z_index = 0
			_on_drop()
			if is_hovered:
				info_ui.visible = true

## ドラッグ中、マウスに追従して位置を更新する処理。
func _process(_delta: float) -> void:
	if dragging:
		global_position = get_global_mouse_position() + offset

## ドラッグを離したときにシグナルを発信する処理。
func _on_drop() -> void:
	piece_dropped.emit(self, global_position)


# ==========================================
# 4. 回転処理
# ==========================================

## ピースを時計回りに90度回転させ、内部のジョイントデータも入れ替える処理。
func _rotate_90_degrees() -> void:
	piece_data = piece_data.duplicate()
	var old_top = piece_data.top_joints.duplicate()
	var old_bottom = piece_data.bottom_joints.duplicate()
	var old_left = piece_data.left_joints.duplicate()
	var old_right = piece_data.right_joints.duplicate()

	# データ配列の並べ替え（底と上は配列の並び順が反転する）
	piece_data.right_joints = old_top
	piece_data.bottom_joints = old_right
	piece_data.bottom_joints.reverse()
	piece_data.left_joints = old_bottom
	piece_data.top_joints = old_left
	piece_data.top_joints.reverse()

	target_rotation += 90.0
	var tween = create_tween()
	tween.tween_property(self, "rotation_degrees", target_rotation, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# UIの文字が逆さまにならないようにマイナス方向に回す
	if info_ui:
		tween.tween_property(info_ui, "rotation_degrees", -target_rotation, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
func _reverse_array(arr: Array) -> Array:
	var new_arr = arr.duplicate()
	new_arr.reverse()
	return new_arr


# ==========================================
# 5. ジョイントの描画・接続エフェクト
# ==========================================

## BoardManager から受け取った「どの辺が繋がっているか」の情報を、
## 自分の回転状態に合わせて補正し、記憶する処理。
func set_connections(in_top: Array, in_bottom: Array, in_left: Array, in_right: Array) -> void:
	var rot_steps = int(round(target_rotation / 90.0)) % 4
	if rot_steps < 0: rot_steps += 4
		
	var c_top = in_top
	var c_bottom = in_bottom
	var c_left = in_left
	var c_right = in_right
	
	if rot_steps == 1:
		c_top = in_right; c_bottom = in_left; c_left = _reverse_array(in_top); c_right = _reverse_array(in_bottom)
	elif rot_steps == 2:
		c_top = _reverse_array(in_bottom); c_bottom = _reverse_array(in_top); c_left = _reverse_array(in_right); c_right = _reverse_array(in_left)
	elif rot_steps == 3:
		c_top = _reverse_array(in_left); c_bottom = _reverse_array(in_right); c_left = in_bottom; c_right = in_top

	conn_top = c_top
	conn_bottom = c_bottom
	conn_left = c_left
	conn_right = c_right
	
	queue_redraw()

## CanvasItem の描画処理（毎フレームや queue_redraw が呼ばれたときに実行）。
## ピースの枠線と、4辺の凹凸を描画する。
func _draw() -> void:
	if not piece_data: return
	
	var half = CELL_SIZE / 2.0
	draw_rect(Rect2(-half, -half, CELL_SIZE, CELL_SIZE), Color.BLACK, false, 2.0)
	
	var rot_steps = int(round(target_rotation / 90.0)) % 4
	if rot_steps < 0: rot_steps += 4
		
	var draw_top = piece_data.top_joints
	var draw_bottom = piece_data.bottom_joints
	var draw_left = piece_data.left_joints
	var draw_right = piece_data.right_joints
	
	if rot_steps == 1:
		draw_top = piece_data.right_joints; draw_bottom = piece_data.left_joints; draw_left = _reverse_array(piece_data.top_joints); draw_right = _reverse_array(piece_data.bottom_joints)
	elif rot_steps == 2:
		draw_top = _reverse_array(piece_data.bottom_joints); draw_bottom = _reverse_array(piece_data.top_joints); draw_left = _reverse_array(piece_data.right_joints); draw_right = _reverse_array(piece_data.left_joints)
	elif rot_steps == 3:
		draw_top = _reverse_array(piece_data.left_joints); draw_bottom = _reverse_array(piece_data.right_joints); draw_left = piece_data.bottom_joints; draw_right = piece_data.top_joints

	var sides = [
		{"data": draw_top,    "connected": conn_top,    "angle": -90.0},
		{"data": draw_bottom, "connected": conn_bottom, "angle": 90.0},
		{"data": draw_left,   "connected": conn_left,   "angle": 180.0},
		{"data": draw_right,  "connected": conn_right,  "angle": 0.0}
	]
	
	for side in sides:
		_draw_side_joints(side["data"], side["connected"], side["angle"], half)

## 1つの辺に対する凹凸を描画し、繋がっている場合は色を光らせる（ゴールドにする）処理。
func _draw_side_joints(joints_array: Array, connected_array: Array, angle: float, dist: float) -> void:
	var pos_step = CELL_SIZE / 4.0
	var start_pos = -CELL_SIZE / 2.0
	
	for i in range(3):
		var type = joints_array[i]
		if type == Joint.Type.FLAT: continue
		
		var is_connected: bool = connected_array[i]
		var base_p = Vector2(dist, start_pos + pos_step * (i + 1))
		var p_left = base_p + Vector2(0, -JOINT_BASE_SIZE / 2.0)
		var p_right = base_p + Vector2(0, JOINT_BASE_SIZE / 2.0)
		var p_tip = base_p
		
		if type == Joint.Type.CONVEX:
			p_tip += Vector2(JOINT_DEPTH, 0)
			var points = PackedVector2Array([ p_left.rotated(deg_to_rad(angle)), p_right.rotated(deg_to_rad(angle)), p_tip.rotated(deg_to_rad(angle)) ])
			var color = Color(1.0, 0.9, 0.1, 1.0) if is_connected else Color(0, 0.8, 0, 1.0)
			draw_colored_polygon(points, color)
			draw_polyline(PackedVector2Array([points[0], points[2], points[1]]), Color.BLACK, 1.0)
			
		elif type == Joint.Type.CONCAVE:
			p_tip += Vector2(-JOINT_DEPTH, 0)
			var points = PackedVector2Array([ p_left.rotated(deg_to_rad(angle)), p_right.rotated(deg_to_rad(angle)), p_tip.rotated(deg_to_rad(angle)) ])
			var color = Color(1.0, 0.9, 0.1, 1.0) if is_connected else Color(1.0, 0.2, 0.2, 1.0)
			draw_colored_polygon(points, color)
			draw_polyline(PackedVector2Array([points[0], points[2], points[1]]), Color.BLACK, 1.0)
