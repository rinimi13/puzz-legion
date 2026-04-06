# res://Scripts/Core/MapScreen.gd
extends Control

# ==========================================
# ★修正：ピースと同じサイズ（正方形）にし、隙間をなくす
# ※現在80.0にしていますが、実際のピースの画像サイズ（64.0など）に合わせて数値を変更してください！
const CELL_SIZE: float = 80.0 
# ==========================================

@export var player_data: PlayerData 

var map_manager: MapManager
var hand_manager: HandManager
var current_player_pos: Vector2i = Vector2i(-1, -1)
var player_marker: ColorRect
var map_start_offset: Vector2

var placed_pieces: Dictionary = {}

func _ready() -> void:
	# ==========================================
	# ★最重要修正：MapScreen（画面全体）がマウス入力をブロックするのを防ぐ！
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ==========================================
	
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	
	map_manager = MapManager.new()
	add_child(map_manager)
	map_manager.generate_stage_1_map()
	
	_draw_map_grid()
	_init_player_position()
	
	hand_manager = HandManager.new()
	add_child(hand_manager)
	hand_manager.piece_picked_up_signal.connect(_on_piece_picked_up)
	hand_manager.piece_dropped_signal.connect(_on_piece_dropped)
	
	if DeckManager.master_deck.is_empty() and player_data != null:
		DeckManager.master_deck = player_data.starting_deck.duplicate()
		
	if DeckManager.master_deck.is_empty():
		print("⚠️エラー: プレイヤーデータがセットされていないため、デッキが空です！")
	else:
		DeckManager.prepare_battle()
		hand_manager.draw_new_hand(3, self)

func _draw_map_grid() -> void:
	var grid = map_manager.map_grid
	var total_width = MapManager.COLS * CELL_SIZE
	var total_height = MapManager.ROWS * CELL_SIZE
	
	# 画面中央にパズル盤面として配置
	map_start_offset = Vector2(
		(get_viewport_rect().size.x - total_width) / 2.0,
		(get_viewport_rect().size.y - total_height) / 2.0 - 50 
	)
	
	for y in range(MapManager.ROWS):
		for x in range(MapManager.COLS):
			var event_data: EventData = grid[y][x]
			if event_data.event_type == EventData.EventType.EMPTY:
				continue
				
			var cell_panel = ColorRect.new()
			cell_panel.size = Vector2(CELL_SIZE, CELL_SIZE) # 正方形に
			cell_panel.position = _get_cell_screen_pos(x, y)
			cell_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			# ★パズル盤面っぽくするために、枠線（黒）を少し残すテクニック
			var inner_color = Color()
			match event_data.event_type:
				EventData.EventType.START: inner_color = Color(0.3, 0.8, 0.3)
				EventData.EventType.BATTLE: inner_color = Color(0.6, 0.2, 0.2)
				EventData.EventType.ELITE: inner_color = Color(0.8, 0.1, 0.1)
				EventData.EventType.SHOP: inner_color = Color(0.8, 0.8, 0.2)
				EventData.EventType.REST: inner_color = Color(0.2, 0.6, 0.8)
				EventData.EventType.BOSS: inner_color = Color(0.9, 0.0, 0.9)
			
			# 枠線用の少し暗い背景
			cell_panel.color = Color(0, 0, 0, 0.5) 
			
			# 中身の色
			var inner_rect = ColorRect.new()
			inner_rect.color = inner_color
			inner_rect.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
			inner_rect.position = Vector2(1, 1)
			inner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell_panel.add_child(inner_rect)
			
			var label = Label.new()
			label.text = event_data.event_name
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			cell_panel.add_child(label)
			add_child(cell_panel)

func _init_player_position() -> void:
	for y in range(MapManager.ROWS):
		if map_manager.map_grid[y][0].event_type == EventData.EventType.START:
			current_player_pos = Vector2i(0, y)
			break
			
	player_marker = ColorRect.new()
	player_marker.color = Color(1.0, 1.0, 0.0, 0.4) 
	player_marker.size = Vector2(CELL_SIZE, CELL_SIZE)
	player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(player_marker)
	_update_marker_visual()

func _get_cell_screen_pos(x: int, y: int) -> Vector2:
	return map_start_offset + Vector2(x * CELL_SIZE, y * CELL_SIZE)

func _update_marker_visual() -> void:
	if current_player_pos.x != -1:
		player_marker.position = _get_cell_screen_pos(current_player_pos.x, current_player_pos.y)

func _on_piece_picked_up(_piece_node: PieceNode) -> void:
	pass

func _on_piece_dropped(piece_node: PieceNode, drop_pos: Vector2) -> void:
	var local_pos = drop_pos + Vector2(32, 32) - map_start_offset
	var grid_x = int(local_pos.x / CELL_SIZE)
	var grid_y = int(local_pos.y / CELL_SIZE)
	
	if grid_x < 0 or grid_x >= MapManager.COLS or grid_y < 0 or grid_y >= MapManager.ROWS:
		hand_manager.handle_placement_failure(piece_node)
		return
		
	var target_event: EventData = map_manager.map_grid[grid_y][grid_x]
	
	# ==========================================
	# ★修正：_is_valid_move に「置こうとしているピースのデータ」も渡して判定する
	if target_event.event_type == EventData.EventType.EMPTY or not _is_valid_move(piece_node.piece_data, grid_x, grid_y):
		hand_manager.handle_placement_failure(piece_node)
		return
		
	# ===== マスを覆う（移動）成功！ =====
	# ★追加：辞書に置いたピースのデータを記録する
	placed_pieces[Vector2i(grid_x, grid_y)] = piece_node.piece_data
	# ==========================================
	
	current_player_pos = Vector2i(grid_x, grid_y)
	_update_marker_visual()
	
	# デッキの捨て札に追加し、手札管理からは外す
	DeckManager.add_to_discard(piece_node.piece_data)
	hand_manager.remove_from_hand(piece_node)
	
	# ==========================================
	# ★変更：ピースを削除せず、マップにピッタリはめ込む！
	if piece_node.get_parent():
		piece_node.get_parent().remove_child(piece_node)
	add_child(piece_node)
	
	piece_node.input_pickable = false # もう掴めなくする
	piece_node.z_index = 0 # 手札用の最前面表示を解除
	
	# マスの中央にピッタリはまるように位置を調整
	piece_node.position = _get_cell_screen_pos(grid_x, grid_y) + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	
	# 踏んだマスだと分かりやすいように、ピースを少し暗くする
	piece_node.modulate = Color(0.6, 0.6, 0.6, 1.0)
	
	# プレイヤーマーカーの下に表示されるように順番を調整
	move_child(piece_node, player_marker.get_index())
	# ==========================================
	
	hand_manager.draw_new_hand(1, self)
	
	print("🐾 マスを覆いました！ 移動先: ", target_event.event_name)
	_execute_map_event(target_event)

func _execute_map_event(event: EventData) -> void:
	match event.event_type:
		EventData.EventType.BATTLE, EventData.EventType.ELITE, EventData.EventType.BOSS:
			print(">>> ⚔️ バトルシーンへ遷移します！ <<<")
			
			# ==========================================
			# ★追加：実際のバトルシーンへ遷移する
			# ※ "res://Main.tscn" の部分は、実際のバトル画面のシーン名に合わせて変更してください！
			get_tree().change_scene_to_file("res://Scenes/Main.tscn")
			# ==========================================
			
		EventData.EventType.REST:
			print("☕ HPを回復した！")
		EventData.EventType.SHOP:
			print("💰 ショップを開いた！")

func _is_valid_move(piece_data: PieceData, target_x: int, target_y: int) -> bool:
	var dx = target_x - current_player_pos.x
	var dy = target_y - current_player_pos.y
	
	# 1. 上下左右の1マス隣でなければ置けない
	if abs(dx) + abs(dy) != 1:
		return false
		
	# 2. 現在地が「STARTマス」の場合は、無条件で最初の一歩を踏み出せる
	var current_event = map_manager.map_grid[current_player_pos.y][current_player_pos.x]
	if current_event.event_type == EventData.EventType.START:
		return true 
		
	# 3. 現在地にあるピースのデータを取り出す
	if not placed_pieces.has(current_player_pos):
		return false # 万が一データがない場合はエラー弾き
		
	var current_piece_data: PieceData = placed_pieces[current_player_pos]
	var match_count = 0
	
	# 4. バトルシステムと同じ「凹凸が噛み合っているか」の判定
	if dx == 1: # 右へ進む場合（現在地の右辺 vs 新しいピースの左辺）
		for i in range(3):
			if _is_interlocking(current_piece_data.right_joints[i], piece_data.left_joints[i]): match_count += 1
	elif dx == -1: # 左へ戻る場合（※左に進めるようにするかはゲーム性次第です）
		for i in range(3):
			if _is_interlocking(current_piece_data.left_joints[i], piece_data.right_joints[i]): match_count += 1
	elif dy == 1: # 下へ進む場合
		for i in range(3):
			if _is_interlocking(current_piece_data.bottom_joints[i], piece_data.top_joints[i]): match_count += 1
	elif dy == -1: # 上へ進む場合
		for i in range(3):
			if _is_interlocking(current_piece_data.top_joints[i], piece_data.bottom_joints[i]): match_count += 1
			
	# 1箇所以上ジョイントが成功していれば移動可能！
	if match_count > 0:
		return true
	else:
		print("ジョイントが噛み合わないため配置できません！")
		return false

## ジョイントの凹(-1)と凸(1)が噛み合うかを判定する関数
func _is_interlocking(joint_a: int, joint_b: int) -> bool:
	return (joint_a == 1 and joint_b == -1) or (joint_a == -1 and joint_b == 1)
